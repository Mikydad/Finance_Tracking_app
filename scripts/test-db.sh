#!/usr/bin/env bash
# Runs the migrations and database tests on a throwaway PostgreSQL.
#
#   scripts/test-db.sh                 # starts a temp cluster (needs initdb/pg_ctl)
#   DATABASE_URL=postgres://... scripts/test-db.sh   # uses an empty database you provide
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cleanup() { :; }
trap 'cleanup' EXIT

if [[ -z "${DATABASE_URL:-}" ]]; then
  pgbin="${PG_BIN:-$(ls -d /usr/lib/postgresql/*/bin 2>/dev/null | sort -V | tail -1)}"
  tmp="$(mktemp -d)"
  "$pgbin/initdb" -D "$tmp/data" -U postgres -A trust >/dev/null
  "$pgbin/pg_ctl" -D "$tmp/data" -o "-k $tmp -p 54329 -c listen_addresses=''" -l "$tmp/log" start >/dev/null
  cleanup() { "$pgbin/pg_ctl" -D "$tmp/data" stop -m immediate >/dev/null 2>&1 || true; rm -rf "$tmp"; }
  DATABASE_URL="postgresql://postgres@/postgres?host=$tmp&port=54329"
fi

run() { psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -q -X -o /dev/null -f "$1"; }

run "$root/supabase/tests/db/00_supabase_stub.sql"
for f in "$root"/supabase/migrations/*.sql; do
  echo "migrate: $(basename "$f")"
  run "$f"
done
for f in "$root"/supabase/tests/db/[1-9]*_test.sql; do
  echo "test: $(basename "$f")"
  run "$f"
done
