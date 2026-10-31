#!/bin/zsh
# Start OpenList and the Finder mount at login (user LaunchAgents, no admin rights).
# Undo with: scripts/uninstall-launchd.sh
set -eu

REPO="${0:A:h:h}"
AGENTS="$HOME/Library/LaunchAgents"
OPENLIST_BIN="$(command -v openlist)"
mkdir -p "$AGENTS" "$HOME/.config/openlist/log" "$HOME/.config/rclone"

cp "$REPO/scripts/mount-baidu.sh" "$HOME/.config/rclone/mount-baidu.sh"
chmod +x "$HOME/.config/rclone/mount-baidu.sh"

for name in org.oplist.openlist local.baidunetdisk.mount; do
  sed -e "s|__HOME__|$HOME|g" -e "s|__OPENLIST_BIN__|$OPENLIST_BIN|g" \
    "$REPO/launchd/$name.plist.template" > "$AGENTS/$name.plist"
  launchctl bootout "gui/$(id -u)/$name" 2>/dev/null || true
  # bootout returns before the old job is gone; bootstrapping too early fails with error 5.
  for _ in {1..20}; do
    launchctl print "gui/$(id -u)/$name" >/dev/null 2>&1 || break
    sleep 0.5
  done
  launchctl bootstrap "gui/$(id -u)" "$AGENTS/$name.plist"
  echo "loaded $name"
done
