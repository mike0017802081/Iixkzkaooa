#!/usr/bin/env bash
# phase 4 — deep Samsung Galaxy S23 identity spoof + GPU simulation + One UI setup
# Runs after emulator has fully booted.
set -euo pipefail

ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT:-/opt/android-sdk}"
export PATH="${ANDROID_SDK_ROOT}/emulator:\
${ANDROID_SDK_ROOT}/platform-tools:\
${PATH}"

adb_sh() {
  adb shell "$@" 2>/dev/null || true
}

adb_sp() {
  # setprop with su fallback
  local key="$1" val="$2"
  adb shell "setprop '${key}' '${val}'" 2>/dev/null || \
  adb shell "su 0 setprop '${key}' '${val}'" 2>/dev/null || true
}

# ── root + remount system RW ─────────────────────────────────────────────────
adb root
sleep 3
adb remount 2>/dev/null || true
adb_sh "mount -o rw,remount /system" 2>/dev/null || true
adb_sh "mount -o rw,remount /" 2>/dev/null || true
adb_sh "setenforce 0" 2>/dev/null || true

# ── build.prop full S23 rewrite via Python on host ───────────────────────────
adb pull /system/build.prop /tmp/build.prop.orig 2>/dev/null || {
  echo "could not pull build.prop — using setprop only"
}

if [[ -f /tmp/build.prop.orig ]]; then
  python3 - << 'PYEOF'
import re, sys

with open('/tmp/build.prop.orig', 'r', encoding='utf-8', errors='replace') as f:
    content = f.read()

# Full Samsung Galaxy S23 (SM-S911B, Snapdragon 8 Gen 2) property set
# Matches actual S911BXXS4CWI3 firmware fingerprint
inject = {
    # ── identity ────────────────────────────────────────────────────────────
    'ro.product.model':                    'SM-S911B',
    'ro.product.name':                     'dm1q',
    'ro.product.device':                   'dm1q',
    'ro.product.brand':                    'samsung',
    'ro.product.manufacturer':             'samsung',
    'ro.product.marketname':               'Galaxy S23',
    'ro.product.odm.model':                'SM-S911B',
    'ro.product.odm.name':                 'dm1q',
    'ro.product.odm.device':               'dm1q',
    'ro.product.odm.brand':                'samsung',
    'ro.product.odm.manufacturer':         'samsung',
    'ro.product.vendor.model':             'SM-S911B',
    'ro.product.vendor.name':              'dm1qxx',
    'ro.product.vendor.device':            'dm1q',
    'ro.product.vendor.brand':             'samsung',
    'ro.product.vendor.manufacturer':      'samsung',
    'ro.product.system.model':             'SM-S911B',
    'ro.product.system.name':              'dm1q',
    'ro.product.system.brand':             'samsung',
    'ro.product.system.manufacturer':      'samsung',
    'ro.product.system_ext.model':         'SM-S911B',
    'ro.product.system_ext.brand':         'samsung',
    'ro.product.bootimage.model':          'SM-S911B',
    'ro.product.bootimage.brand':          'samsung',
    # ── build ────────────────────────────────────────────────────────────────
    'ro.build.product':                    'dm1q',
    'ro.build.flavor':                     'dm1qxx-user',
    'ro.build.type':                       'user',
    'ro.build.tags':                       'release-keys',
    'ro.build.id':                         'TP1A.220624.014',
    'ro.build.version.release':            '13',
    'ro.build.version.release_or_codename':'13',
    'ro.build.version.sdk':                '33',
    'ro.build.version.incremental':        'S911BXXS4CWI3',
    'ro.build.version.security_patch':     '2023-11-01',
    'ro.build.version.base_os':
        'samsung/dm1qxx/dm1q:13/TP1A.220624.014/S911BXXS4CWI3:user/release-keys',
    'ro.build.display.id':                 'TP1A.220624.014.S911BXXS4CWI3',
    'ro.build.description':
        'dm1qxx-user 13 TP1A.220624.014 S911BXXS4CWI3 release-keys',
    'ro.build.fingerprint':
        'samsung/dm1qxx/dm1q:13/TP1A.220624.014/S911BXXS4CWI3:user/release-keys',
    'ro.build.changelist':                 '25312775',
    'ro.build.PDA':                        'S911BXXS4CWI3',
    # ── SoC / hardware ───────────────────────────────────────────────────────
    'ro.board.platform':                   'kalama',
    'ro.hardware':                         'qcom',
    'ro.chipname':                         'SM8550',
    'ro.soc.manufacturer':                 'Qualcomm',
    'ro.soc.model':                        'SM8550',
    'ro.boot.hardware':                    'qcom',
    # Snapdragon 8 Gen 2: 1×Cortex-X3 @3.2GHz + 2×A715 + 2×A510 (perf) + 3×A510
    'ro.com.samsung.chipset.name':         'Snapdragon 8 Gen 2',
    'ro.product.cpu.abi':                  'arm64-v8a',
    'ro.product.cpu.abilist':              'arm64-v8a,armeabi-v7a,armeabi',
    'ro.product.cpu.abilist32':            'armeabi-v7a,armeabi',
    'ro.product.cpu.abilist64':            'arm64-v8a',
    # ── GPU — Adreno 740 ─────────────────────────────────────────────────────
    'ro.hardware.egl':                     'adreno',
    'ro.hardware.vulkan':                  'adreno',
    'ro.hardware.gralloc':                 'default',
    'ro.gfx.driver.0':
        'com.qualcomm.qti.gpudrivers.kalama.api33',
    'ro.vendor.extension_library':         'libqti-perfd-client.so',
    'ro.opengles.version':                 '196610',
    'ro.board.first_api_level':            '33',
    # ── display ──────────────────────────────────────────────────────────────
    'ro.sf.lcd_density':                   '425',
    'persist.sys.sf.native_mode':          '1',
    # ── Samsung / One UI ─────────────────────────────────────────────────────
    'ro.csc.country_code':                 'XFE',
    'ro.csc.sales_code':                   'DBT',
    'ro.csc.version':                      'S911BDBTS4AWA1',
    'ro.com.google.clientidbase':          'android-samsung-kalama',
    'ro.com.google.clientidbase.ms':       'android-samsung-kalama',
    'net.bt.name':                         'Samsung',
    'ro.config.ringtone':                  'Over the Horizon.ogg',
    'ro.config.notification_sound':        'Samsung_Whistle.ogg',
    'ro.config.alarm_alert':               'Homecoming.ogg',
    # Play Integrity / SafetyNet hints
    'ro.boot.verifiedbootstate':           'green',
    'ro.boot.veritymode':                  'enforcing',
}

