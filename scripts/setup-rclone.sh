#!/bin/zsh
# Install the official rclone build (Homebrew's has no `mount` on macOS) and create
# the `openlist` WebDAV remote. Also copies the mount filter into ~/.config/rclone.
set -eu

BIN="$HOME/.local/bin"
REPO="${0:A:h:h}"
PW_FILE="${OPENLIST_PW_FILE:-$HOME/.config/openlist/admin-password.txt}"

if [[ ! -x "$BIN/rclone" ]]; then
  arch=$([[ "$(uname -m)" == arm64 ]] && echo arm64 || echo amd64)
  tmp=$(mktemp -d)
  curl -fsSL "https://downloads.rclone.org/rclone-current-osx-$arch.zip" -o "$tmp/r.zip"
  unzip -q "$tmp/r.zip" -d "$tmp"
  mkdir -p "$BIN" && cp "$tmp"/rclone-*/rclone "$BIN/"
  xattr -d com.apple.quarantine "$BIN/rclone" 2>/dev/null || true
  rm -rf "$tmp"
fi
"$BIN/rclone" version | head -1

mkdir -p "$HOME/.config/rclone"
"$BIN/rclone" config create openlist webdav \
  url=http://127.0.0.1:5244/dav vendor=other user=admin \
  pass="$("$BIN/rclone" obscure "$(cat "$PW_FILE")")" --non-interactive >/dev/null
chmod 600 "$HOME/.config/rclone/rclone.conf"
cp "$REPO/config/mount-filter.txt" "$HOME/.config/rclone/mount-filter.txt"
echo "rclone remote 'openlist' ready."
