#!/usr/bin/env bash
# Record the Google Drive v3 answers of test/fixtures/drive_*.json (and
# drive_*.txt, kept verbatim: answers that are not JSON, and headers): the
# bodies app/photos/drive.ml classifies and decodes, and the resumable
# session's answers the upload job (UploadWorker.java) reads. The file name
# ends with the HTTP status the request must answer; another status fails the
# script. The
# URLs are written out exactly as Drive.find_folder, create_original, … render
# them (test/photos/test_drive.ml asserts the same strings).
#
#   scripts/record-drive-fixtures.sh [--force]
#
# An existing file is kept unless --force: fixtures are recorded once, never
# edited. Two groups:
#
# - no token needed (always recorded): a 403 without Authorization, the 401s
#   of an invalid token (the rename's PATCH included), and the 404 of an
#   unknown resumable session;
# - a drive.file access token in HERBIER_DRIVE_TOKEN (from the OAuth 2.0
#   Playground with the …/auth/drive.file scope; never committed, never
#   printed): the success answers, made in a throwaway root folder
#   "Herbier-fixtures" with a 1-pixel JPEG whose herbier_photo_id is the nil
#   UUID; the folder is trashed at the end, also on failure. Among them, a
#   root folder's files.get present, after a move and rename, and trashed
#   (drive_files_get_folder_{present,moved,trashed}_200.json), and the
#   metadata Drive.get_folder reads of a folder, a trashed folder, a file and
#   an unknown id (drive_files_get_folder_meta_*.json), and files.update of
#   the root's name on a folder, a trashed folder and an unknown id
#   (drive_files_update_name_*.json). The resumable
#   session's headers are recorded too, filtered: the status line,
#   content-type and location, whose upload_id (a credential while the
#   session lives) is replaced by a fixed placeholder. Skipped, with a
#   message, when the variable is unset. HERBIER_GOOGLE_NO_DRIVE_TOKEN, a
#   Google token without any Drive scope (optional), adds the 403 of a
#   missing scope.
#
# No personal data lands in the files: no request asks for owners or emails,
# and the ids are those of the throwaway files. Check before committing.
set -euo pipefail
root="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
for tool in curl jq; do
  command -v "$tool" >/dev/null || { echo "$tool not found" >&2; exit 1; }
done
out="$root/test/fixtures"
force=0
case "$#:${1:-}" in
  0:) ;;
  1:--force) force=1 ;;
  *) echo "usage: $0 [--force]" >&2; exit 2 ;;
esac

api="https://www.googleapis.com/drive/v3/files"
upload_api="https://www.googleapis.com/upload/drive/v3/files"
boundary="herbier-000102030405060708090a0b0c0d0e0f"
nil_uuid="00000000-0000-0000-0000-000000000000"

tmp="$(mktemp -d)"
folder_id=""
cleanup() {
  if [ -n "$folder_id" ] && [ -n "${HERBIER_DRIVE_TOKEN:-}" ]; then
    curl -sS -o /dev/null -X PATCH "$api/$folder_id?fields=id" \
      -H "@$tmp/auth_header" \
      -H 'Content-Type: application/json; charset=UTF-8' \
      -d '{"trashed":true}' || true
  fi
  rm -rf "$tmp"
}
trap cleanup EXIT

# call <name> <expected status> <method> <url> [curl args…]: the answer lands
# in $tmp/<name>; another status is fatal.
call() {
  local name="$1" expected="$2" method="$3" url="$4"
  shift 4
  local status
  status="$(curl -sS -o "$tmp/$name" -w '%{http_code}' -X "$method" "$url" "$@")" || {
    echo "$name: curl failed ($?)" >&2
    exit 1
  }
  [ "$status" = "$expected" ] || {
    echo "$name: HTTP $status, expected $expected" >&2
    cat "$tmp/$name" >&2
    exit 1
  }
}

# keep <name> <file>: the answer, pretty-printed, becomes the fixture unless
# it exists.
keep() {
  local name="$1" file="$2"
  if [ -e "$out/$file" ] && [ "$force" = 0 ]; then
    echo "skip $file"
  else
    jq . "$tmp/$name" >"$tmp/$name.pretty"
    mv "$tmp/$name.pretty" "$out/$file"
    echo "recorded $file"
  fi
}