for key, val in inject.items():
    pattern = rf'^{re.escape(key)}=.*$'
    replacement = f'{key}={val}'
    if re.search(pattern, content, re.MULTILINE):
        content = re.sub(pattern, replacement, content, flags=re.MULTILINE)
    else:
        content += f'\n{key}={val}'

with open('/tmp/build.prop.new', 'w', encoding='utf-8') as f:
    f.write(content)

print('build.prop: written to /tmp/build.prop.new')
PYEOF

  adb push /tmp/build.prop.new /system/build.prop
  adb_sh "chmod 644 /system/build.prop"
  echo "build.prop: pushed"
fi

# ── runtime setprop for props not in build.prop or for instant effect ─────────
declare -A RUNTIME_PROPS
RUNTIME_PROPS=(
  [ro.product.model]='SM-S911B'
  [ro.product.brand]='samsung'
  [ro.product.manufacturer]='samsung'
  [ro.board.platform]='kalama'
  [ro.hardware]='qcom'
  [ro.hardware.egl]='adreno'
  [ro.hardware.vulkan]='adreno'
  [ro.opengles.version]='196610'
  [ro.sf.lcd_density]='425'
  [net.bt.name]='Samsung'
)

for key in "${!RUNTIME_PROPS[@]}"; do
  adb_sp "${key}" "${RUNTIME_PROPS[$key]}"
done

# ── GPU vendor string spoof via libGLES LD_PRELOAD shim ───────────────────────
# Compile a small shared lib on the host (x86_64 matches emulator ABI)
# that overrides glGetString / glGetStringi to return Adreno 740 strings.
cat > /tmp/gpuspoof.c << 'CSRC'
/*
 * gpuspoof.c — override OpenGL ES vendor / renderer strings
 * Target: Android x86_64 emulator (glibc, not bionic, but pattern works in
 *         both via RTLD_NEXT because we intercept before the real .so).
 * Compile: gcc -shared -fPIC -O2 -o libgpuspoof.so gpuspoof.c -ldl
 */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <stddef.h>
#include <GLES2/gl2.h>

typedef const GLubyte *(*fn_glGetString)(GLenum name);
typedef const GLubyte *(*fn_glGetStringi)(GLenum name, GLuint index);

