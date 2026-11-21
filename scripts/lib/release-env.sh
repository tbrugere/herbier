# Sourced by scripts/release.sh (and test/scripts/release_env.t): loading
# and checking the production values, before anything is built. Defines
# the variable lists and functions below; sourcing it runs nothing. Messages
# go to stderr and name variables or paths, never a value: the passwords are
# in the same environment.

# The release key (android/app/build.gradle reads the same four).
release_env_signing_vars=(
  HERBIER_RELEASE_KEYSTORE
  HERBIER_RELEASE_KEYSTORE_PASSWORD
  HERBIER_RELEASE_KEY_ALIAS
  HERBIER_RELEASE_KEY_PASSWORD
)
# The one-time key rotation from the previous (debug) key: release.sh
# re-signs the release APK with this lineage (architecture §4).
release_env_rotation_vars=(
  HERBIER_SIGNING_LINEAGE
  HERBIER_PREVIOUS_KEYSTORE
  HERBIER_PREVIOUS_KEY_ALIAS
  HERBIER_PREVIOUS_KEYSTORE_PASSWORD
  HERBIER_PREVIOUS_KEY_PASSWORD
)

# release_env_load <root>: exports what <root>/.env.prod sets, over the
# environment; without the file the environment alone is used (CI).
release_env_load() {
  if [ -f "$1/.env.prod" ]; then
    set -a
    # shellcheck disable=SC1091
    . "$1/.env.prod"
    set +a
  fi
  return 0
}

# release_env_placeholder <name>: succeeds when the value is still one of
# .env.prod.example's placeholders: a password is one when it is a whole
# `<...>` (a real one may contain `<`), any other value when it has a `<`.
release_env_placeholder() {
  case "$1" in
    *_PASSWORD) [[ "${!1}" == "<"*">" ]] ;;
    *) [[ "${!1}" == *"<"* ]] ;;
  esac
}

# release_env_require <name>…: one line per name that is empty or still a
# <placeholder>; returns 1 when any was.
release_env_require() {
  local name failed=0
  for name in "$@"; do
    if [ -z "${!name:-}" ]; then
      echo "release.sh: $name is not set (in .env.prod or the environment)" >&2
      failed=1
    elif release_env_placeholder "$name"; then
      echo "release.sh: $name still has a <placeholder> from .env.prod.example" >&2
      failed=1
    fi
  done
  return "$failed"
}

# release_env_count_set <name>…: prints how many of the names are non-empty.
release_env_count_set() {
  local name n=0
  for name in "$@"; do
    [ -n "${!name:-}" ] && n=$((n + 1))
  done
  echo "$n"
}

# release_env_file <name> <root>: makes the path in <name> absolute (~/ is
# $HOME, a relative path is under <root>), exports it, and checks the file
# exists and is not empty (an unset CI secret decodes to an empty keystore).
release_env_file() {
  local name=$1 root=$2 path=${!1}
  case "$path" in
    "~/"*) path="$HOME/${path#"~/"}" ;;
    /*) ;;
    *) path="$root/$path" ;;
  esac
  export "$name=$path"
  if [ ! -f "$path" ]; then
    echo "release.sh: $name: no such file: $path" >&2
    return 1
  elif [ ! -s "$path" ]; then
    echo "release.sh: $name: empty file: $path" >&2
    return 1
  fi
}

# Every backend value the APK needs to sign in (Auth.create sees "" and says
# so in 4m otherwise).
release_env_check_backend() {
  release_env_require HERBIER_SUPABASE_URL HERBIER_SUPABASE_PUBLISHABLE_KEY \
    HERBIER_GOOGLE_WEB_CLIENT_ID
}

# release_env_check_signing <release|debug> <root>: a release needs the
# release key; a debug build takes it entirely or not at all (then Gradle
# signs with the default debug key). The rotation is release-only, all or
# none. Returns 2 on an unknown mode.
release_env_check_signing() {
  local mode=$1 root=$2 failed=0 name
  case "$mode" in
    release) ;;
    debug)
      if [ "$(release_env_count_set "${release_env_signing_vars[@]}")" = 0 ]; then
        echo "release.sh: no release key set: the debug APK is signed with the debug key" >&2
        return 0
      fi
      ;;
    *)
      echo "release.sh: unknown mode $mode" >&2
      return 2
      ;;
  esac
  release_env_require "${release_env_signing_vars[@]}" || return 1
  release_env_file HERBIER_RELEASE_KEYSTORE "$root" || return 1
  [ "$mode" = release ] || return 0
  if [ "$(release_env_count_set "${release_env_rotation_vars[@]}")" = 0 ]; then
    return 0
  fi
  release_env_require "${release_env_rotation_vars[@]}" || return 1
  for name in HERBIER_SIGNING_LINEAGE HERBIER_PREVIOUS_KEYSTORE; do
    release_env_file "$name" "$root" || failed=1
  done
  return "$failed"
}

# Succeeds when every rotation variable is set.
release_env_rotation_enabled() {
  [ "$(release_env_count_set "${release_env_rotation_vars[@]}")" = \
    "${#release_env_rotation_vars[@]}" ]
}
