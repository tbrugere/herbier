Native cram test of scripts/lib/release-env.sh and of scripts/release.sh's
checks before the build, copied next to this file by the dune rules. Every
case runs in a scrubbed environment (`env -i HOME=... PATH=... bash -c
'...'`), so nothing from the developer's shell or a real `.env.prod` leaks
in; `$0` inside the sub-shell is the sourced script, `$1`/`$2`… are the
root or extra values the outer line passes. Passwords are given "SECRET"
values in the cases whose output is logged to secrets.log; the last case
checks that none of it leaked.

  $ SCRIPT="$PWD/release-env.sh"

1. Sourcing alone prints nothing, is rc=0, and defines the four functions
release.sh calls (`type -t` -> `function`).

  $ env -i HOME="$PWD" PATH="$PATH" bash -c '
  > . "$0"
  > echo "source-rc=$?"
  > for f in release_env_load release_env_check_backend \
  >          release_env_check_signing release_env_rotation_enabled; do
  >   printf "%s=%s\n" "$f" "$(type -t "$f")"
  > done
  > ' "$SCRIPT"
  source-rc=0
  release_env_load=function
  release_env_check_backend=function
  release_env_check_signing=function
  release_env_rotation_enabled=function

2. `release_env_load` with no `.env.prod`: rc=0, a variable already in the
environment is unchanged.

  $ mkdir root2
  $ env -i HOME="$PWD" PATH="$PATH" HERBIER_SUPABASE_URL=preset bash -c '
  > . "$0"
  > release_env_load "$1"
  > echo "rc=$?"
  > echo "url=$HERBIER_SUPABASE_URL"
  > ' "$SCRIPT" "$PWD/root2"
  rc=0
  url=preset

3. `release_env_load` with a `.env.prod` setting the three backend values:
all three are exported, visible to a child process.

  $ mkdir root3
  $ cat > root3/.env.prod <<'ENVPROD'
  > HERBIER_SUPABASE_URL=https://test.example.supabase.co
  > HERBIER_SUPABASE_PUBLISHABLE_KEY=sb_publishable_test123
  > HERBIER_GOOGLE_WEB_CLIENT_ID=123-test.apps.googleusercontent.com
  > ENVPROD
  $ env -i HOME="$PWD" PATH="$PATH" bash -c '
  > . "$0"
  > release_env_load "$1"
  > echo "rc=$?"
  > sh -c "echo \$HERBIER_SUPABASE_URL; echo \$HERBIER_SUPABASE_PUBLISHABLE_KEY; echo \$HERBIER_GOOGLE_WEB_CLIENT_ID"
  > ' "$SCRIPT" "$PWD/root3"
  rc=0
  https://test.example.supabase.co
  sb_publishable_test123
  123-test.apps.googleusercontent.com

4. A `.env.prod` value overrides an environment value of the same name.

  $ env -i HOME="$PWD" PATH="$PATH" HERBIER_SUPABASE_URL=preset bash -c '
  > . "$0"
  > release_env_load "$1"
  > echo "$HERBIER_SUPABASE_URL"
  > ' "$SCRIPT" "$PWD/root3"
  https://test.example.supabase.co

5. `check_backend` with all three set: rc=0, no output.

  $ env -i HOME="$PWD" PATH="$PATH" \
  >   HERBIER_SUPABASE_URL=a HERBIER_SUPABASE_PUBLISHABLE_KEY=b \
  >   HERBIER_GOOGLE_WEB_CLIENT_ID=c bash -c '
  > . "$0"
  > release_env_check_backend
  > echo "rc=$?"
  > ' "$SCRIPT"
  rc=0

6. `check_backend` with none set: three "is not set" lines, in the order
URL, key, client id; rc=1.

  $ env -i HOME="$PWD" PATH="$PATH" bash -c '
  > . "$0"
  > release_env_check_backend
  > echo "rc=$?"
  > ' "$SCRIPT"
  release.sh: HERBIER_SUPABASE_URL is not set (in .env.prod or the environment)
  release.sh: HERBIER_SUPABASE_PUBLISHABLE_KEY is not set (in .env.prod or the environment)
  release.sh: HERBIER_GOOGLE_WEB_CLIENT_ID is not set (in .env.prod or the environment)
  rc=1