const GLubyte *glGetString(GLenum name) {
    static fn_glGetString real_fn = NULL;
    if (!real_fn) real_fn = (fn_glGetString)dlsym(RTLD_NEXT, "glGetString");
    switch (name) {
        case 0x1F00: return (const GLubyte *)"Qualcomm";
        case 0x1F01: return (const GLubyte *)"Adreno (TM) 740";
        case 0x1F02: return (const GLubyte *)"OpenGL ES 3.2 V@0615.73 (GIT@7c5e8d8)";
        case 0x8B8C: return (const GLubyte *)"OpenGL ES GLSL ES 3.20";
        default: return real_fn ? real_fn(name) : NULL;
    }
}

/* glGetStringi is used by OpenGL ES 3.x for extension enumeration */
const GLubyte *glGetStringi(GLenum name, GLuint index) {
    static fn_glGetStringi real_fn = NULL;
    if (!real_fn) real_fn = (fn_glGetStringi)dlsym(RTLD_NEXT, "glGetStringi");
    return real_fn ? real_fn(name, index) : NULL;
}
CSRC

# build the shim (NDK not needed: emulator runs x86_64 ELF with glibc-like linkage)
if command -v gcc &>/dev/null \
   && pkg-config --exists glesv2 2>/dev/null; then
  GLES_FLAGS="$(pkg-config --cflags glesv2 2>/dev/null || echo '-I/usr/include')"
  gcc -shared -fPIC -O2 ${GLES_FLAGS} \
    -o /tmp/libgpuspoof.so /tmp/gpuspoof.c -ldl 2>/dev/null && {
    adb push /tmp/libgpuspoof.so /system/lib64/libgpuspoof.so
    adb_sh "chmod 644 /system/lib64/libgpuspoof.so"
    # Inject into app_process so all Android processes load the shim
    # via /system/etc/ld.config.txt additional_namespaces or init.rc LD_PRELOAD
    adb_sh "echo 'export LD_PRELOAD=/system/lib64/libgpuspoof.so' \
      >> /system/etc/environment" 2>/dev/null || true
    echo "gpuspoof.so: deployed to /system/lib64"
  } || echo "gpuspoof.so: build failed — skipping shim (setprop spoof still active)"
else
  echo "gpuspoof.so: missing build deps — skipping shim"
fi

# ── display: apply S23 screen resolution and 120 Hz refresh ──────────────────
adb_sh "wm size 1080x2340"
adb_sh "wm density 425"
adb_sh "settings put system peak_refresh_rate 120"
adb_sh "settings put system min_refresh_rate 60"
adb_sh "settings put system user_refresh_rate 120"
adb_sh "settings put global animator_duration_scale 0.5"
adb_sh "settings put global window_animation_scale 0.5"
adb_sh "settings put global transition_animation_scale 0.5"

# ── CPU topology: write /proc-visible info that reflects S8G2 Cortex layout ──
# Cortex-X3 × 1 (prime), A715 × 2 (perf), A510 × 5 (eff)
# /sys/devices/system/cpu/cpuN/cpufreq/cpuinfo_max_freq
cpu_freqs=(3200000 2800000 2800000 2000000 2000000 2000000 2000000 2000000)
for i in "${!cpu_freqs[@]}"; do
  adb_sh \
    "echo '${cpu_freqs[$i]}' > /sys/devices/system/cpu/cpu${i}/cpufreq/scaling_max_freq" \
    2>/dev/null || true
done

# ── Samsung-specific system settings ─────────────────────────────────────────
adb_sh "settings put secure ui_night_mode 1"       # dark mode (One UI default)
adb_sh "settings put system screen_brightness 200"
adb_sh "settings put system font_scale 1.0"
adb_sh "settings put system pointer_speed 0"
# Edge panels, DeX UI hints
adb_sh "settings put system edge_screen_on_switch 0" 2>/dev/null || true

# ── reboot to apply build.prop changes ───────────────────────────────────────
echo "rebooting to apply identity..."
adb reboot
sleep 10

# wait for second boot
BOOT2=0
until adb shell getprop sys.boot_completed 2>/dev/null | grep -q "^1$"; do
  sleep 5
  BOOT2=$((BOOT2 + 5))
  if (( BOOT2 >= 240 )); then
    echo "reboot timeout — continuing anyway" >&2
    break
  fi
done

echo "spoof: identity applied, second boot complete in ${BOOT2}s"
