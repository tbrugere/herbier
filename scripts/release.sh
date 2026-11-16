#!/usr/bin/env bash
# Production build: web shell (release profile), Capacitor sync, signed APK.
# Usage: scripts/release.sh [--debug]
#   default   release APK signed by the release key (gradle assembleRelease)
#   --debug   debug APK of the same production bundle (gradle assembleDebug),
#             signed by the release key when it is set, so that it and the
#             release replace each other in place on the phone
# The values come from .env.prod (copy .env.prod.example) when it exists,
# else from the environment (CI), for this process only: dev builds, which
# never read them, keep the local Supabase stack and the debug key.
# Environment: ANDROID_HOME (~/Library/Android/sdk), for Gradle, apksigner and aapt2.
set -euo pipefail
root="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
cd "$root"
. scripts/lib/release-env.sh
case "${1:-}" in
  "") mode=release task=assembleRelease ;;
  --debug) mode=debug task=assembleDebug ;;
  *) echo "usage: $0 [--debug]" >&2; exit 2 ;;
esac
release_env_load "$root"
ok=0
release_env_check_backend || ok=1
release_env_check_picker || ok=1
release_env_check_signing "$mode" "$root" || ok=1
[ "$ok" = 0 ] || exit 1

android_home="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
# Gradle finds the SDK through ANDROID_HOME when android/local.properties
# (git-ignored, written by Android Studio) is absent, as in a fresh clone.
export ANDROID_HOME="$android_home"
# `|| true`: with no build-tools dir the check below says so (pipefail).
build_tools="$(ls -d "$android_home"/build-tools/*/ 2>/dev/null | sort -V | tail -n 1 || true)"
apksigner="${build_tools}apksigner"
aapt2="${build_tools}aapt2"
if [ -z "$build_tools" ] || [ ! -x "$apksigner" ] || [ ! -x "$aapt2" ]; then
  echo "release.sh: no apksigner/aapt2 under $android_home/build-tools (set ANDROID_HOME)" >&2
  exit 1
fi

dune build --profile release @web
if [ ! -s _build/default/web/dist/app.js ]; then
  echo "release.sh: web bundle missing (_build/default/web/dist/app.js)" >&2
  exit 1
fi
if grep -q herbierDev _build/default/web/dist/app.js; then
  echo "release.sh: release bundle contains dev pages (herbierDev)" >&2
  exit 1
fi
npx --no-install cap sync android
(cd android && ./gradlew "$task")

apk="android/app/build/outputs/apk/$mode/app-$mode.apk"
if [ ! -f "$apk" ]; then
  echo "release.sh: $apk was not produced (an unsigned build means the release key is not set)" >&2
  exit 1
fi
if [ "$mode" = release ] && release_env_rotation_enabled; then
  # The lineage lets an install signed with the previous key accept this
  # one, from Android 9 (apksigner's default starts the rotation at 13);
  # below, v2 keeps the previous key. Passwords go through env:, never the
  # command line.
  "$apksigner" sign \
    --ks "$HERBIER_PREVIOUS_KEYSTORE" \
    --ks-key-alias "$HERBIER_PREVIOUS_KEY_ALIAS" \
    --ks-pass env:HERBIER_PREVIOUS_KEYSTORE_PASSWORD \
    --key-pass env:HERBIER_PREVIOUS_KEY_PASSWORD \
    --next-signer \
    --ks "$HERBIER_RELEASE_KEYSTORE" \
    --ks-key-alias "$HERBIER_RELEASE_KEY_ALIAS" \
    --ks-pass env:HERBIER_RELEASE_KEYSTORE_PASSWORD \
    --key-pass env:HERBIER_RELEASE_KEY_PASSWORD \
    --lineage "$HERBIER_SIGNING_LINEAGE" \
    --rotation-min-sdk-version 28 \
    "$apk"
fi
certs="$("$apksigner" verify --print-certs "$apk")" || {
  echo "release.sh: $apk does not verify" >&2
  exit 1
}
badging="$("$aapt2" dump badging "$apk")"
echo "apk: $apk"
sed -n "s/^package: .*versionCode='\([^']*\)'.*/versionCode: \1/p" <<<"$badging"
version_name="$(sed -n "s/^package: .*versionName='\([^']*\)'.*/\1/p" <<<"$badging")"
echo "versionName: $version_name"
grep 'certificate SHA-256 digest' <<<"$certs"
if [ "$mode" = release ] && release_env_rotation_enabled; then
  "$apksigner" lineage --in "$apk" --print-certs | grep 'certificate SHA-256 digest'
fi
# Gradle and dune each run git describe: a tracked file changed between the
# two (cap sync rewriting a stale generated file) shows as -dirty in one only.
bundle_version="$(sed -n 's/^let git = "\(.*\)"$/\1/p' _build/default/app/version/herbier_version.ml)"
if [ "$version_name" != "$bundle_version" ]; then
  echo "release.sh: versionName $version_name is not the bundle's version $bundle_version (commit what the build changed: git status)" >&2
  exit 1
fi
