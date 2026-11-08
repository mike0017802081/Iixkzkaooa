#!/usr/bin/env python3
"""
noVNC authentication gate.

Flow:
  1. User hits https://<tunnel>/ → served the password form.
  2. User POSTs password → checked server-side (never echoed).
  3. On match: session cookie set, redirect to /vnc/.
  4. /vnc/* and WebSocket (/websockify) proxied to noVNC on 127.0.0.1:NOVNC_PORT.
  5. Wrong password: redirect back to / with ?e=1 (no hint in response body).

The password is read once from $SESSION_KEY at startup and stored only as a
hash — it is never logged, never serialised, never sent to the client.
"""

import asyncio
import hashlib
import hmac
import html
import logging
import os
import secrets
import sys
import time

# ── optional aiohttp; fall back to pure-asyncio TCP proxy ────────────────────
try:
    import aiohttp
    import aiohttp.web
    HAS_AIOHTTP = True
except ImportError:
    HAS_AIOHTTP = False

GATE_PORT = int(os.environ.get('GATE_PORT', '8080'))
NOVNC_HOST = '127.0.0.1'
NOVNC_PORT = int(os.environ.get('NOVNC_PORT', '6080'))

# ── derive password hash once at startup (key never stored raw) ──────────────
_raw_key = os.environ.get('SESSION_KEY', '')
if not _raw_key:
    sys.stderr.write('SESSION_KEY not set — cannot start gate\n')
    sys.exit(1)
PASS_HASH: str = hashlib.sha256(_raw_key.encode()).hexdigest()
del _raw_key  # remove from process memory

# active session tokens: token → issued_at (float)
TOKENS: dict[str, float] = {}
TOKEN_TTL = 86400  # 24 hours

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s gate %(levelname)s %(message)s',
    datefmt='%H:%M:%S',
)
log = logging.getLogger('gate')

# ── HTML templates ────────────────────────────────────────────────────────────
_LOGIN_HTML = """\
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Connect</title>
<style>
*{box-sizing:border-box;margin:0;padding:0}
body{min-height:100vh;display:flex;align-items:center;justify-content:center;
     background:#0d1117;font-family:system-ui,sans-serif;color:#e6edf3}
.card{background:#161b22;border:1px solid #30363d;border-radius:12px;
      padding:2.5rem 3rem;width:360px;max-width:95vw;text-align:center}
h2{font-size:1.3rem;font-weight:600;margin-bottom:1.6rem;letter-spacing:.02em}
.err{color:#f85149;font-size:.85rem;margin-bottom:.9rem}
input[type=password]{width:100%;padding:.7rem 1rem;border-radius:7px;
  border:1px solid #30363d;background:#0d1117;color:#e6edf3;
  font-size:1rem;outline:none;transition:border .2s}
input[type=password]:focus{border-color:#58a6ff}
button{margin-top:1.1rem;width:100%;padding:.75rem;border-radius:7px;
  border:none;background:#238636;color:#fff;font-size:1rem;
  font-weight:600;cursor:pointer;transition:background .2s}
button:hover{background:#2ea043}
</style>
</head>
<body>
<div class="card">
  <h2>Remote Session</h2>
  {ERR_BLOCK}
  <form method="POST" action="/auth" autocomplete="off">
    <input type="password" name="pw" placeholder="Access key" autofocus required>
    <button type="submit">Connect</button>
  </form>
</div>
</body>
</html>
"""

_ERR_BLOCK = '<p class="err">Incorrect — try again.</p>'


def _login_html(error: bool = False) -> str:
    block = _ERR_BLOCK if error else ''
    return _LOGIN_HTML.replace('{ERR_BLOCK}', block)


def _check_pass(candidate: str) -> bool:
    candidate_hash = hashlib.sha256(candidate.encode()).hexdigest()
    return hmac.compare_digest(candidate_hash, PASS_HASH)


def _issue_token() -> str:
    tok = secrets.token_hex(48)
    TOKENS[tok] = time.monotonic()
    return tok


def _validate_token(tok: str) -> bool:
    issued = TOKENS.get(tok)
    if issued is None:
        return False
    if time.monotonic() - issued > TOKEN_TTL:
        del TOKENS[tok]
        return False
    return True


