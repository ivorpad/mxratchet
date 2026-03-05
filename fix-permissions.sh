#!/bin/bash
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR"

HELPER_PLIST="com.ivor.mxratchet-helper"
DAEMON_DIR="/Library/LaunchDaemons"
LOG_DIR="$HOME/Library/Logs"
LOG_PATH="$LOG_DIR/mxratchet-helper.log"
SIGN_HASH="A0FD22414F94EA6BFC4F1EF1F5BFC369633D6710"
SIGN_ID="com.ivor.mxratchet-helper"

echo "=== MXRatchet Helper Permission Fix ==="
echo

# 1. Stop existing daemon
echo "[1/7] Stopping existing daemon..."
sudo launchctl bootout system/"$HELPER_PLIST" 2>/dev/null || true
sleep 1
# Kill any stragglers
sudo pkill -f mxratchet-helper 2>/dev/null || true
sleep 1

# 2. Clean up stale socket
echo "[2/7] Cleaning up..."
sudo rm -f /var/run/mxratchet.sock

# 3. Try to clear stale TCC entry
echo "[3/7] Clearing stale TCC entries..."
# Try resetting just our identifier (may or may not work)
tccutil reset ListenEvent "$SIGN_ID" 2>/dev/null || true
tccutil reset ListenEvent MXRatchetHelper 2>/dev/null || true
# Try the user-level TCC database
USER_TCC="$HOME/Library/Application Support/com.apple.TCC/TCC.db"
if [ -w "$USER_TCC" ] 2>/dev/null; then
    sqlite3 "$USER_TCC" "DELETE FROM access WHERE service='kTCCServiceListenEvent' AND client LIKE '%mxratchet%'" 2>/dev/null || true
    echo "  Cleared user TCC entries"
fi
# Try the system TCC database
sudo sqlite3 "/Library/Application Support/com.apple.TCC/TCC.db" \
    "DELETE FROM access WHERE service='kTCCServiceListenEvent' AND client LIKE '%mxratchet%'" 2>/dev/null || true

# 4. Rebuild
echo "[4/7] Building..."
swift build -c release 2>&1 | tail -1

# 5. Sign with stable identity
echo "[5/7] Signing with developer certificate..."
codesign --force --sign "$SIGN_HASH" --identifier "$SIGN_ID" .build/release/MXRatchetHelper
codesign -dvv .build/release/MXRatchetHelper 2>&1 | grep -E "Identifier|Authority|TeamIdentifier"

# 6. Install
echo "[6/7] Installing..."
sudo mkdir -p /usr/local/bin
sudo cp .build/release/MXRatchetHelper /usr/local/bin/mxratchet-helper
sudo chmod 755 /usr/local/bin/mxratchet-helper
mkdir -p "$LOG_DIR"

# Install plist
sed "s|__LOG_PATH__|$LOG_PATH|g" "$DIR/$HELPER_PLIST.plist" \
    | sudo tee "$DAEMON_DIR/$HELPER_PLIST.plist" > /dev/null
sudo chown root:wheel "$DAEMON_DIR/$HELPER_PLIST.plist"
sudo chmod 644 "$DAEMON_DIR/$HELPER_PLIST.plist"

# 7. Open Input Monitoring settings
echo "[7/7] Opening Input Monitoring settings..."
echo
echo "  ┌─────────────────────────────────────────────────────┐"
echo "  │  ADD THIS TO INPUT MONITORING:                      │"
echo "  │                                                     │"
echo "  │  /usr/local/bin/mxratchet-helper                    │"
echo "  │                                                     │"
echo "  │  Click +, then Cmd+Shift+G, paste the path above.  │"
echo "  └─────────────────────────────────────────────────────┘"
echo
open "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"

echo "Press ENTER after you've added mxratchet-helper to Input Monitoring..."
read -r

# Start daemon
echo "Starting daemon..."
sudo launchctl bootstrap system "$DAEMON_DIR/$HELPER_PLIST.plist" 2>/dev/null || \
    sudo launchctl load "$DAEMON_DIR/$HELPER_PLIST.plist" 2>/dev/null || \
    sudo launchctl kickstart system/"$HELPER_PLIST"

sleep 3

# Verify
echo
echo "=== Checking result ==="
tail -5 "$LOG_PATH"

if grep -q "Connected to MX Master 3" <(tail -5 "$LOG_PATH"); then
    echo
    echo "SUCCESS — helper connected to MX Master 3"
else
    echo
    echo "Still failing. If Input Monitoring didn't stick, try:"
    echo "  1. Run:  tccutil reset ListenEvent"
    echo "     (This resets ALL Input Monitoring — you'll re-grant Terminal etc.)"
    echo "  2. Re-add /usr/local/bin/mxratchet-helper to Input Monitoring"
    echo "  3. Run:  sudo launchctl kickstart -k system/$HELPER_PLIST"
fi
