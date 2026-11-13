#!/usr/bin/env bash
# Record the PostgREST answers of test/fixtures/sync_*.json from the local
# stack (`npx supabase start`). The curl requests are written by hand to
# match app/sync/net/rest.ml's; test_rest checks only the answers' keys,
# against the catalog. A file name ends with the status the request must
# answer (the anon upsert's with the status answered); another status fails
# the script. A throwaway user, sync-fixtures@herbier.local, owns the rows
# and is deleted at the end, also on failure.
#
#   scripts/record-sync-fixtures.sh [--force]
#
# Rows have fixed ids and the literal values below, mirrored by the tests;
# only updated_at is the server's (trigger). An existing file is kept unless
# --force: fixtures are recorded once, never edited. No real account or
# token lands in a file (select answers carry no owner_id).
set -euo pipefail
root="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
# shellcheck source=lib/local-stack.sh
. "$root/scripts/lib/local-stack.sh"
require_tools curl jq
out="$root/test/fixtures"
force=0
case "$#:${1:-}" in
  0:) ;;
  1:--force) force=1 ;;
  *) echo "usage: $0 [--force]" >&2; exit 2 ;;
esac

local_stack_keys "$root"
rest="$api/rest/v1"

tmp="$(mktemp -d)"
user_id=""
cleanup() {
  if [ -n "$user_id" ]; then
    local status
    status="$(curl -sS -o /dev/null -w '%{http_code}' -X DELETE \
      "$api/auth/v1/admin/users/$user_id" \
      -H "apikey: $service" -H "Authorization: Bearer $service" || true)"
    [ "$status" = 200 ] \
      || echo "warning: deleting user $user_id: HTTP $status" >&2
  fi
  rm -rf "$tmp"
}
trap cleanup EXIT

