#!/usr/bin/env bash
# PiTV Setup — One-shot install script for Raspberry Pi
# Run this once on a fresh Raspberry Pi OS Lite installation.
#
# Usage:
#   sudo ./setup.sh              # Standard install
#   sudo ./setup.sh --readonly   # Install + enable read-only filesystem

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
READONLY=false

# Parse args
for arg in "$@"; do
    case $arg in
        --readonly) READONLY=true ;;
        --help|-h)
            echo "Usage: sudo $0 [--readonly]"
            echo "  --readonly  Enable OverlayFS for SD card protection"
            exit 0
            ;;
    esac
done

# Must run as root
if [[ $EUID -ne 0 ]]; then
    echo "Error: This script must be run as root (sudo)." >&2
    exit 1
fi

# Detect Pi
if ! grep -q "Raspberry Pi\|BCM" /proc/cpuinfo 2>/dev/null; then
    echo "Warning: This doesn't appear to be a Raspberry Pi. Continuing anyway..." >&2
fi

# Detect boot config path (Bookworm vs Bullseye)
if [[ -d /boot/firmware ]]; then
    BOOT_CONFIG="/boot/firmware/config.txt"
else
    BOOT_CONFIG="/boot/config.txt"
fi

echo "=== PiTV Setup ==="
echo "Project dir:  $PROJECT_DIR"
echo "Boot config:  $BOOT_CONFIG"
echo ""

# Step 1: Install mplayer
echo "[1/6] Installing mplayer..."
apt-get update -qq
apt-get install -y -qq mplayer

# Step 2: Disable KMS driver (required for composite output)
echo "[2/6] Disabling KMS video driver for composite support..."
if grep -q "^dtoverlay=vc4-kms-v3d" "$BOOT_CONFIG" 2>/dev/null; then
    sed -i 's/^dtoverlay=vc4-kms-v3d/#dtoverlay=vc4-kms-v3d  # Disabled by PiTV (composite requires firmware driver)/' "$BOOT_CONFIG"
    echo "  Commented out dtoverlay=vc4-kms-v3d"
elif grep -q "^dtoverlay=vc4-fkms-v3d" "$BOOT_CONFIG" 2>/dev/null; then
    sed -i 's/^dtoverlay=vc4-fkms-v3d/#dtoverlay=vc4-fkms-v3d  # Disabled by PiTV (composite requires firmware driver)/' "$BOOT_CONFIG"
    echo "  Commented out dtoverlay=vc4-fkms-v3d"
else
    echo "  KMS overlay already disabled or not found."
fi

# Step 3: Append boot config
echo "[3/6] Configuring composite video output..."
MARKER="# --- PiTV Composite Output ---"
if grep -qF "$MARKER" "$BOOT_CONFIG" 2>/dev/null; then
    echo "  Boot config already applied, skipping."
else
    echo "" >> "$BOOT_CONFIG"
    cat "$PROJECT_DIR/config/config.txt" >> "$BOOT_CONFIG"
    echo "  Appended PiTV settings to $BOOT_CONFIG"
fi

# Step 4: Force audio to analog output
echo "[4/6] Configuring audio output..."
amixer cset numid=3 1 2>/dev/null || echo "  Warning: Could not set audio output (may need reboot)"

# Detect the real user (not root)
PI_USER=$(logname 2>/dev/null || echo "pi")
PI_HOME=$(eval echo "~$PI_USER")

# Step 5: Install and enable systemd service
echo "[5/6] Installing systemd service..."
sed -e "s|__USER__|$PI_USER|g" -e "s|__HOME__|$PI_HOME|g" \
    "$PROJECT_DIR/systemd/pitv.service" > /etc/systemd/system/pitv.service
systemctl daemon-reload
systemctl enable pitv.service
echo "  Service installed for user: $PI_USER"

# Update config with actual home path
sed -i "s|__HOME__|$PI_HOME|g" "$PROJECT_DIR/config/pitv.conf"

# Step 6: Create videos directory
echo "[6/6] Preparing videos directory..."
VIDEOS_DIR="$PROJECT_DIR/videos"
mkdir -p "$VIDEOS_DIR"
chown -R "$PI_USER:$PI_USER" "$VIDEOS_DIR"

# Optional: Enable read-only filesystem
if [[ "$READONLY" == "true" ]]; then
    echo ""
    echo "[Optional] Enabling read-only filesystem (OverlayFS)..."
    if command -v raspi-config &>/dev/null; then
        raspi-config nonint enable_overlayfs
        raspi-config nonint enable_bootro
        echo "  OverlayFS enabled. SD card is protected after next reboot."
        echo "  To add videos later, you must first disable it:"
        echo "    sudo raspi-config nonint disable_overlayfs"
        echo "    sudo raspi-config nonint disable_bootro"
        echo "    sudo reboot"
    else
        echo "  Warning: raspi-config not found, cannot enable OverlayFS." >&2
    fi
fi

echo ""
echo "=== Setup Complete ==="
echo ""
echo "Next steps:"
echo "  1. Transcode your videos on your desktop:"
echo "     ./scripts/transcode.sh ~/my_videos/ ./videos/"
echo ""
echo "  2. Copy the transcoded .mp4 files to: $VIDEOS_DIR"
echo ""
echo "  3. Reboot the Pi:"
echo "     sudo reboot"
echo ""
echo "Video will start playing automatically on the composite output."
