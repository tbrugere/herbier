#!/usr/bin/env bash
# Write the local database's catalog (lib/postgrest/codegen/catalog.sql: one
# pretty-printed JSON object per table) to supabase/schema/catalog.json, the
# input of postgrest-codegen, which generates app/store/tables.ml from it
# (app/store/dune).
#
#   scripts/catalog-dump.sh            # rewrite supabase/schema/catalog.json
#   scripts/catalog-dump.sh --check    # fail, with a diff, if it is stale
#
# Needs the local Supabase database with this branch's migrations applied
# (`npx supabase db reset`); DB_URL overrides where it is.
set -euo pipefail
root="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
db_url="${DB_URL:-postgresql://postgres:postgres@127.0.0.1:54322/postgres}"
committed="$root/supabase/schema/catalog.json"

# -q: no CREATE FUNCTION tag in the output, only the rows.
dump() {
  psql "$db_url" -X -q -At -v ON_ERROR_STOP=1 \
    -f "$root/lib/postgrest/codegen/catalog.sql"
}

# Dumped first, so that a psql failure stops here with its own message.
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
case "${1:-}" in
  "")
    dump >"$tmp"
    cat "$tmp" >"$committed"
    ;;
  --check)
    dump >"$tmp"
    if ! diff -u "$committed" "$tmp"; then
      echo "supabase/schema/catalog.json is stale: run scripts/catalog-dump.sh" >&2
      exit 1
    fi
    ;;
  *)
    echo "usage: $0 [--check]" >&2
    exit 2
    ;;
esac
