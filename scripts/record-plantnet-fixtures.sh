#!/usr/bin/env bash
# Record Pl@ntNet's answers as test/fixtures/plantnet_*.json
# (docs/notes/plantnet-webview.md).
# A name ends with the HTTP status answered; a status the case does not expect
# fails the script.
#
#   HERBIER_PLANTNET_API_KEY=… scripts/record-plantnet-fixtures.sh [--force]
#
# An existing file is kept unless --force: fixtures are recorded once, never
# edited. An existing <prefix><3 digits>.json counts as present whatever its
# status: some cases (other Origin, no Origin, no-reject) have no fixed
# status. Two groups:
#
# - no key needed (always recorded): the 401 of an invalid key;
# - the user's key in HERBIER_PLANTNET_API_KEY, exposed with https://localhost
#   as an authorized domain (never committed, never printed, never on a
#   command line: curl reads the URL from a config on a pipe, jq and grep read
#   the key from stdin or a pipe; it stays in the environment of the child
#   processes, readable by the same user only): first a free
#   GET /v2/projects with Origin: https://localhost, which must answer 200
#   (else exit 3 before any credit is spent); then the floras, the same GET
#   with another Origin and without one (free), and four identify requests,
#   one credit each, each skipped when its file exists. Skipped, with a
#   message, when the variable is unset.
#
# Every request but the two refusal cases sends Origin: https://localhost, as
# the WebView does. The images are Pl@ntNet's own examples (plantnet/my.plantnet,
# pinned by commit and sha256) and a generated grey square, all in a temporary
# directory: no user photo, nothing personal. Every answer is grepped for the
# key before it is kept, and every plantnet_*.json at the end.
set -euo pipefail
root="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
for tool in curl jq uv; do
  command -v "$tool" >/dev/null || { echo "$tool not found" >&2; exit 1; }
done
if command -v sha256sum >/dev/null; then
  sha256() { sha256sum "$1" | cut -d' ' -f1; }
elif command -v shasum >/dev/null; then
  sha256() { shasum -a 256 "$1" | cut -d' ' -f1; }
else
  echo "sha256sum or shasum not found" >&2
  exit 1
fi
out="$root/test/fixtures"
force=0
case "$#:${1:-}" in
  0:) ;;
  1:--force) force=1 ;;
  *) echo "usage: $0 [--force]" >&2; exit 2 ;;
esac

api="https://my-api.plantnet.org/v2"
origin="https://localhost"
examples="https://raw.githubusercontent.com/plantnet/my.plantnet/2fca71a1be5abd7dd9186d3899ac05b6bcda7a82/examples/data"
key="${HERBIER_PLANTNET_API_KEY:-}"
credits=0

tmp="$(mktemp -d)"
# A request counts before curl runs, so the count is an upper bound.
trap 'echo "identify credits spent: at most $credits" >&2; rm -rf "$tmp"' EXIT

# fail_if_key <file>: an answer holding the key is deleted, never kept. The
# key reaches grep as a pattern file on a pipe (never empty: skipped without
# a key, an empty pattern would match everything).
fail_if_key() {
  if [ -n "$key" ] && grep -qFf <(printf '%s\n' "$key") "$1"; then
    rm -f "$1"
    echo "key found in $(basename "$1")" >&2
    exit 1
  fi
}

# call <name> <expected status regex> <method> <url> [curl args…]: the answer
# lands in $tmp/<name>, its status in $tmp/<name>.status. The URL (it may hold
# the key) goes through a curl config on a pipe, never argv, and is never
# printed.
call() {
  local name="$1" expected="$2" method="$3" url="$4"
  shift 4
  local written status time
  written="$(curl -s -o "$tmp/$name" -w '%{http_code} %{time_total}' \
    -X "$method" -K <(printf 'url = "%s"\n' "$url") "$@")" || {
    echo "$name: curl failed ($?)" >&2
    exit 1
  }
  status="${written%% *}"
  time="${written#* }"
  fail_if_key "$tmp/$name"
  echo "$name: HTTP $status in $time s"
  printf '%s' "$status" >"$tmp/$name.status"
  [[ "$status" =~ $expected ]] || {
    echo "$name: HTTP $status, expected $expected" >&2
    cat "$tmp/$name" >&2
    echo >&2
    exit 1
  }
}

# present <prefix>: some test/fixtures/<prefix><status>.json exists (and no
# --force).
present() {
  [ "$force" = 0 ] && compgen -G "$out/$1[0-9][0-9][0-9].json" >/dev/null
}

# keep <name> <prefix>: the answer, pretty-printed, becomes the fixture
# <prefix><status>.json unless a file with that prefix exists.
keep() {
  local name="$1" prefix="$2"
  local file
  file="$prefix$(cat "$tmp/$name.status").json"
  if present "$prefix"; then
    echo "skip $prefix*.json"
  else
    jq . "$tmp/$name" >"$tmp/$name.pretty" || {
      echo "$name: answer is not JSON" >&2
      head -c 2000 "$tmp/$name" >&2
      echo >&2
      exit 1
    }
    fail_if_key "$tmp/$name.pretty"
    mv "$tmp/$name.pretty" "$out/$file"
    echo "recorded $file"
  fi
}

