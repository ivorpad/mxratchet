#!/bin/bash
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
HELPER_PLIST="com.ivor.mxratchet-helper"
DAEMON_DIR="/Library/LaunchDaemons"
LOG_DIR="$HOME/Library/Logs"
LOG_PATH="$LOG_DIR/mxratchet-helper.log"

echo "=== MXRatchet App Installer ==="
echo

# 1. Build
echo "Building (release)..."
cd "$DIR"
swift build -c release
echo "  Built successfully"
echo

# 2. Bundle .app
echo "Bundling MXRatchet.app..."
mkdir -p .build/MXRatchet.app/Contents/MacOS
cp .build/release/MXRatchet .build/MXRatchet.app/Contents/MacOS/
cp Resources/Info.plist .build/MXRatchet.app/Contents/
echo "  Bundled: .build/MXRatchet.app"
echo

# 3. Install helper binary
echo "Installing mxratchet-helper (requires sudo)..."
sudo mkdir -p /usr/local/bin
sudo cp .build/release/MXRatchetHelper /usr/local/bin/mxratchet-helper
sudo chmod 755 /usr/local/bin/mxratchet-helper
echo "  Installed: /usr/local/bin/mxratchet-helper"
echo

# 4. Install helper LaunchDaemon
echo "Installing helper LaunchDaemon..."
mkdir -p "$LOG_DIR"

# Unload existing daemon
if sudo launchctl list "$HELPER_PLIST" &>/dev/null; then
    echo "  Stopping existing helper daemon..."
    sudo launchctl bootout system/"$HELPER_PLIST" 2>/dev/null || \
        sudo launchctl unload "$DAEMON_DIR/$HELPER_PLIST.plist" 2>/dev/null || true
fi

# Install plist with log path substituted
sed "s|__LOG_PATH__|$LOG_PATH|g" "$DIR/$HELPER_PLIST.plist" \
    | sudo tee "$DAEMON_DIR/$HELPER_PLIST.plist" > /dev/null
sudo chown root:wheel "$DAEMON_DIR/$HELPER_PLIST.plist"
sudo chmod 644 "$DAEMON_DIR/$HELPER_PLIST.plist"

echo "  Loading helper daemon..."
sudo launchctl bootstrap system "$DAEMON_DIR/$HELPER_PLIST.plist" 2>/dev/null || \
    sudo launchctl load "$DAEMON_DIR/$HELPER_PLIST.plist"
echo

# 5. Install app
echo "Installing MXRatchet.app..."
APP_DEST="$HOME/Applications"
mkdir -p "$APP_DEST"
rm -rf "$APP_DEST/MXRatchet.app"
cp -R .build/MXRatchet.app "$APP_DEST/"
echo "  Installed: $APP_DEST/MXRatchet.app"
echo

echo "=== Done! ==="
echo
echo "  Helper logs: tail -f $LOG_PATH"
echo "  Launch app:  open ~/Applications/MXRatchet.app"
echo
echo "The helper daemon is running and will auto-apply preferences on reconnect."
echo "The app will appear in the menu bar (no dock icon)."
echo
echo "To uninstall:"
echo "  sudo launchctl bootout system/$HELPER_PLIST"
echo "  sudo rm /Library/LaunchDaemons/$HELPER_PLIST.plist /usr/local/bin/mxratchet-helper"
echo "  rm -rf ~/Applications/MXRatchet.app"
echo "  sudo rm -f /etc/mxratchet.json /var/run/mxratchet.sock"
