#!/usr/bin/env bash
# phase 2 — create Android Virtual Device with Samsung Galaxy S23 hardware profile
set -euo pipefail

ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT:-/opt/android-sdk}"
AVD_NAME="${AVD_NAME:-S23_Unit}"
export PATH="${ANDROID_SDK_ROOT}/cmdline-tools/latest/bin:\
${ANDROID_SDK_ROOT}/emulator:\
${ANDROID_SDK_ROOT}/platform-tools:\
${PATH}"
export ANDROID_AVD_HOME="${HOME}/.android/avd"
mkdir -p "${ANDROID_AVD_HOME}"
mkdir -p "${HOME}/.android"

# touch repositories.cfg to suppress sdkmanager warning
touch "${HOME}/.android/repositories.cfg"

# ── create AVD ────────────────────────────────────────────────────────────────
echo "no" | avdmanager create avd \
  --name "${AVD_NAME}" \
  --package "system-images;android-33;google_apis;x86_64" \
  --device "pixel_6" \
  --force \
  2>&1 | grep -v "^Warning" || true

CONFIG="${ANDROID_AVD_HOME}/${AVD_NAME}.avd/config.ini"
[[ -f "${CONFIG}" ]] || { echo "avd config not found at ${CONFIG}" >&2; exit 1; }

# ── patch hardware config to match Samsung Galaxy S23 (SM-S911B) ──────────────
# Screen: 6.1-inch FHD+ 1080×2340, 425ppi, 120Hz AMOLED
# SoC: Snapdragon 8 Gen 2 (SM8550), Cortex-X3 primary
# RAM: 8 GB  |  Storage: 128 GB base
python3 - "${CONFIG}" << 'PYEOF'
import sys, re

path = sys.argv[1]
with open(path, 'r') as f:
    text = f.read()

overrides = {
    'hw.cpu.ncore':              '8',
    'hw.ramSize':                '8192',
    'hw.lcd.width':              '1080',
    'hw.lcd.height':             '2340',
    'hw.lcd.density':            '425',
    'hw.lcd.circular':           'no',
    'hw.keyboard':               'yes',
    'hw.mainKeys':               'no',
    'hw.gpu.enabled':            'yes',
    'hw.gpu.mode':               'swiftshader_indirect',
    'hw.audioInput':             'yes',
    'hw.audioOutput':            'yes',
    'hw.camera.back':            'virtualscene',
    'hw.camera.front':           'emulated',
    'hw.gps':                    'yes',
    'hw.sensors.proximity':      'yes',
    'hw.sensors.light':          'yes',
    'hw.sensors.gyroscope':      'yes',
    'hw.sensors.acceleration':   'yes',
    'hw.sensors.magnetic_field': 'yes',
    'hw.sensors.barometer':      'yes',
    'hw.biometrics.fingerprint': 'yes',
    'hw.fingerprint':            'yes',
    'disk.dataPartition.size':   '16G',
    'fastboot.forceColdBoot':    'no',
    'tag.display':               'Google APIs',
    'tag.id':                    'google_apis',
    'avd.ini.encoding':          'UTF-8',
    'PlayStore.enabled':         'true',
}

for key, val in overrides.items():
    pattern = rf'^{re.escape(key)}=.*$'
    replacement = f'{key}={val}'
    if re.search(pattern, text, re.MULTILINE):
        text = re.sub(pattern, replacement, text, flags=re.MULTILINE)
    else:
        text += f'\n{key}={val}'

with open(path, 'w') as f:
    f.write(text)

print(f"config patched: {path}")
PYEOF

echo "avd: ${AVD_NAME} created"