7. `check_backend` with the example's placeholders: one "<placeholder>"
line per placeholder value; rc=1.

  $ env -i HOME="$PWD" PATH="$PATH" \
  >   HERBIER_SUPABASE_URL='https://<project-ref>.supabase.co' \
  >   HERBIER_SUPABASE_PUBLISHABLE_KEY='sb_publishable_<key>' \
  >   HERBIER_GOOGLE_WEB_CLIENT_ID='<number>-<id>.apps.googleusercontent.com' \
  >   bash -c '
  > . "$0"
  > release_env_check_backend
  > echo "rc=$?"
  > ' "$SCRIPT"
  release.sh: HERBIER_SUPABASE_URL still has a <placeholder> from .env.prod.example
  release.sh: HERBIER_SUPABASE_PUBLISHABLE_KEY still has a <placeholder> from .env.prod.example
  release.sh: HERBIER_GOOGLE_WEB_CLIENT_ID still has a <placeholder> from .env.prod.example
  rc=1

8. `check_signing release` with nothing set: four "is not set" lines; rc=1.

  $ env -i HOME="$PWD" PATH="$PATH" bash -c '
  > . "$0"
  > release_env_check_signing release "$1"
  > echo "rc=$?"
  > ' "$SCRIPT" "$PWD"
  release.sh: HERBIER_RELEASE_KEYSTORE is not set (in .env.prod or the environment)
  release.sh: HERBIER_RELEASE_KEYSTORE_PASSWORD is not set (in .env.prod or the environment)
  release.sh: HERBIER_RELEASE_KEY_ALIAS is not set (in .env.prod or the environment)
  release.sh: HERBIER_RELEASE_KEY_PASSWORD is not set (in .env.prod or the environment)
  rc=1