# keep_raw <name> <file>: as keep, the answer verbatim (not JSON).
keep_raw() {
  local name="$1" file="$2"
  if [ -e "$out/$file" ] && [ "$force" = 0 ]; then
    echo "skip $file"
  else
    cp "$tmp/$name" "$out/$file"
    echo "recorded $file"
  fi
}

# The metadata Drive.create_session sends: the nil-UUID file into <parent>.
session_metadata() {
  jq -cn --arg parent "$1" --arg id "$nil_uuid" '{
    name: "fixture.jpg", mimeType: "image/jpeg", parents: [$parent],
    appProperties: {herbier_photo_id: $id, sha256: ("0" * 64)}}'
}

# The multipart body Drive.create_original frames: metadata part, then the
# media part (a 1-pixel JPEG), with CRLFs.
multipart() {
  local parent="$1"
  local metadata
  metadata="$(jq -cn --arg parent "$parent" --arg id "$nil_uuid" '{
    name: "fixture.jpg", mimeType: "image/jpeg", parents: [$parent],
    appProperties: {herbier_photo_id: $id, sha256: ("0" * 64)}}')"
  {
    printf -- '--%s\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n%s' \
      "$boundary" "$metadata"
    printf -- '\r\n--%s\r\nContent-Type: image/jpeg\r\n\r\n' "$boundary"
    printf '%s' '/9j/4AAQSkZJRgABAQEASABIAAD/2wBDAP//////////////////////////////////////////////////////////////////////////////////////wgALCAABAAEBAREA/8QAFBABAAAAAAAAAAAAAAAAAAAAAP/aAAgBAQABPxA=' \
      | base64 --decode
    printf -- '\r\n--%s--\r\n' "$boundary"
  } >"$tmp/multipart"
}

get_trashed_url() { echo "$api/$1?fields=id,trashed"; }
# Drive.get_folder's URL (id, name, mimeType, trashed).
get_folder_meta_url() { echo "$api/$1?fields=id,name,mimeType,trashed"; }
# Drive.update_name's URL (files.update of the root's name, same fields).
update_name_url() { echo "$api/$1?fields=id,name,mimeType,trashed"; }
create_original_url="$upload_api?uploadType=multipart&fields=id,webViewLink"
create_session_url="$upload_api?uploadType=resumable&fields=id,webViewLink"
unknown_session_url="$upload_api?uploadType=resumable&upload_id=herbier-fixture-unknown"
find_fixture_folder_url="$api?q=name%20%3D%20%27Herbier-fixtures%27%20and%20mimeType%20%3D%20%27application%2Fvnd.google-apps.folder%27%20and%20%27root%27%20in%20parents%20and%20trashed%20%3D%20false&fields=files%28id%29&orderBy=createdTime&pageSize=10&spaces=drive"
find_nil_original_url="$api?q=appProperties%20has%20%7B%20key%3D%27herbier_photo_id%27%20and%20value%3D%2700000000-0000-0000-0000-000000000000%27%20%7D%20and%20trashed%20%3D%20false&fields=files%28id%2CwebViewLink%29&orderBy=createdTime&pageSize=10&spaces=drive"

# 1. No token: Google answers 403 for an anonymous call.
call no_token 403 GET "$(get_trashed_url abc)"
keep no_token drive_files_get_no_token_403.json

# 2. An invalid token, on a read and on the upload.
call invalid_get 401 GET "$(get_trashed_url abc)" \
  -H 'Authorization: Bearer ya29.invalid'
keep invalid_get drive_files_get_invalid_token_401.json
call invalid_folder_meta 401 GET "$(get_folder_meta_url abc)" \
  -H 'Authorization: Bearer ya29.invalid'
keep invalid_folder_meta drive_files_get_folder_meta_invalid_token_401.json
call invalid_update 401 PATCH "$(update_name_url abc)" \
  -H 'Authorization: Bearer ya29.invalid' \
  -H 'Content-Type: application/json; charset=UTF-8' \
  -d '{"name":"Herbier-fixtures"}'
keep invalid_update drive_files_update_name_invalid_token_401.json
multipart root
call invalid_create 401 POST "$create_original_url" \
  -H 'Authorization: Bearer ya29.invalid' \
  -H "Content-Type: multipart/related; boundary=$boundary" \
  --data-binary "@$tmp/multipart"
