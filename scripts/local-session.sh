#!/usr/bin/env bash
# Print a Supabase session (the JSON of /auth/v1/verify: access_token,
# refresh_token, expires_at, user) for a user of the local stack
# (`npx supabase start`), creating the user, confirmed, through the admin API
# when it does not exist. For device checks that need a token without a
# Google account on the emulator (#dev/rest: paste the access token).
#
#   scripts/local-session.sh <email>
#   TOKEN=$(scripts/local-session.sh dev@herbier.local | jq -r .access_token)
#
# Local stack only: the keys come from `npx supabase status`.
set -euo pipefail
case "$#" in
  1) email="$1" ;;
  *) echo "usage: $0 <email>" >&2; exit 2 ;;
esac
root="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
# shellcheck source=lib/local-stack.sh
. "$root/scripts/lib/local-stack.sh"
require_tools curl jq

local_stack_keys "$root"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# call <expected status> <method> <url> <key> [body]: the answer on stdout;
# another status is fatal. The service role key is also the bearer.
call() {
  local expected="$1" method="$2" url="$3" key="$4" body="${5:-}"
  local args=(-sS -o "$tmp/answer" -w '%{http_code}' -X "$method" "$url"
    -H "apikey: $key" -H 'Content-Type: application/json')
  [ "$key" = "$service" ] && args+=(-H "Authorization: Bearer $service")
  [ -n "$body" ] && args+=(-d "$body")
  local status
  status="$(curl "${args[@]}")"
  [ "$status" = "$expected" ] || {
    echo "$method $url: HTTP $status, expected $expected" >&2
    cat "$tmp/answer" >&2
    exit 1
  }
  cat "$tmp/answer"
}

# The user: reused when an account with that address exists.
existing="$(call 200 GET "$api/auth/v1/admin/users?per_page=1000" "$service" \
  | jq -r --arg email "$email" \
      '[.users[] | select(.email == $email)][0].id // empty')"
if [ -z "$existing" ]; then
  call 200 POST "$api/auth/v1/admin/users" "$service" \
    "$(jq -nc --arg email "$email" '{email: $email, email_confirm: true}')" \
    >/dev/null
fi

# A session through a magic link verified directly.
link="$(call 200 POST "$api/auth/v1/admin/generate_link" "$service" \
  "$(jq -nc --arg email "$email" '{type: "magiclink", email: $email}')")"
call 200 POST "$api/auth/v1/verify" "$anon" \
  "$(jq -c '{type: "magiclink", token_hash: .hashed_token}' <<<"$link")"
