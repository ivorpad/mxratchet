#!/bin/bash
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
PLIST_NAME="com.ivor.mxratchet"
DAEMON_DIR="/Library/LaunchDaemons"
LOG_DIR="$HOME/Library/Logs"

echo "=== mxratchet installer ==="
echo

# 1. Compile Swift binary
echo "Compiling mxratchet..."
swiftc -O -o "$DIR/mxratchet" "$DIR/mxratchet-hid.swift" \
    -framework IOKit -framework CoreFoundation 2>&1
echo "  Compiled: $DIR/mxratchet"
echo

# 2. Install binary
echo "Installing to /usr/local/bin/mxratchet (requires sudo)..."
sudo mkdir -p /usr/local/bin
sudo cp "$DIR/mxratchet" /usr/local/bin/mxratchet
sudo chmod 755 /usr/local/bin/mxratchet
echo

# 3. Quick test
echo "Testing device access..."
if sudo /usr/local/bin/mxratchet status 2>/dev/null; then
    echo
    echo "Device accessible!"
else
    echo
    echo "Warning: Could not access MX Master 3."
    echo "  The daemon will keep retrying after install."
    echo "  If the mouse is asleep, move it and try: sudo mxratchet status"
fi
echo

# 4. Install LaunchDaemon (runs as root)
echo "Installing LaunchDaemon (runs as root for BLE HID access)..."
mkdir -p "$LOG_DIR"

# Unload existing daemon
if sudo launchctl list "$PLIST_NAME" &>/dev/null; then
    echo "  Stopping existing daemon..."
    sudo launchctl bootout system/"$PLIST_NAME" 2>/dev/null || \
        sudo launchctl unload "$DAEMON_DIR/$PLIST_NAME.plist" 2>/dev/null || true
fi

# Generate plist from template, substituting log path for current user
LOG_PATH="$LOG_DIR/mxratchet.log"
sed "s|__LOG_PATH__|$LOG_PATH|g" "$DIR/$PLIST_NAME.plist" | sudo tee "$DAEMON_DIR/$PLIST_NAME.plist" > /dev/null
sudo chown root:wheel "$DAEMON_DIR/$PLIST_NAME.plist"
sudo chmod 644 "$DAEMON_DIR/$PLIST_NAME.plist"

echo "  Loading daemon..."
sudo launchctl bootstrap system "$DAEMON_DIR/$PLIST_NAME.plist" 2>/dev/null || \
    sudo launchctl load "$DAEMON_DIR/$PLIST_NAME.plist"

echo
echo "=== Done! ==="
echo
echo "  Status:    sudo mxratchet status"
echo "  Ratchet:   sudo mxratchet ratchet"
echo "  Free spin: sudo mxratchet freespin"
echo "  Logs:      tail -f ~/Library/Logs/mxratchet.log"
echo
echo "The daemon is running and will enforce ratchet mode every 30s."
echo "It persists across reboots."
echo
echo "To uninstall:"
echo "  sudo launchctl bootout system/$PLIST_NAME"
echo "  sudo rm /Library/LaunchDaemons/$PLIST_NAME.plist /usr/local/bin/mxratchet"
