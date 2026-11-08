#!/usr/bin/env bash
# phase 1 — install system dependencies and Android SDK
set -euo pipefail

ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT:-/opt/android-sdk}"
CMDTOOLS_URL="https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip"

# ── system packages ──────────────────────────────────────────────────────────
sudo apt-get update -qq 2>/dev/null
sudo apt-get install -y --no-install-recommends \
  xvfb \
  x11vnc \
  x11-utils \
  xdotool \
  libgl1-mesa-dev \
  libgles2-mesa-dev \
  libgles2-mesa \
  mesa-utils \
  mesa-vulkan-drivers \
  libegl1-mesa \
  libgbm1 \
  unzip \
  curl \
  wget \
  git \
  python3 \
  python3-pip \
  python3-venv \
  openjdk-17-jdk \
  libc6-i386 \
  libncurses5 \
  libstdc++6 \
  zlib1g \
  qemu-kvm \
  libvirt-daemon-system \
  libvirt-clients \
  bridge-utils \
  cpu-checker \
  kmod \
  socat \
  2>/dev/null

# ── KVM acceleration ─────────────────────────────────────────────────────────
sudo modprobe kvm_intel 2>/dev/null || sudo modprobe kvm_amd 2>/dev/null || true
if [[ -e /dev/kvm ]]; then
  sudo chmod 777 /dev/kvm
  sudo adduser "$(id -un)" kvm 2>/dev/null || true
  echo "kvm: enabled"
else
  echo "kvm: not available, using software rendering"
fi

# ── Python dependencies ───────────────────────────────────────────────────────
pip3 install --quiet --break-system-packages \
  websockets \
  aiohttp \
  2>/dev/null || \
pip3 install --quiet \
  websockets \
  aiohttp \
  2>/dev/null || true

# ── noVNC ────────────────────────────────────────────────────────────────────
if [[ ! -d /opt/novnc ]]; then
  sudo git clone --depth 1 https://github.com/novnc/noVNC.git /opt/novnc 2>/dev/null
  sudo git clone --depth 1 https://github.com/novnc/websockify.git \
    /opt/novnc/utils/websockify 2>/dev/null
fi
sudo chmod +x /opt/novnc/utils/launch.sh 2>/dev/null || true

# ── cloudflared ───────────────────────────────────────────────────────────────
if ! command -v cloudflared &>/dev/null; then
  curl -fsSL \
    "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64" \
    -o /usr/local/bin/cloudflared
  sudo chmod +x /usr/local/bin/cloudflared
fi

# ── Android SDK cmdline-tools ─────────────────────────────────────────────────
sudo mkdir -p "${ANDROID_SDK_ROOT}/cmdline-tools"
curl -fsSL "${CMDTOOLS_URL}" -o /tmp/ct.zip
sudo unzip -q /tmp/ct.zip -d "${ANDROID_SDK_ROOT}/cmdline-tools"
# sdkmanager expects the folder named "latest"
if [[ -d "${ANDROID_SDK_ROOT}/cmdline-tools/cmdline-tools" ]]; then
  sudo mv "${ANDROID_SDK_ROOT}/cmdline-tools/cmdline-tools" \
          "${ANDROID_SDK_ROOT}/cmdline-tools/latest"
fi
rm -f /tmp/ct.zip

export PATH="${ANDROID_SDK_ROOT}/cmdline-tools/latest/bin:\
${ANDROID_SDK_ROOT}/emulator:\
${ANDROID_SDK_ROOT}/platform-tools:\
${PATH}"

# ── accept licences and install SDK components ────────────────────────────────
yes | sdkmanager --licenses >/dev/null 2>&1 || true

sdkmanager --install \
  "emulator" \
  "platform-tools" \
  "platforms;android-33" \
  "system-images;android-33;google_apis;x86_64" \
  2>&1 | grep -v "^Warning" || true

# persist PATH for later steps
echo "ANDROID_SDK_ROOT=${ANDROID_SDK_ROOT}" >> "${GITHUB_ENV:-/dev/null}" 2>/dev/null || true
echo "${ANDROID_SDK_ROOT}/cmdline-tools/latest/bin" \
  >> "${GITHUB_PATH:-/dev/null}" 2>/dev/null || true
echo "${ANDROID_SDK_ROOT}/emulator" \
  >> "${GITHUB_PATH:-/dev/null}" 2>/dev/null || true
echo "${ANDROID_SDK_ROOT}/platform-tools" \
  >> "${GITHUB_PATH:-/dev/null}" 2>/dev/null || true

echo "setup: complete"
