#!/bin/bash
# Installs NightLock for the current user:
#   ~/.local/bin/nightlock                          the CLI
#   ~/Library/LaunchAgents/com.nightlock.agent.plist runs `nightlock check` every 20 s
#   ~/.config/nightlock/config                      your settings (created on first run)
set -eu
cd "$(dirname "$0")"

[ "$(uname -s)" = "Darwin" ] || { echo "NightLock is for macOS."; exit 1; }

BIN_DIR="$HOME/.local/bin"
AGENTS="$HOME/Library/LaunchAgents"
LABEL="com.nightlock.agent"
PLIST="$AGENTS/$LABEL.plist"

mkdir -p "$BIN_DIR" "$AGENTS" "$HOME/Library/Logs"
install -m 755 nightlock "$BIN_DIR/nightlock"
sed "s|__HOME__|$HOME|g" com.nightlock.agent.plist > "$PLIST"

# Create the config now so the user can edit it before the first lock.
"$BIN_DIR/nightlock" status >/dev/null 2>&1 || true

launchctl bootout "gui/$(id -u)/$LABEL" >/dev/null 2>&1 || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"
launchctl kickstart "gui/$(id -u)/$LABEL" >/dev/null 2>&1 || true

echo "NightLock installed."
echo
"$BIN_DIR/nightlock" status
echo
echo "Edit your window and app list:   nightlock edit"
echo "(add ~/.local/bin to your PATH if 'nightlock' is not found:"
echo "   echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> ~/.zshrc )"
echo
echo "On first use macOS may ask to allow 'bash' or 'osascript' to control apps or"
echo "send notifications. Click Allow, or the lock cannot quit apps."