# call <name> <expected status> <method> <url> <key> <body or ""> [curl args…]
# : the answer lands in $tmp/<name>; another status is fatal ("any" accepts
# every status and leaves it in $tmp/<name>.status).
call() {
  local name="$1" expected="$2" method="$3" url="$4" key="$5" body="$6"
  shift 6
  local args=(-sS -o "$tmp/$name" -w '%{http_code}' -X "$method" "$url"
    -H "apikey: $key")
  [ "$key" = "$service" ] && args+=(-H "Authorization: Bearer $service")
  [ -n "$body" ] && args+=(-H 'Content-Type: application/json' -d "$body")
  local status
  status="$(curl "${args[@]}" "$@")"
  echo "$status" >"$tmp/$name.status"
  [ "$expected" = any ] || [ "$status" = "$expected" ] || {
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

# 1. The throwaway user and its session (magic link verified directly). A
#    user left by an interrupted run is deleted first (its rows cascade):
#    reusing it would mix its old rows into the answers.
call users 200 GET "$api/auth/v1/admin/users?per_page=1000" "$service" ""
leftover="$(jq -r '[.users[] | select(.email == "sync-fixtures@herbier.local")][0].id // empty' \
  "$tmp/users")"
if [ -n "$leftover" ]; then
  call delete_leftover 200 DELETE "$api/auth/v1/admin/users/$leftover" \
    "$service" ""
fi
call user 200 POST "$api/auth/v1/admin/users" "$service" \
  '{"email":"sync-fixtures@herbier.local","email_confirm":true}'
user_id="$(jq -r .id "$tmp/user")"
call link 200 POST "$api/auth/v1/admin/generate_link" "$service" \
  '{"type":"magiclink","email":"sync-fixtures@herbier.local"}'
call verify 200 POST "$api/auth/v1/verify" "$anon" \
  "$(jq -c '{type:"magiclink", token_hash:.hashed_token}' "$tmp/link")"
token="$(jq -r .access_token "$tmp/verify")"

# Rest.upsert's headers (Content-Type is added by call).
upsert_headers=(-H "Authorization: Bearer $token"
  -H 'Prefer: resolution=merge-duplicates,missing=default')
upsert() { # <name> <table> <json row> [expected status]
  call "$1" "${4:-201}" POST "$rest/$2" "$anon" "$3" "${upsert_headers[@]}"
}
# Rest.select_since's request (page 0 unless a range is given).
pull() { # <name> <table> <filter or ""> <columns> [range]
  local filter="${3:+$3&}"
  call "$1" 200 GET "$rest/$2?${filter}select=$4&order=updated_at,id" \
    "$anon" "" -H "Authorization: Bearer $token" -H 'Range-Unit: items' \
    -H "Range: ${5:-0-499}" -H 'Accept: application/json' \
    -H 'Prefer: missing=default'
}

plant=01965d4e-0000-7000-8000-000000000001
tag=01965d4e-0000-7000-8000-000000000002
observation=01965d4e-0000-7000-8000-000000000003
photo=01965d4e-0000-7000-8000-000000000004
plant_tag=01965d4e-0000-7000-8000-000000000005
plant_ref=01965d4e-0000-7000-8000-000000000006
reference=01965d4e-0000-7000-8000-000000000007
no_plant=01965d4e-0000-7000-8000-0000000000ff

# 2. One row per table, parents first; then the plant again (update path),
#    with notes and the cover (PostgREST answers 200 there, 201 for an
#    insert). The reference payload's keys are out of
#    jsonb order (longer key first, nested keys unsorted): the select
#    answer shows them reordered.
upsert plant_v1 plants '{"id":"'$plant'","display_name":"Digitale pourpre","aliases":["Digitale","Gant de Notre-Dame"],"scientific_name":"Digitalis purpurea","authorship":"L.","gbif_key":5414995,"notes":"","notes_updated_at":null,"cover_photo_id":null,"created_at":"2026-11-12T09:00:00Z","updated_at":"2026-11-12T09:00:00Z","deleted_at":null}'
upsert tag tags '{"id":"'$tag'","name":"Lisière","created_at":"2026-11-12T09:01:00Z","updated_at":"2026-11-12T09:01:00Z","deleted_at":null}'
upsert observation observations '{"id":"'$observation'","plant_id":"'$plant'","at":"2026-11-12T08:45:00Z","lat":45.5,"lon":3.25,"accuracy_m":12.5,"place_label":"Bois","place_derived":null,"note":"Fleurs ouvertes","created_at":"2026-11-12T09:02:00Z","updated_at":"2026-11-12T09:02:00Z","deleted_at":null}'
upsert photo photos '{"id":"'$photo'","observation_id":"'$observation'","taken_at":"2026-11-12T08:46:00Z","width":1600,"height":1200,"sha256":"9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08","preview_path":"previews/'$photo'.jpg","preview_bucket_key":null,"original_target":"drive","drive_file_id":null,"upload_state":"pending","created_at":"2026-11-12T09:03:00Z","updated_at":"2026-11-12T09:03:00Z","deleted_at":null}'
upsert plant_tag plant_tags '{"id":"'$plant_tag'","plant_id":"'$plant'","tag_id":"'$tag'","created_at":"2026-11-12T09:04:00Z","updated_at":"2026-11-12T09:04:00Z","deleted_at":null}'
upsert plant_ref plant_refs '{"id":"'$plant_ref'","plant_id":"'$plant'","source":"gbif","external_id":"5414995","url":"https://www.gbif.org/species/5414995","created_at":"2026-11-12T09:05:00Z","updated_at":"2026-11-12T09:05:00Z","deleted_at":null}'
upsert reference reference '{"id":"'$reference'","plant_id":"'$plant'","source":"gbif","fetched_at":"2026-11-12T09:06:00Z","payload":{"vernacular":[{"name":"Digitale pourpre","lang":"fra"}],"species":{"rank":"SPECIES","key":5414995,"canonicalName":"Digitalis purpurea"}},"status":"complete","created_at":"2026-11-12T09:06:00Z","updated_at":"2026-11-12T09:06:00Z","deleted_at":null}'
upsert plant_v2 plants '{"id":"'$plant'","display_name":"Digitale pourpre","aliases":["Digitale","Gant de Notre-Dame"],"scientific_name":"Digitalis purpurea","authorship":"L.","gbif_key":5414995,"notes":"Mi-ombre","notes_updated_at":"2026-11-12T09:07:00Z","cover_photo_id":"'$photo'","created_at":"2026-11-12T09:00:00Z","updated_at":"2026-11-12T09:07:00Z","deleted_at":null}' 200

# 3. Select-since with no filter, each table (Synced.row's columns).
pull s_plants plants "" id,display_name,aliases,scientific_name,authorship,gbif_key,notes,notes_updated_at,cover_photo_id,created_at,updated_at,deleted_at
keep s_plants sync_select_plants_200.json
pull s_tags tags "" id,name,created_at,updated_at,deleted_at
keep s_tags sync_select_tags_200.json
pull s_observations observations "" id,plant_id,at,lat,lon,accuracy_m,place_label,place_derived,note,created_at,updated_at,deleted_at
keep s_observations sync_select_observations_200.json
pull s_photos photos "" id,observation_id,taken_at,width,height,sha256,preview_path,preview_bucket_key,original_target,drive_file_id,upload_state,created_at,updated_at,deleted_at
keep s_photos sync_select_photos_200.json
pull s_plant_tags plant_tags "" id,plant_id,tag_id,created_at,updated_at,deleted_at
keep s_plant_tags sync_select_plant_tags_200.json
pull s_plant_refs plant_refs "" id,plant_id,source,external_id,url,created_at,updated_at,deleted_at
keep s_plant_refs sync_select_plant_refs_200.json
pull s_reference reference "" id,plant_id,source,fetched_at,payload,status,created_at,updated_at,deleted_at
keep s_reference sync_select_reference_200.json

# 4. Errors. A token that is not a JWT.
call bad_jwt 401 POST "$rest/plants" "$anon" "$(cat <<JSON
{"id":"$plant","display_name":"x","aliases":[],"scientific_name":null,"authorship":null,"gbif_key":null,"notes":"","notes_updated_at":null,"cover_photo_id":null,"created_at":"2026-11-12T09:00:00Z","updated_at":"2026-11-12T09:00:00Z","deleted_at":null}
JSON
)" -H 'Authorization: Bearer not-a-jwt' \
  -H 'Prefer: resolution=merge-duplicates,missing=default'
keep bad_jwt sync_upsert_plants_bad_jwt_401.json

# No Authorization: the anon role. Named after the status answered.
call anon_upsert any POST "$rest/plants" "$anon" "$(cat <<JSON
{"id":"$plant","display_name":"x","aliases":[],"scientific_name":null,"authorship":null,"gbif_key":null,"notes":"","notes_updated_at":null,"cover_photo_id":null,"created_at":"2026-11-12T09:00:00Z","updated_at":"2026-11-12T09:00:00Z","deleted_at":null}
JSON
)" -H 'Prefer: resolution=merge-duplicates,missing=default'
anon_status="$(cat "$tmp/anon_upsert.status")"
case "$anon_status" in
  4??) keep anon_upsert "sync_upsert_plants_anon_$anon_status.json" ;;
  *) echo "anon upsert: HTTP $anon_status, expected a 4xx" >&2; exit 1 ;;
