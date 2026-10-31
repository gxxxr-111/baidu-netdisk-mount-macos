#!/bin/zsh
# Mount Baidu Netdisk (through the local OpenList WebDAV) in Finder via rclone + fuse-t.
# Runs in the foreground so launchd can manage it. Override any setting with env vars.
set -u

RCLONE="${RCLONE:-$HOME/.local/bin/rclone}"          # official build; Homebrew's lacks `mount`
REMOTE="${REMOTE:-openlist:BaiduNetdisk}"             # rclone remote + OpenList mount path
MOUNT_POINT="${MOUNT_POINT:-$HOME/BaiduNetdisk}"
FUSE_BACKEND="${FUSE_BACKEND:-fskit}"                 # fskit (macOS 26+) or nfs
FILTER_FILE="${FILTER_FILE:-$HOME/.config/rclone/mount-filter.txt}"
LOG_FILE="${LOG_FILE:-$HOME/.config/rclone/mount.log}"
OPENLIST_URL="${OPENLIST_URL:-http://127.0.0.1:5244}"

# Wait up to 2 minutes for OpenList (matters at login, when both start together).
for _ in {1..120}; do
  curl -fs -o /dev/null "$OPENLIST_URL/ping" && break
  sleep 1
done

mkdir -p "$MOUNT_POINT"
backend_opt=()
[[ "$FUSE_BACKEND" == fskit ]] && backend_opt=(-o backend=fskit)

exec "$RCLONE" mount "$REMOTE" "$MOUNT_POINT" \
  "${backend_opt[@]}" --volname BaiduNetdisk \
  --user-agent pan.baidu.com \
  --filter-from "$FILTER_FILE" \
  --vfs-cache-mode full --vfs-cache-max-size 30G --vfs-cache-max-age 168h \
  --vfs-read-chunk-size 8M --vfs-read-chunk-streams 16 \
  --vfs-write-back 10s --dir-cache-time 5m --transfers 4 --timeout 30m \
  --noappledouble --noapplexattr \
  --log-file "$LOG_FILE" --log-level INFO
