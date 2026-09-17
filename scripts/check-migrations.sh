#!/usr/bin/env bash
# Rebuilds every migration from an empty database, in a throwaway Postgres.
#
#   npm run check:migrations            # apply, report, tear down
#   KEEP=1 npm run check:migrations     # leave it running and print how to connect
#
# `supabase db push` only ever applies the newest migration to a database that
# already has the rest, so it cannot tell you whether the set still builds from
# nothing — and three separate bugs in this project were only visible that way.
set -euo pipefail

for dir in /opt/homebrew/opt/postgresql@16/bin /opt/homebrew/opt/postgresql@17/bin /usr/local/opt/postgresql@16/bin; do
  [ -x "$dir/initdb" ] && PATH="$dir:$PATH"
done
command -v initdb >/dev/null || { echo "Postgres not found. brew install postgresql@16"; exit 2; }

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d /tmp/blurt-pg.XXXXXX)"   # short path: unix sockets cap at ~100 bytes
PORT="${PORT:-55499}"
export PGHOST=127.0.0.1 PGPORT="$PORT" PGUSER=blurt PGDATABASE=blurt_check

cleanup() { pg_ctl -D "$WORK/data" stop -m immediate >/dev/null 2>&1 || true; rm -rf "$WORK"; }
[ "${KEEP:-}" = "1" ] || trap cleanup EXIT

initdb -D "$WORK/data" -U blurt --auth=trust >/dev/null
pg_ctl -D "$WORK/data" -o "-p $PORT -c listen_addresses=127.0.0.1 -c unix_socket_directories=''" -l "$WORK/log" -w start >/dev/null
createdb -U blurt blurt_check
psql -q -v ON_ERROR_STOP=1 -f "$ROOT/scripts/supabase-stubs.sql" 2>&1 | grep -v "wal_level\|HINT" || true

count=0
for f in "$ROOT"/supabase/migrations/*.sql; do
  if ! out=$(psql -q -v ON_ERROR_STOP=1 -f "$f" 2>&1); then
    echo "FAILED  $(basename "$f")"; echo "$out" | grep -iA3 "error" | head -10; exit 1
  fi
  count=$((count + 1))
done
echo "ok  $count migrations build from an empty database"

if [ -n "${1:-}" ]; then psql -X -q -f "$1"; fi
if [ "${KEEP:-}" = "1" ]; then
  echo "left running:  psql -h 127.0.0.1 -p $PORT -U blurt blurt_check"
  echo "stop with:     pg_ctl -D $WORK/data stop"
fi