def _purge_tokens():
    cutoff = time.monotonic() - TOKEN_TTL
    stale = [k for k, v in TOKENS.items() if v < cutoff]
    for k in stale:
        del TOKENS[k]


# ── aiohttp implementation ────────────────────────────────────────────────────
if HAS_AIOHTTP:
    async def _handle_root(req: aiohttp.web.Request) -> aiohttp.web.Response:
        error = req.rel_url.query.get('e') == '1'
        return aiohttp.web.Response(
            content_type='text/html',
            text=_login_html(error),
        )

    async def _handle_auth(req: aiohttp.web.Request) -> aiohttp.web.Response:
        try:
            data = await req.post()
        except Exception:
            raise aiohttp.web.HTTPFound('/?e=1')
        pw = data.get('pw', '')
        if _check_pass(pw):
            tok = _issue_token()
            resp = aiohttp.web.HTTPFound('/vnc/')
            resp.set_cookie(
                'st',
                tok,
                httponly=True,
                samesite='Strict',
                max_age=TOKEN_TTL,
            )
            log.info('auth: success, token issued')
            return resp
        log.info('auth: failed attempt')
        raise aiohttp.web.HTTPFound('/?e=1')

    async def _proxy_http(req: aiohttp.web.Request) -> aiohttp.web.StreamResponse:
        tok = req.cookies.get('st', '')
        if not _validate_token(tok):
            raise aiohttp.web.HTTPFound('/')
        # forward to noVNC
        path = req.match_info.get('path', '')
        target = f'http://{NOVNC_HOST}:{NOVNC_PORT}/{path}'
        async with aiohttp.ClientSession() as session:
            async with session.request(
                req.method,
                target,
                headers={
                    k: v for k, v in req.headers.items()
                    if k.lower() not in ('host', 'connection')
                },
                data=await req.read(),
                allow_redirects=False,
            ) as upstream:
                resp = aiohttp.web.StreamResponse(
                    status=upstream.status,
                    headers={
                        k: v for k, v in upstream.headers.items()
                        if k.lower() not in ('transfer-encoding', 'connection')
                    },
                )
                await resp.prepare(req)
                async for chunk in upstream.content.iter_any():
                    await resp.write(chunk)
                return resp

    async def _proxy_ws(req: aiohttp.web.Request) -> aiohttp.web.WebSocketResponse:
        tok = req.cookies.get('st', '')
        if not _validate_token(tok):
            raise aiohttp.web.HTTPForbidden()
        ws_client = aiohttp.web.WebSocketResponse()
        await ws_client.prepare(req)
        target = f'ws://{NOVNC_HOST}:{NOVNC_PORT}/websockify'
        async with aiohttp.ClientSession() as session:
            async with session.ws_connect(target) as ws_upstream:
                async def fwd_up():
                    async for msg in ws_client:
                        if msg.type == aiohttp.WSMsgType.BINARY:
                            await ws_upstream.send_bytes(msg.data)
                        elif msg.type == aiohttp.WSMsgType.TEXT:
                            await ws_upstream.send_str(msg.data)
                        elif msg.type in (
                            aiohttp.WSMsgType.CLOSE,
                            aiohttp.WSMsgType.ERROR,
                        ):
                            break

                async def fwd_down():
                    async for msg in ws_upstream:
                        if msg.type == aiohttp.WSMsgType.BINARY:
                            await ws_client.send_bytes(msg.data)
                        elif msg.type == aiohttp.WSMsgType.TEXT:
                            await ws_client.send_str(msg.data)
                        elif msg.type in (
                            aiohttp.WSMsgType.CLOSE,
                            aiohttp.WSMsgType.ERROR,
                        ):
                            break

                await asyncio.gather(fwd_up(), fwd_down())
        return ws_client

    def _build_app() -> aiohttp.web.Application:
        app = aiohttp.web.Application()
        app.router.add_get('/', _handle_root)
        app.router.add_post('/auth', _handle_auth)
        app.router.add_route('*', '/websockify', _proxy_ws)
        app.router.add_route('*', '/vnc/{path:.*}', _proxy_http)
        app.router.add_route('*', '/{path:.*}', _proxy_http)
        return app

    async def _main():
        app = _build_app()
        runner = aiohttp.web.AppRunner(app)
        await runner.setup()
        site = aiohttp.web.TCPSite(runner, '0.0.0.0', GATE_PORT)
        await site.start()
        log.info('gate: listening on 0.0.0.0:%d → novnc %s:%d',
                 GATE_PORT, NOVNC_HOST, NOVNC_PORT)
        while True:
            _purge_tokens()
            await asyncio.sleep(300)

