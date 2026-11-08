#!/usr/bin/env bash
# phase 3 — start virtual display, x11vnc, and Android emulator; wait for boot
set -euo pipefail

ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT:-/opt/android-sdk}"
AVD_NAME="${AVD_NAME:-S23_Unit}"
DISP="${DISPLAY:-:1}"
VNC_PORT="${VNC_PORT:-5901}"
export PATH="${ANDROID_SDK_ROOT}/emulator:\
${ANDROID_SDK_ROOT}/platform-tools:\
${ANDROID_SDK_ROOT}/cmdline-tools/latest/bin:\
${PATH}"
export ANDROID_AVD_HOME="${HOME}/.android/avd"
export DISPLAY="${DISP}"

# ── virtual framebuffer 1920×1080 ────────────────────────────────────────────
Xvfb "${DISP}" \
  -screen 0 1920x1080x24 \
  -ac \
  +extension GLX \
  +extension RANDR \
  +render \
  -noreset \
  -dpi 96 \
  &
echo "$!" > /tmp/xvfb.pid
sleep 2

xdpyinfo -display "${DISP}" >/dev/null 2>&1 \
  || { echo "Xvfb failed to start" >&2; exit 1; }
echo "xvfb: running on ${DISP}"

# ── x11vnc ────────────────────────────────────────────────────────────────────
x11vnc \
  -display "${DISP}" \
  -rfbport "${VNC_PORT}" \
  -nopw \
  -shared \
  -forever \
  -noxdamage \
  -noxfixes \
  -quiet \
  -bg \
  -o /tmp/x11vnc.log
echo "x11vnc: port ${VNC_PORT}"

# ── attempt host-GPU first, fall back to swiftshader ─────────────────────────
GPU_MODE="swiftshader_indirect"
if [[ -e /dev/kvm ]]; then
  GPU_MODE="host"
  echo "emulator: using host GPU mode"
else
  echo "emulator: using swiftshader (no KVM)"
fi

# ── boot-time property injections (pre-spoof) ─────────────────────────────────
# These are applied by the QEMU layer before Android userspace reads them.
# ro.* overwrites cannot be guaranteed from adb after boot — this is the safe path.
PROP_ARGS=(
  -prop ro.product.model=SM-S911B
  -prop ro.product.name=dm1q
  -prop ro.product.device=dm1q
  -prop ro.product.brand=samsung
  -prop ro.product.manufacturer=samsung
  -prop ro.product.marketname="Galaxy S23"
  -prop ro.board.platform=kalama
  -prop ro.hardware=qcom
  -prop ro.chipname=SM8550
  -prop ro.soc.manufacturer=Qualcomm
  -prop ro.soc.model=SM8550
  -prop ro.build.version.release=13
  -prop ro.build.version.sdk=33
  -prop ro.build.version.security_patch=2023-11-01
  -prop ro.build.display.id=TP1A.220624.014.S911BXXS4CWI3
  -prop ro.build.fingerprint=samsung/dm1qxx/dm1q:13/TP1A.220624.014/S911BXXS4CWI3:user/release-keys
  -prop ro.build.type=user
  -prop ro.build.tags=release-keys
  -prop ro.product.cpu.abi=arm64-v8a
  -prop ro.product.cpu.abilist=arm64-v8a,armeabi-v7a,armeabi
  -prop ro.hardware.egl=adreno
  -prop ro.hardware.vulkan=adreno
  -prop ro.opengles.version=196610
  -prop ro.sf.lcd_density=425
  -prop ro.com.google.clientidbase=android-samsung-kalama
  -prop net.bt.name=Samsung
  -prop ro.com.samsung.chipset.name="Snapdragon 8 Gen 2"
)

# ── start emulator ────────────────────────────────────────────────────────────
emulator \
  -avd "${AVD_NAME}" \
  -no-window \
  -no-audio \
  -no-snapshot \
  -no-boot-anim \
  -gpu "${GPU_MODE}" \
  -memory 8192 \
  -cores 4 \
  -wipe-data \
  -accel auto \
  "${PROP_ARGS[@]}" \
  -qemu -smp 8,cores=4,threads=2 \
  > /tmp/emulator.log 2>&1 \
  &
echo "$!" > /tmp/emulator.pid
echo "emulator: pid $(cat /tmp/emulator.pid)"

# ── wait for Android to fully boot (up to 5 minutes) ─────────────────────────
echo "waiting for Android boot..."
BOOT_TIMEOUT=300
ELAPSED=0
until adb shell getprop sys.boot_completed 2>/dev/null | grep -q "^1$"; do
  sleep 5
  ELAPSED=$((ELAPSED + 5))
  if (( ELAPSED >= BOOT_TIMEOUT )); then
    echo "boot timeout after ${BOOT_TIMEOUT}s" >&2
    exit 1
  fi
  echo "  waiting... ${ELAPSED}s"
done

echo "emulator: booted in ${ELAPSED}s"
sleep 3