keep invalid_create drive_files_create_invalid_token_401.json
call invalid_session 401 POST "$create_session_url" \
  -H 'Authorization: Bearer invalid' \
  -H 'Content-Type: application/json; charset=UTF-8' \
  -d "$(session_metadata root)"
keep invalid_session drive_files_create_session_invalid_token_401.json

# 3. An unknown (or expired) resumable session, asked how much it holds, as
# the upload job does at the start of every run.
call unknown_session 404 PUT "$unknown_session_url" \
  -H 'Content-Range: bytes */10' -H 'Content-Length: 0'
keep_raw unknown_session drive_session_put_unknown_404.txt

if [ -z "${HERBIER_DRIVE_TOKEN:-}" ]; then
  echo "HERBIER_DRIVE_TOKEN unset: success answers not recorded" >&2
  exit 0
fi
# The tokens go through header files, not curl's argv (visible in ps).
printf 'Authorization: Bearer %s\n' "$HERBIER_DRIVE_TOKEN" >"$tmp/auth_header"
auth=(-H "@$tmp/auth_header")
json=(-H 'Content-Type: application/json; charset=UTF-8')

# 4. The folder, absent then created then found.
call folder_absent 200 GET "$find_fixture_folder_url" "${auth[@]}"
[ "$(jq '.files | length' "$tmp/folder_absent")" = 0 ] || {
  echo "a Herbier-fixtures folder exists already: trash it first" >&2
  exit 1
}
keep folder_absent drive_files_list_folder_absent_200.json
call folder_created 200 POST "$api?fields=id" "${auth[@]}" "${json[@]}" \
  -d '{"name":"Herbier-fixtures","mimeType":"application/vnd.google-apps.folder","parents":["root"]}'
folder_id="$(jq -r .id "$tmp/folder_created")"
keep folder_created drive_files_create_folder_200.json
call folder_found 200 GET "$find_fixture_folder_url" "${auth[@]}"
keep folder_found drive_files_list_folder_found_200.json

# 4b. A root folder checked by id: present, renamed by the app
# (Drive.rename_root's files.update), then moved into another folder, then
# trashed and renamed again. The move and trash PATCHes are not recorded; the
# two files.update of the name (live and trashed) are. The id,trashed answers keep the health check's shape; the app's
# root check (Drive.resolve_root) reads id,name,mimeType,trashed, so it
# learns a name changed in Drive. Both folders live inside Herbier-fixtures,
# trashed with it.
call root_created 200 POST "$api?fields=id" "${auth[@]}" "${json[@]}" \
  -d "$(jq -cn --arg parent "$folder_id" '{name: "Herbier-fixtures-root",
    mimeType: "application/vnd.google-apps.folder", parents: [$parent]}')"
root_id="$(jq -r .id "$tmp/root_created")"
call other_created 200 POST "$api?fields=id" "${auth[@]}" "${json[@]}" \
  -d "$(jq -cn --arg parent "$folder_id" '{name: "Herbier-fixtures-other",
    mimeType: "application/vnd.google-apps.folder", parents: [$parent]}')"
other_id="$(jq -r .id "$tmp/other_created")"
call root_present 200 GET "$(get_trashed_url "$root_id")" "${auth[@]}"
keep root_present drive_files_get_folder_present_200.json
call root_renamed 200 PATCH "$(update_name_url "$root_id")" "${auth[@]}" \
  "${json[@]}" -d '{"name":"Herbier-fixtures-renamed"}'
keep root_renamed drive_files_update_name_200.json
call root_move 200 PATCH \
  "$api/$root_id?addParents=$other_id&removeParents=$folder_id&fields=id" \
  "${auth[@]}" "${json[@]}" -d '{"name":"Herbier-fixtures-renamed"}'
call root_moved 200 GET "$(get_trashed_url "$root_id")" "${auth[@]}"
keep root_moved drive_files_get_folder_moved_200.json
call root_meta_usable 200 GET "$(get_folder_meta_url "$root_id")" "${auth[@]}"
keep root_meta_usable drive_files_get_folder_meta_usable_200.json
call root_trash 200 PATCH "$api/$root_id?fields=id" "${auth[@]}" "${json[@]}" \
  -d '{"trashed":true}'
