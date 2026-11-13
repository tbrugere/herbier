#!/usr/bin/env bash
# Production build: web shell (release profile), Capacitor sync, APK.
# Usage: scripts/release.sh [--debug]
#   default   signed release APK (gradle assembleRelease)
#   --debug   debug APK of the same production bundle (gradle assembleDebug),
#             to try the production backend on a phone
# Where the build signs in comes from .env.prod (copy .env.prod.example),
# loaded for this process only: dev builds, which never read it, keep
# defaulting to the local Supabase stack.
set -euo pipefail
cd "$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
case "${1:-}" in
  "") task=assembleRelease ;;
  --debug) task=assembleDebug ;;
  *) echo "usage: $0 [--debug]" >&2; exit 2 ;;
esac
if [ ! -f .env.prod ]; then
  echo ".env.prod is missing: copy .env.prod.example and fill it in" >&2
  exit 1
fi
set -a
. ./.env.prod
set +a
# Without all three the APK can never sign in (Auth.create sees "" and says
# so in 4m).
: "${HERBIER_SUPABASE_URL:?set in .env.prod}" \
  "${HERBIER_SUPABASE_PUBLISHABLE_KEY:?set in .env.prod}" \
  "${HERBIER_GOOGLE_WEB_CLIENT_ID:?set in .env.prod}"
case "$HERBIER_SUPABASE_URL$HERBIER_SUPABASE_PUBLISHABLE_KEY$HERBIER_GOOGLE_WEB_CLIENT_ID" in
  *"<"*) echo ".env.prod still has a <placeholder> from the example" >&2; exit 1 ;;
esac
dune build --profile release @web
test -s _build/default/web/dist/app.js
if grep -q herbierDev _build/default/web/dist/app.js; then
  echo "release bundle contains dev pages (herbierDev)" >&2
  exit 1
fi
npx cap sync android
(cd android && ./gradlew "$task")
