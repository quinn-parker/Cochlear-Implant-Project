#!/bin/bash
# =============================================================================
# Cochlear Implant Project - Full Setup Script
# Installs all dependencies for: Flutter App, nRF Firmware, Python Tools
# =============================================================================

set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "============================================="
echo "  Cochlear Implant Project - Setup"
echo "============================================="

# --------------------------------------------------
# 1. System packages (Ubuntu/Debian)
# --------------------------------------------------
echo ""
echo "[1/5] Installing system dependencies..."
sudo apt-get update
sudo apt-get install -y \
    git \
    cmake \
    ninja-build \
    python3 \
    python3-pip \
    python3-venv \
    clang \
    pkg-config \
    libgtk-3-dev \
    liblzma-dev \
    libstdc++-12-dev \
    libserialport-dev \
    curl \
    unzip \
    wget

# --------------------------------------------------
# 2. Flutter SDK
# --------------------------------------------------
echo ""
echo "[2/5] Setting up Flutter..."
if command -v flutter &> /dev/null; then
    echo "Flutter already installed: $(flutter --version | head -1)"
else
    echo "Installing Flutter via snap..."
    sudo snap install flutter --classic
fi

flutter doctor --android-licenses 2>/dev/null || true
flutter config --no-analytics

# --------------------------------------------------
# 3. Flutter app dependencies
# --------------------------------------------------
echo ""
echo "[3/5] Installing Flutter app dependencies..."
cd "$SCRIPT_DIR/app"
flutter pub get
cd "$SCRIPT_DIR"

# --------------------------------------------------
# 4. Python tools dependencies
# --------------------------------------------------
echo ""
echo "[4/5] Installing Python tool dependencies..."

# Firmware serial tool
pip3 install --user -r firmware/tools/requirements.txt

# Audio testing tool
pip3 install --user -r tools/audio_testing/requirements.txt

# --------------------------------------------------
# 5. nRF Connect SDK (Zephyr)
# --------------------------------------------------
echo ""
echo "[5/5] Checking nRF Connect SDK..."
if command -v west &> /dev/null; then
    echo "West (Zephyr build tool) already installed."
    echo "To build firmware:"
    echo "  cd firmware"
    echo "  west build -b nrf54l15dk/nrf54l15/cpuapp"
    echo "  west flash"
else
    echo ""
    echo "=== nRF Connect SDK NOT FOUND ==="
    echo "Install it manually:"
    echo "  1. pip3 install west"
    echo "  2. mkdir -p ~/ncs && cd ~/ncs"
    echo "  3. west init -m https://github.com/nrfconnect/sdk-nrf --mr v2.5.0"
    echo "  4. west update"
    echo "  5. pip3 install -r zephyr/scripts/requirements.txt"
    echo "  6. pip3 install -r nrf/scripts/requirements.txt"
    echo ""
    echo "Or install nRF Connect for Desktop:"
    echo "  https://www.nordicsemi.com/Products/Development-tools/nRF-Connect-for-Desktop"
fi

echo ""
echo "============================================="
echo "  Setup complete!"
echo "============================================="
echo ""
echo "To run the Flutter GUI:"
echo "  cd app && flutter run -d linux"
echo ""
echo "To build firmware:"
echo "  cd firmware && west build -b nrf54l15dk/nrf54l15/cpuapp"
echo ""
echo "To test serial comms:"
echo "  python3 firmware/tools/hearing_aid_serial.py --port /dev/ttyACM0 --test"
echo ""
