# Sourced by the scripts that talk to the local Supabase stack
# (`npx supabase start`): local-session.sh, record-gotrue-fixtures.sh,
# record-sync-fixtures.sh. Defines functions only.

# require_tools <tool>…: exit 1 unless each is on PATH (one check per tool:
# `command -v jq curl` succeeds when either exists).
require_tools() {
  local tool
  for tool in "$@"; do
    command -v "$tool" >/dev/null || { echo "needs $tool" >&2; exit 1; }
  done
}

# local_stack_keys <repo root>: sets api, anon and service (API_URL,
# PUBLISHABLE_KEY, SERVICE_ROLE_KEY of `npx supabase status -o env`); exit 1
# when the stack is not running.
local_stack_keys() {
  local env_out
  env_out="$(cd "$1" && env -u NODE_OPTIONS npx supabase status -o env)"
  api="$(sed -n 's/^API_URL="\(.*\)"$/\1/p' <<<"$env_out")"
  anon="$(sed -n 's/^PUBLISHABLE_KEY="\(.*\)"$/\1/p' <<<"$env_out")"
  service="$(sed -n 's/^SERVICE_ROLE_KEY="\(.*\)"$/\1/p' <<<"$env_out")"
  [ -n "$api" ] && [ -n "$anon" ] && [ -n "$service" ] \
    || { echo "local stack not running (npx supabase start)" >&2; exit 1; }
}