call root_trashed 200 GET "$(get_trashed_url "$root_id")" "${auth[@]}"
keep root_trashed drive_files_get_folder_trashed_200.json
call root_renamed_trashed 200 PATCH "$(update_name_url "$root_id")" \
  "${auth[@]}" "${json[@]}" -d '{"name":"Herbier-fixtures-renamed"}'
keep root_renamed_trashed drive_files_update_name_trashed_200.json
call root_meta_trashed 200 GET "$(get_folder_meta_url "$root_id")" "${auth[@]}"
keep root_meta_trashed drive_files_get_folder_meta_trashed_200.json

# 5. The original, uploaded into it, then found by its appProperties.
multipart "$folder_id"
call original_created 200 POST "$create_original_url" "${auth[@]}" \
  -H "Content-Type: multipart/related; boundary=$boundary" \
  --data-binary "@$tmp/multipart"
file_id="$(jq -r .id "$tmp/original_created")"
keep original_created drive_files_create_original_200.json
call original_found 200 GET "$find_nil_original_url" "${auth[@]}"
keep original_found drive_files_list_original_found_200.json

# 6. A resumable session into the folder (its headers), then its bytes in
# one PUT, as the upload job sends them.
call session 200 POST "$create_session_url" "${auth[@]}" "${json[@]}" \
  -D "$tmp/session_headers" -d "$(session_metadata "$folder_id")"
tr -d '\r' <"$tmp/session_headers" \
  | awk 'NR == 1 || tolower($1) == "content-type:" || tolower($1) == "location:"' \
  | sed -E 's/upload_id=[^&[:space:]]*/upload_id=herbier-fixture/' \
  >"$tmp/session_headers_kept"
keep_raw session_headers_kept drive_files_create_session_200.headers.txt
session_url="$(tr -d '\r' <"$tmp/session_headers" | awk 'tolower($1) == "location:" { print $2; exit }')"
[ -n "$session_url" ] || { echo "session: no location header" >&2; exit 1; }
printf '%s' '/9j/4AAQSkZJRgABAQEASABIAAD/2wBDAP//////////////////////////////////////////////////////////////////////////////////////wgALCAABAAEBAREA/8QAFBABAAAAAAAAAAAAAAAAAAAAAP/aAAgBAQABPxA=' \
  | base64 --decode >"$tmp/pixel.jpg"
call session_complete 200 PUT "$session_url" -H 'Content-Type: image/jpeg' \
  --data-binary "@$tmp/pixel.jpg"
keep session_complete drive_session_put_complete_200.json

# 7. Its presence: there, trashed (the PATCH is not recorded), unknown.
call present 200 GET "$(get_trashed_url "$file_id")" "${auth[@]}"
keep present drive_files_get_present_200.json
call meta_not_folder 200 GET "$(get_folder_meta_url "$file_id")" "${auth[@]}"
keep meta_not_folder drive_files_get_folder_meta_not_folder_200.json
call trash 200 PATCH "$api/$file_id?fields=id" "${auth[@]}" "${json[@]}" \
  -d '{"trashed":true}'
call trashed 200 GET "$(get_trashed_url "$file_id")" "${auth[@]}"
keep trashed drive_files_get_trashed_200.json
call unknown 404 GET "$(get_trashed_url 0000000000000000000000000000000)" \
  "${auth[@]}"
keep unknown drive_files_get_unknown_404.json
call meta_unknown 404 GET \
  "$(get_folder_meta_url 0000000000000000000000000000000)" "${auth[@]}"
keep meta_unknown drive_files_get_folder_meta_unknown_404.json
call update_unknown 404 PATCH \
  "$(update_name_url 0000000000000000000000000000000)" "${auth[@]}" \
  "${json[@]}" -d '{"name":"Herbier-fixtures"}'
keep update_unknown drive_files_update_name_unknown_404.json

# 8. A token without Drive scope (optional).
if [ -n "${HERBIER_GOOGLE_NO_DRIVE_TOKEN:-}" ]; then
  printf 'Authorization: Bearer %s\n' "$HERBIER_GOOGLE_NO_DRIVE_TOKEN" \
    >"$tmp/no_drive_header"
  call scope_missing 403 GET "$find_fixture_folder_url" -H "@$tmp/no_drive_header"
  keep scope_missing drive_files_list_scope_missing_403.json
fi