# Pl@ntNet's example images, checked before any Pl@ntNet request.
fetch_example() {
  local file="$1" sum="$2"
  curl -sfL -o "$tmp/$file" "$examples/$file" || {
    echo "$file: download failed" >&2
    exit 1
  }
  [ "$(sha256 "$tmp/$file")" = "$sum" ] || {
    echo "$file: sha256 mismatch" >&2
    exit 1
  }
}
fetch_example image_1.jpeg \
  f5566d3b9db826bc60a4082587a75a363649acb73fd8fbf537df2c219bc3036b
fetch_example image_2.jpeg \
  20e3fa3940e423f8264999c88effd06526061a916797c38e587e4ffca09c632c
# The non-plant image: a uniform mid-grey square, generated, never committed.
uv run --quiet --with pillow python3 -c \
  'import sys; from PIL import Image; Image.new("RGB",(800,800),(128,128,128)).save(sys.argv[1],quality=90)' \
  "$tmp/not_plant.jpg"

# uri <string>: the string URI-encoded, read from stdin (never argv).
uri() { printf '%s' "$1" | jq -sRr @uri; }

# identify_url <URI-encoded key> [extra query]: the /identify/all URL.
identify_url() {
  printf '%s/identify/all?include-related-images=true&lang=fr&nb-results=5&api-key=%s%s' \
    "$api" "$1" "${2:-}"
}
# The multipart image parts, one organ then one image each.
part() { echo "images=@$tmp/$1;filename=$1;type=image/jpeg"; }
one=(-F organs=auto -F "$(part image_1.jpeg)")
two=(-F organs=flower -F "$(part image_1.jpeg)" -F organs=leaf
  -F "$(part image_2.jpeg)")
grey=(-F organs=auto -F "$(part not_plant.jpg)")
at_origin=(-H "Origin: $origin")

# 1. No key: an invalid key's 401 (no account, no credit).
if ! present plantnet_identify_invalid_key_; then
  call invalid_key '^401$' POST "$(identify_url invalid-key-for-fixtures)" \
    "${at_origin[@]}" "${one[@]}"
  keep invalid_key plantnet_identify_invalid_key_
fi

if [ -z "$key" ]; then
  echo "HERBIER_PLANTNET_API_KEY unset: keyed answers not recorded" >&2
  exit 0
fi
key_uri="$(uri "$key")"
projects_url="$api/projects?lang=fr&api-key=$key_uri"

# 2. Exposure guard (free): a key not exposed, or without https://localhost
# among its authorized domains, stops here, before any credit. Its 200 is the
# floras' fixture.
call projects '^[0-9]{3}$' GET "$projects_url" "${at_origin[@]}"
[ "$(cat "$tmp/projects.status")" = 200 ] || {
  echo "Pl@ntNet refused the exposure check for $origin (HTTP $(cat "$tmp/projects.status")): a 403 « CORS error: Origin not allowed » means the key is not exposed for it" >&2
  cat "$tmp/projects" >&2
  echo >&2
  exit 3
}
keep projects plantnet_projects_fr_

# 3. The same GET from another origin and without Origin (free), each skipped
# when its file exists.
if ! present plantnet_projects_origin_refused_; then
  call origin_refused '^4[0-9][0-9]$' GET "$projects_url" \
    -H 'Origin: https://example.org'
  keep origin_refused plantnet_projects_origin_refused_
fi
if ! present plantnet_projects_no_origin_; then
  call no_origin '^[0-9]{3}$' GET "$projects_url"
  keep no_origin plantnet_projects_no_origin_
fi

# 4. Identify, one credit per request, each skipped when its file exists.
# identify <name> <expected> <file prefix> <extra query> [curl args…]
identify() {
  local name="$1" expected="$2" prefix="$3" extra="$4"
  shift 4
  if present "$prefix"; then
    echo "skip $prefix*.json"
    return
  fi
  credits=$((credits + 1))
  call "$name" "$expected" POST "$(identify_url "$key_uri" "$extra")" \
    "${at_origin[@]}" "$@"
  keep "$name" "$prefix"
}
identify one_auto '^200$' plantnet_identify_one_auto_ '' "${one[@]}"
identify two_flower_leaf '^200$' plantnet_identify_two_flower_leaf_ '' \
  "${two[@]}"
identify not_plant '^404$' plantnet_identify_not_plant_ '' "${grey[@]}"
identify not_plant_no_reject '^(200|404)$' \
  plantnet_identify_not_plant_no_reject_ '&no-reject=true' "${grey[@]}"

for f in "$out"/plantnet_*.json; do
  if [ -e "$f" ]; then fail_if_key "$f"; fi
done
