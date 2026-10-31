#!/bin/zsh
# Stop and remove the LaunchAgents. Config, cache and credentials are left in place.
set -u
for name in local.baidunetdisk.mount org.oplist.openlist; do
  launchctl bootout "gui/$(id -u)/$name" 2>/dev/null && echo "stopped $name"
  rm -f "$HOME/Library/LaunchAgents/$name.plist"
done
umount "$HOME/CloudDrives" 2>/dev/null || true
