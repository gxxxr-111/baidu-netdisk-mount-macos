#!/bin/zsh
# One-time OpenList setup: data dir, localhost-only binding, admin user, WebDAV write permission.
# Run while OpenList is NOT running. Safe to re-run (keeps the existing database).
set -eu

DATA="${OPENLIST_DATA:-$HOME/.config/openlist}"
PW_FILE="$DATA/admin-password.txt"
command -v openlist >/dev/null || { echo "Install first: brew install openlist"; exit 1; }
pgrep -f "openlist server" >/dev/null && { echo "Stop OpenList first."; exit 1; }
mkdir -p "$DATA"

if [[ ! -f "$DATA/data.db" ]]; then
  # OpenList 4.2.9 may skip creating the admin user on first start unless this env var is set.
  umask 077
  openssl rand -base64 24 | tr -d '/+=' > "$PW_FILE"
  echo "Initialising OpenList (about 10 s)..."
  (cd "$DATA" && OPENLIST_ADMIN_PASSWORD="$(cat "$PW_FILE")" \
     timeout 10 openlist server --data "$DATA" >/dev/null 2>&1) || true
  # The first-start log prints the initial password; scrub it.
  grep -rl "initial password" "$DATA/log" 2>/dev/null | while read -r f; do
    sed -i '' -E 's/(initial password is: ).*/\1<redacted>/' "$f"
  done
fi

# Listen on localhost only.
python3 - "$DATA/config.json" <<'EOF'
import json, sys
p = sys.argv[1]; c = json.load(open(p))
c["scheme"]["address"] = "127.0.0.1"
json.dump(c, open(p, "w"), indent=2)
EOF

# Admin can be created without the WebDAV-manage bits (9-11) -> 403 on MKCOL/PUT. Add them.
sqlite3 "$DATA/data.db" "update x_users set permission = permission | 3584 where username='admin';"
sqlite3 "$DATA/data.db" "select 'admin permission = ' || permission from x_users where username='admin';"
echo "Done. Admin password: $PW_FILE (copy with: pbcopy < $PW_FILE)"