# ── pure-asyncio fallback (no aiohttp) ───────────────────────────────────────
else:
    import http.server
    import io
    import socket
    import threading
    import urllib.parse

    class _GateHandler(http.server.BaseHTTPRequestHandler):
        def log_message(self, fmt, *args):  # silence default access log
            pass

        def _set_cookie(self, tok: str):
            return (
                f'Set-Cookie: st={tok}; HttpOnly; SameSite=Strict; '
                f'Max-Age={TOKEN_TTL}; Path=/\r\n'
            )

        def _tok_from_header(self) -> str:
            cookie_hdr = self.headers.get('Cookie', '')
            for part in cookie_hdr.split(';'):
                k, _, v = part.strip().partition('=')
                if k.strip() == 'st':
                    return v.strip()
            return ''

        def do_GET(self):
            parsed = urllib.parse.urlparse(self.path)
            qs = urllib.parse.parse_qs(parsed.query)
            tok = self._tok_from_header()

            if parsed.path in ('/', ''):
                error = qs.get('e', [''])[0] == '1'
                body = _login_html(error).encode()
                self.send_response(200)
                self.send_header('Content-Type', 'text/html; charset=utf-8')
                self.send_header('Content-Length', str(len(body)))
                self.end_headers()
                self.wfile.write(body)
                return

            if not _validate_token(tok):
                self.send_response(302)
                self.send_header('Location', '/')
                self.end_headers()
                return

            # proxy to noVNC
            self._proxy_http()

        def do_POST(self):
            parsed = urllib.parse.urlparse(self.path)
            if parsed.path == '/auth':
                length = int(self.headers.get('Content-Length', '0'))
                body = self.rfile.read(length)
                params = urllib.parse.parse_qs(body.decode())
                pw_list = params.get('pw', [''])
                pw = pw_list[0] if pw_list else ''
                if _check_pass(pw):
                    tok = _issue_token()
                    log.info('auth: success')
                    self.send_response(302)
                    self.send_header('Location', '/vnc/')
                    self.send_header(*('Set-Cookie', self._set_cookie(tok).split(': ', 1)[1]))
                    self.end_headers()
                else:
                    log.info('auth: failed')
                    self.send_response(302)
                    self.send_header('Location', '/?e=1')
                    self.end_headers()
            else:
                self.send_response(404)
                self.end_headers()

        def _proxy_http(self):
            import http.client
            path = self.path
            if path.startswith('/vnc'):
                path = path[4:] or '/'
            conn = http.client.HTTPConnection(NOVNC_HOST, NOVNC_PORT, timeout=30)
            try:
                headers = {
                    k: v for k, v in self.headers.items()
                    if k.lower() not in ('host', 'connection', 'cookie')
                }
                conn.request(self.command, path, headers=headers)
                resp = conn.getresponse()
                self.send_response(resp.status)
                for k, v in resp.getheaders():
                    if k.lower() not in ('transfer-encoding', 'connection'):
                        self.send_header(k, v)
                self.end_headers()
                while True:
                    chunk = resp.read(65536)
                    if not chunk:
                        break
                    self.wfile.write(chunk)
            except Exception as exc:
                log.warning('proxy error: %s', exc)
            finally:
                conn.close()

    def _run_fallback():
        server = http.server.ThreadingHTTPServer(('0.0.0.0', GATE_PORT), _GateHandler)
        log.info('gate (fallback): listening on 0.0.0.0:%d → novnc %s:%d',
                 GATE_PORT, NOVNC_HOST, NOVNC_PORT)
        server.serve_forever()

    async def _main():
        loop = asyncio.get_event_loop()
        await loop.run_in_executor(None, _run_fallback)


if __name__ == '__main__':
    try:
        asyncio.run(_main())
    except KeyboardInterrupt:
        pass