9. `check_signing release` with all four set and an existing keystore file
given relatively (`keys/r.jks`): rc=0, and `$HERBIER_RELEASE_KEYSTORE` is
now absolute (`$ROOT/keys/r.jks`). Passwords carry a "SECRET" marker,
checked in the last case.

  $ mkdir -p root9/keys && echo key > root9/keys/r.jks
  $ out9=$(env -i HOME="$PWD" PATH="$PATH" \
  >   HERBIER_RELEASE_KEYSTORE=keys/r.jks \
  >   HERBIER_RELEASE_KEYSTORE_PASSWORD=pw-SECRET-KS \
  >   HERBIER_RELEASE_KEY_ALIAS=herbier \
  >   HERBIER_RELEASE_KEY_PASSWORD=pw-SECRET-KEY bash -c '
  > . "$0"
  > release_env_check_signing release "$1"
  > echo "rc=$?"
  > [ "$HERBIER_RELEASE_KEYSTORE" = "$1/keys/r.jks" ] \
  >   && echo absolute-ok || echo absolute-fail
  > ' "$SCRIPT" "$PWD/root9" 2>&1)
  $ printf '%s\n' "$out9" | tee -a secrets.log
  rc=0
  absolute-ok

10. Same with `~/r.jks` (`HOME` = root10, not the release root): expanded
to `$HOME/r.jks`.

  $ mkdir root10 && echo key > root10/r.jks
  $ env -i HOME="$PWD/root10" PATH="$PATH" \
  >   HERBIER_RELEASE_KEYSTORE='~/r.jks' \
  >   HERBIER_RELEASE_KEYSTORE_PASSWORD=x \
  >   HERBIER_RELEASE_KEY_ALIAS=herbier \
  >   HERBIER_RELEASE_KEY_PASSWORD=x bash -c '
  > . "$0"
  > release_env_check_signing release "$1"
  > echo "rc=$?"
  > [ "$HERBIER_RELEASE_KEYSTORE" = "$HOME/r.jks" ] \
  >   && echo home-ok || echo home-fail
  > ' "$SCRIPT" "$PWD"
  rc=0
  home-ok

11. Keystore path to a missing file: the "no such file" line with the
absolute path; rc=1.

  $ mkdir root11
  $ out11=$(env -i HOME="$PWD" PATH="$PATH" \
  >   HERBIER_RELEASE_KEYSTORE=keys/missing.jks \
  >   HERBIER_RELEASE_KEYSTORE_PASSWORD=pw-SECRET-KS \
  >   HERBIER_RELEASE_KEY_ALIAS=herbier \
  >   HERBIER_RELEASE_KEY_PASSWORD=pw-SECRET-KEY bash -c '
  > . "$0"
  > release_env_check_signing release "$1"
  > echo "rc=$?"
  > ' "$SCRIPT" "$PWD/root11" 2>&1)
  $ printf '%s\n' "$out11" | tee -a secrets.log
  release.sh: HERBIER_RELEASE_KEYSTORE: no such file: $TESTCASE_ROOT/root11/keys/missing.jks
  rc=1

12. `check_signing debug` with nothing set: the single note line; rc=0.

  $ env -i HOME="$PWD" PATH="$PATH" bash -c '
  > . "$0"
  > release_env_check_signing debug "$1"
  > echo "rc=$?"
  > ' "$SCRIPT" "$PWD"
  release.sh: no release key set: the debug APK is signed with the debug key
  rc=0

13. `check_signing debug` with only `HERBIER_RELEASE_KEYSTORE` set: three
"is not set" lines (the other release-key variables); rc=1.

  $ out13=$(env -i HOME="$PWD" PATH="$PATH" \
  >   HERBIER_RELEASE_KEYSTORE=dummy.jks bash -c '
  > . "$0"
  > release_env_check_signing debug "$1"
  > echo "rc=$?"
  > ' "$SCRIPT" "$PWD" 2>&1)
  $ printf '%s\n' "$out13" | tee -a secrets.log
  release.sh: HERBIER_RELEASE_KEYSTORE_PASSWORD is not set (in .env.prod or the environment)
  release.sh: HERBIER_RELEASE_KEY_ALIAS is not set (in .env.prod or the environment)
  release.sh: HERBIER_RELEASE_KEY_PASSWORD is not set (in .env.prod or the environment)
  rc=1

14. `check_signing release` with the release key complete and the rotation
variables partial (lineage only): four "is not set" lines for the other
rotation variables; rc=1.

  $ mkdir -p root14/keys && echo key > root14/keys/r.jks
  $ out14=$(env -i HOME="$PWD" PATH="$PATH" \
  >   HERBIER_RELEASE_KEYSTORE=keys/r.jks \
  >   HERBIER_RELEASE_KEYSTORE_PASSWORD=pw-SECRET-KS \
  >   HERBIER_RELEASE_KEY_ALIAS=herbier \
  >   HERBIER_RELEASE_KEY_PASSWORD=pw-SECRET-KEY \
  >   HERBIER_SIGNING_LINEAGE=keys/lineage bash -c '
  > . "$0"
  > release_env_check_signing release "$1"
  > echo "rc=$?"
  > ' "$SCRIPT" "$PWD/root14" 2>&1)
  $ printf '%s\n' "$out14" | tee -a secrets.log
  release.sh: HERBIER_PREVIOUS_KEYSTORE is not set (in .env.prod or the environment)
  release.sh: HERBIER_PREVIOUS_KEY_ALIAS is not set (in .env.prod or the environment)
  release.sh: HERBIER_PREVIOUS_KEYSTORE_PASSWORD is not set (in .env.prod or the environment)
  release.sh: HERBIER_PREVIOUS_KEY_PASSWORD is not set (in .env.prod or the environment)
  rc=1

15. Release key and rotation variables complete, files present: rc=0;
`release_env_rotation_enabled` rc=0; with the rotation variables unset,
rc=1.

  $ mkdir -p root15/keys
  $ for f in r.jks lineage previous.jks; do echo key > root15/keys/$f; done
  $ out15=$(env -i HOME="$PWD" PATH="$PATH" \
  >   HERBIER_RELEASE_KEYSTORE=keys/r.jks \
  >   HERBIER_RELEASE_KEYSTORE_PASSWORD=pw-SECRET-KS \
  >   HERBIER_RELEASE_KEY_ALIAS=herbier \
  >   HERBIER_RELEASE_KEY_PASSWORD=pw-SECRET-KEY \
  >   HERBIER_SIGNING_LINEAGE=keys/lineage \
  >   HERBIER_PREVIOUS_KEYSTORE=keys/previous.jks \
  >   HERBIER_PREVIOUS_KEY_ALIAS=olddebug \
  >   HERBIER_PREVIOUS_KEYSTORE_PASSWORD=pw-SECRET-PREV-KS \
  >   HERBIER_PREVIOUS_KEY_PASSWORD=pw-SECRET-PREV-KEY bash -c '
  > . "$0"
  > release_env_check_signing release "$1"
  > echo "check-rc=$?"
  > release_env_rotation_enabled
  > echo "rotation-rc=$?"
  > unset HERBIER_SIGNING_LINEAGE HERBIER_PREVIOUS_KEYSTORE \
  >   HERBIER_PREVIOUS_KEY_ALIAS HERBIER_PREVIOUS_KEYSTORE_PASSWORD \
  >   HERBIER_PREVIOUS_KEY_PASSWORD
  > release_env_rotation_enabled
  > echo "rotation-unset-rc=$?"
  > ' "$SCRIPT" "$PWD/root15" 2>&1)
  $ printf '%s\n' "$out15" | tee -a secrets.log
  check-rc=0
  rotation-rc=0
  rotation-unset-rc=1

16. `check_signing debug` with the release key complete and the rotation
variables partial: rc=0 (a debug build ignores the rotation).

  $ mkdir -p root16/keys && echo key > root16/keys/r.jks
  $ env -i HOME="$PWD" PATH="$PATH" \
  >   HERBIER_RELEASE_KEYSTORE=keys/r.jks \
  >   HERBIER_RELEASE_KEYSTORE_PASSWORD=x \
  >   HERBIER_RELEASE_KEY_ALIAS=herbier \
  >   HERBIER_RELEASE_KEY_PASSWORD=x \
  >   HERBIER_SIGNING_LINEAGE=keys/lineage bash -c '
  > . "$0"
  > release_env_check_signing debug "$1"
  > echo "rc=$?"
  > ' "$SCRIPT" "$PWD/root16"
  rc=0

17. `check_signing nonsense ...`: "unknown mode" line; rc=2.

  $ env -i HOME="$PWD" PATH="$PATH" bash -c '
  > . "$0"
  > release_env_check_signing nonsense "$1"
  > echo "rc=$?"
  > ' "$SCRIPT" "$PWD"
  release.sh: unknown mode nonsense
  rc=2

17a. `check_signing release` with placeholder-shaped release values: one
"<placeholder>" line per variable, no value printed; rc=1.

  $ out17a=$(env -i HOME="$PWD" PATH="$PATH" \
  >   HERBIER_RELEASE_KEYSTORE='<path/to/herbier-release.jks>' \
  >   HERBIER_RELEASE_KEYSTORE_PASSWORD='<SECRET store password>' \
  >   HERBIER_RELEASE_KEY_ALIAS='<alias>' \
  >   HERBIER_RELEASE_KEY_PASSWORD='<SECRET key password>' bash -c '
  > . "$0"
  > release_env_check_signing release "$1"
  > echo "rc=$?"
  > ' "$SCRIPT" "$PWD" 2>&1)
  $ printf '%s\n' "$out17a" | tee -a secrets.log
  release.sh: HERBIER_RELEASE_KEYSTORE still has a <placeholder> from .env.prod.example
  release.sh: HERBIER_RELEASE_KEYSTORE_PASSWORD still has a <placeholder> from .env.prod.example
  release.sh: HERBIER_RELEASE_KEY_ALIAS still has a <placeholder> from .env.prod.example
  release.sh: HERBIER_RELEASE_KEY_PASSWORD still has a <placeholder> from .env.prod.example
  rc=1

17b. Release key and rotation variables complete but the lineage and
previous keystore files missing: one "no such file" line each, with the
absolute path (an absolute path is kept as given); rc=1.

  $ mkdir -p root17b/keys && echo key > root17b/keys/r.jks
  $ out17b=$(env -i HOME="$PWD" PATH="$PATH" \
  >   HERBIER_RELEASE_KEYSTORE=keys/r.jks \
  >   HERBIER_RELEASE_KEYSTORE_PASSWORD=pw-SECRET-KS \
  >   HERBIER_RELEASE_KEY_ALIAS=herbier \
  >   HERBIER_RELEASE_KEY_PASSWORD=pw-SECRET-KEY \
  >   HERBIER_SIGNING_LINEAGE=keys/lineage \
  >   HERBIER_PREVIOUS_KEYSTORE="$PWD/root17b/previous.jks" \
  >   HERBIER_PREVIOUS_KEY_ALIAS=olddebug \
  >   HERBIER_PREVIOUS_KEYSTORE_PASSWORD=pw-SECRET-PREV-KS \
  >   HERBIER_PREVIOUS_KEY_PASSWORD=pw-SECRET-PREV-KEY bash -c '
  > . "$0"
  > release_env_check_signing release "$1"
  > echo "rc=$?"
  > ' "$SCRIPT" "$PWD/root17b" 2>&1)
  $ printf '%s\n' "$out17b" | tee -a secrets.log
  release.sh: HERBIER_SIGNING_LINEAGE: no such file: $TESTCASE_ROOT/root17b/keys/lineage
  release.sh: HERBIER_PREVIOUS_KEYSTORE: no such file: $TESTCASE_ROOT/root17b/previous.jks
  rc=1

17c. `.env.prod.example` copied as is: the three backend and the four
release-key values are placeholders, the rotation is off; both checks rc=1.

  $ mkdir root17c && cp env.prod.example root17c/.env.prod
  $ env -i HOME="$PWD" PATH="$PATH" bash -c '
  > . "$0"
  > release_env_load "$1"
  > release_env_check_backend; echo "backend-rc=$?"
  > release_env_check_signing release "$1"; echo "signing-rc=$?"
  > release_env_rotation_enabled; echo "rotation-rc=$?"
  > ' "$SCRIPT" "$PWD/root17c"
  release.sh: HERBIER_SUPABASE_URL still has a <placeholder> from .env.prod.example
  release.sh: HERBIER_SUPABASE_PUBLISHABLE_KEY still has a <placeholder> from .env.prod.example
  release.sh: HERBIER_GOOGLE_WEB_CLIENT_ID still has a <placeholder> from .env.prod.example
  backend-rc=1
  release.sh: HERBIER_RELEASE_KEYSTORE still has a <placeholder> from .env.prod.example
  release.sh: HERBIER_RELEASE_KEYSTORE_PASSWORD still has a <placeholder> from .env.prod.example
  release.sh: HERBIER_RELEASE_KEY_ALIAS still has a <placeholder> from .env.prod.example
  release.sh: HERBIER_RELEASE_KEY_PASSWORD still has a <placeholder> from .env.prod.example
  signing-rc=1
  rotation-rc=1

17d. Real passwords containing `<` (not a whole `<...>`) pass: rc=0.

  $ mkdir -p root17d/keys && echo key > root17d/keys/r.jks
  $ out17d=$(env -i HOME="$PWD" PATH="$PATH" \
  >   HERBIER_RELEASE_KEYSTORE=keys/r.jks \
  >   HERBIER_RELEASE_KEYSTORE_PASSWORD='a<SECRET9x' \
  >   HERBIER_RELEASE_KEY_ALIAS=herbier \
  >   HERBIER_RELEASE_KEY_PASSWORD='x<SECRET>z' bash -c '
  > . "$0"
  > release_env_check_signing release "$1"
  > echo "rc=$?"
  > ' "$SCRIPT" "$PWD/root17d" 2>&1)
  $ printf '%s\n' "$out17d" | tee -a secrets.log
  rc=0

17e. An empty keystore file (what an unset CI secret decodes to): the
"empty file" line; rc=1.

  $ mkdir -p root17e/keys && touch root17e/keys/r.jks
  $ out17e=$(env -i HOME="$PWD" PATH="$PATH" \
  >   HERBIER_RELEASE_KEYSTORE=keys/r.jks \
  >   HERBIER_RELEASE_KEYSTORE_PASSWORD=pw-SECRET-KS \
  >   HERBIER_RELEASE_KEY_ALIAS=herbier \
  >   HERBIER_RELEASE_KEY_PASSWORD=pw-SECRET-KEY bash -c '
  > . "$0"
  > release_env_check_signing release "$1"
  > echo "rc=$?"
  > ' "$SCRIPT" "$PWD/root17e" 2>&1)
  $ printf '%s\n' "$out17e" | tee -a secrets.log
  release.sh: HERBIER_RELEASE_KEYSTORE: empty file: $TESTCASE_ROOT/root17e/keys/r.jks
  rc=1

17f. release.sh itself, in a checkout of its own (it finds the root with
git): an unknown argument is a usage error, rc=2; with nothing set it
reports the backend and the release-key values together, then stops
before building, rc=1.

  $ mkdir -p rel/scripts/lib && git init -q rel
  $ cp release.sh rel/scripts/ && cp release-env.sh rel/scripts/lib/
  $ env -i HOME="$PWD" PATH="$PATH" bash rel/scripts/release.sh --bogus
  usage: rel/scripts/release.sh [--debug]
  [2]
  $ env -i HOME="$PWD" PATH="$PATH" bash rel/scripts/release.sh
  release.sh: HERBIER_SUPABASE_URL is not set (in .env.prod or the environment)
  release.sh: HERBIER_SUPABASE_PUBLISHABLE_KEY is not set (in .env.prod or the environment)
  release.sh: HERBIER_GOOGLE_WEB_CLIENT_ID is not set (in .env.prod or the environment)
  release.sh: Drive folder picker disabled (HERBIER_GOOGLE_CLOUD_PROJECT_NUMBER unset)
  release.sh: HERBIER_RELEASE_KEYSTORE is not set (in .env.prod or the environment)
  release.sh: HERBIER_RELEASE_KEYSTORE_PASSWORD is not set (in .env.prod or the environment)
  release.sh: HERBIER_RELEASE_KEY_ALIAS is not set (in .env.prod or the environment)
  release.sh: HERBIER_RELEASE_KEY_PASSWORD is not set (in .env.prod or the environment)
  [1]

17g. `release_env_check_picker`: the Cloud project number is optional
(unset: one line, rc=0), digits pass silently, a placeholder or a non-digit
value is refused, rc=1.

  $ for v in "" 123456789012 "<number>" 12a4; do
  > env -i HOME="$PWD" PATH="$PATH" HERBIER_GOOGLE_CLOUD_PROJECT_NUMBER="$v" bash -c '
  > . "$0"
  > release_env_check_picker; echo "rc=$?"
  > ' "$SCRIPT"
  > done
  release.sh: Drive folder picker disabled (HERBIER_GOOGLE_CLOUD_PROJECT_NUMBER unset)
  rc=0
  rc=0
  release.sh: HERBIER_GOOGLE_CLOUD_PROJECT_NUMBER still has a <placeholder> from .env.prod.example
  rc=1
  release.sh: HERBIER_GOOGLE_CLOUD_PROJECT_NUMBER must be digits only
  rc=1

18. Secret hygiene: the cases logged to secrets.log above used passwords
containing "SECRET"; none of their combined stdout+stderr does.

  $ n=$(grep -c SECRET secrets.log || true)
  $ echo "secret-lines=$n"
  secret-lines=0