esac

# An observation of a plant that does not exist (23503).
upsert fk observations '{"id":"01965d4e-0000-7000-8000-000000000013","plant_id":"'$no_plant'","at":"2026-11-12T08:45:00Z","lat":null,"lon":null,"accuracy_m":null,"place_label":null,"place_derived":null,"note":null,"created_at":"2026-11-12T09:02:00Z","updated_at":"2026-11-12T09:02:00Z","deleted_at":null}' 409
keep fk sync_upsert_observations_fk_409.json

# lat without lon (23514).
upsert check observations '{"id":"01965d4e-0000-7000-8000-000000000023","plant_id":null,"at":"2026-11-12T08:45:00Z","lat":45.5,"lon":null,"accuracy_m":null,"place_label":null,"place_derived":null,"note":null,"created_at":"2026-11-12T09:02:00Z","updated_at":"2026-11-12T09:02:00Z","deleted_at":null}' 400
keep check sync_upsert_observations_check_400.json

# 5. Pull cases, after every recording above, which they leave as they
#    are. The five files share this run's server timestamps (the tests
#    compare page 0's and page 1's), so they are recorded together: one
#    missing, all five are recorded again.
for file in sync_select_plants_empty_200.json \
  sync_select_tags_deleted_200.json sync_select_tags_page0_200.json \
  sync_select_tags_page1_200.json \
  sync_select_tags_page1_moved_200.json; do
  [ -e "$out/$file" ] || force=1
done
# An empty answer: nothing after a far-future bound.
pull s_plants_empty plants updated_at=gt.2100-01-01T00:00:00Z id,display_name,aliases,scientific_name,authorship,gbif_key,notes,notes_updated_at,cover_photo_id,created_at,updated_at,deleted_at
keep s_plants_empty sync_select_plants_empty_200.json

# The fixture tag soft-deleted by an upsert carrying deleted_at.
upsert tag_deleted tags '{"id":"'$tag'","name":"Lisière","created_at":"2026-11-12T09:01:00Z","updated_at":"2026-11-12T09:08:00Z","deleted_at":"2026-11-12T09:08:00Z"}' 200
pull s_tags_deleted tags "" id,name,created_at,updated_at,deleted_at
keep s_tags_deleted sync_select_tags_deleted_200.json

# Paging: 500 more tags in one POST (ids 01965d4e-…-000000001001 to
# …1500, one transaction, so one updated_at), 501 tags in all: page 0 holds
# 500, page 1 the last one.
tag_id() { printf '01965d4e-0000-7000-8000-%012d' "$((1000 + $1))"; }
bulk="$(for n in $(seq 1 500); do
  printf '{"id":"%s","name":"Tag %03d","created_at":"2026-11-12T09:10:00Z","updated_at":"2026-11-12T09:10:00Z","deleted_at":null}\n' \
    "$(tag_id "$n")" "$n"
done | jq -cs .)"
upsert bulk_tags tags "$bulk"
pull s_tags_page0 tags "" id,name,created_at,updated_at,deleted_at 0-499
keep s_tags_page0 sync_select_tags_page0_200.json
pull s_tags_page1 tags "" id,name,created_at,updated_at,deleted_at 500-999
keep s_tags_page1 sync_select_tags_page1_200.json

# The offset race (architecture §4): a tag of page 0 is written again
# between the two page requests; its updated_at moves last, so page 1 now
# holds it a second time.
upsert tag_moved tags '{"id":"'"$(tag_id 1)"'","name":"Tag 001 bis","created_at":"2026-11-12T09:10:00Z","updated_at":"2026-11-12T09:11:00Z","deleted_at":null}' 200
pull s_tags_page1_moved tags "" id,name,created_at,updated_at,deleted_at \
  500-999
keep s_tags_page1_moved sync_select_tags_page1_moved_200.json
