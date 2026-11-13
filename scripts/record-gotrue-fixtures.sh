#!/usr/bin/env bash
# Record the Supabase Auth (GoTrue) answers of test/fixtures/gotrue_*.json
# from the local stack (`npx supabase start`): the bodies app/sync/gotrue.ml
# decodes. The file name ends with the HTTP status the request must answer;
# another status fails the script. A throwaway user, fixtures@herbier.local,
# is created through the admin API for the refresh chain and deleted at the
# end, also on failure.
#
#   scripts/record-gotrue-fixtures.sh [--force]
#
# An existing file is kept unless --force (every request still runs: the
# chain needs their answers): fixtures are recorded once, never edited. The
# 200 file holds a local-stack JWT and the throwaway address, nothing real.
set -euo pipefail
# One check per tool: `command -v jq curl` succeeds when either exists.
for tool in curl jq; do
  command -v "$tool" >/dev/null || { echo "needs $tool" >&2; exit 1; }
done
root="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
out="$root/test/fixtures"
force=0
case "$#:${1:-}" in
  0:) ;;
  1:--force) force=1 ;;
  *) echo "usage: $0 [--force]" >&2; exit 2 ;;
esac

env_out="$(cd "$root" && env -u NODE_OPTIONS npx supabase status -o env)"
value() { sed -n "s/^$1=\"\(.*\)\"$/\1/p" <<<"$env_out"; }
api="$(value API_URL)"
anon="$(value PUBLISHABLE_KEY)"
service="$(value SERVICE_ROLE_KEY)"
[ -n "$api" ] && [ -n "$anon" ] && [ -n "$service" ] \
  || { echo "local stack not running (npx supabase start)" >&2; exit 1; }

tmp="$(mktemp -d)"
user_id=""
cleanup() {
  if [ -n "$user_id" ]; then
    curl -sS -o /dev/null -X DELETE "$api/auth/v1/admin/users/$user_id" \
      -H "apikey: $service" -H "Authorization: Bearer $service" || true
  fi
  rm -rf "$tmp"
}
trap cleanup EXIT

# post <name> <expected status> <key> <url> <json body or ""> [curl args…]:
# the answer lands in $tmp/<name>; another status is fatal. <key> is the
# apikey header (and the bearer when it is the service role).
post() {
  local name="$1" expected="$2" key="$3" url="$4" body="$5"
  shift 5
  local args=(-sS -o "$tmp/$name" -w '%{http_code}' -X POST "$url"
    -H "apikey: $key" -H 'Content-Type: application/json')
  [ "$key" = "$service" ] && args+=(-H "Authorization: Bearer $service")
  [ -n "$body" ] && args+=(-d "$body")
  local status
  status="$(curl "${args[@]}" "$@")"
  [ "$status" = "$expected" ] || {
    echo "$name: HTTP $status, expected $expected" >&2
    cat "$tmp/$name" >&2
    exit 1
  }
}

# keep <name> <file>: the answer becomes the fixture unless it exists.
keep() {
  local name="$1" file="$2"
  if [ -e "$out/$file" ] && [ "$force" = 0 ]; then
    echo "skip $file"
  else
    cp "$tmp/$name" "$out/$file"
    echo "recorded $file"
  fi
}

# 1. The throwaway user, confirmed so that a magic link signs it in.
post user 200 "$service" "$api/auth/v1/admin/users" \
  '{"email":"fixtures@herbier.local","email_confirm":true}'
user_id="$(jq -r .id "$tmp/user")"

# 2. A first session, through a magic link verified directly (not recorded:
#    a /verify answer, used only for its refresh token).
post link 200 "$service" "$api/auth/v1/admin/generate_link" \
  '{"type":"magiclink","email":"fixtures@herbier.local"}'
post verify 200 "$anon" "$api/auth/v1/verify" \
  "$(jq -c '{type:"magiclink", token_hash:.hashed_token}' "$tmp/link")"

# 3. A refresh: the session app/sync/gotrue.ml decodes.
post refresh 200 "$anon" "$api/auth/v1/token?grant_type=refresh_token" \
  "$(jq -c '{refresh_token}' "$tmp/verify")"
keep refresh gotrue_token_refresh_200.json

# 4. Logout of that session: its refresh tokens are revoked.
post logout 204 "$anon" "$api/auth/v1/logout?scope=local" "" \
  -H "Authorization: Bearer $(jq -r .access_token "$tmp/refresh")"

# 5. A refresh with a revoked token.
post revoked 400 "$anon" "$api/auth/v1/token?grant_type=refresh_token" \
  "$(jq -c '{refresh_token}' "$tmp/refresh")"
keep revoked gotrue_token_refresh_not_found_400.json

# 6. A refresh with a token that is not one.
post invalid 400 "$anon" "$api/auth/v1/token?grant_type=refresh_token" \
  '{"refresh_token":"bogus"}'
keep invalid gotrue_token_refresh_invalid_400.json

# 7. A sign-up while sign-ups are off: the code the id-token grant answers
#    for a Google account without a user.
post signup 422 "$anon" "$api/auth/v1/signup" \
  '{"email":"nobody@herbier.local","password":"not-a-real-password-1"}'
keep signup gotrue_signup_disabled_422.json

# 8. An id-token grant with a token that is not a Google one: with the
#    provider on (supabase/config.toml), GoTrue answers in its OAuth-style
#    envelope ({"error":…,"error_description":…}), not its own.
post id_token 400 "$anon" "$api/auth/v1/token?grant_type=id_token" \
  '{"provider":"google","id_token":"x.y.z","nonce":"n"}'
keep id_token gotrue_token_id_token_invalid_request_400.json
