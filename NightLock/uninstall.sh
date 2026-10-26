#!/bin/bash
# Removes the LaunchAgent and CLI. Keeps ~/.config/nightlock unless --purge is given.
set -u
LABEL="com.nightlock.agent"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

launchctl bootout "gui/$(id -u)/$LABEL" >/dev/null 2>&1 || true
rm -f "$PLIST" "$HOME/.local/bin/nightlock"
if [ "${1:-}" = "--purge" ]; then
  rm -rf "$HOME/.config/nightlock" "$HOME/Library/Logs/nightlock.log" "$HOME/Library/Logs/nightlock.agent.log"
  echo "NightLock removed, including config and logs."
else
  echo "NightLock removed. Config kept at ~/.config/nightlock (use --purge to delete it)."
fi
