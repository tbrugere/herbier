#!/usr/bin/env bash
# Android emulator and WebView devtools for device checks (dev pages such as
# #dev/storage) without a phone. One shared emulator (AVD herbier, console
# port 5554) for every agent and worktree; device checks take turns with
# lock and unlock.
#
#   scripts/emulator.sh lock [label]     wait until this caller holds the device lock (prints the
#                                        holder while waiting); held by the same label already:
#                                        re-enter it at once; idle for HERBIER_LOCK_IDLE (20 min,
#                                        no device subcommand or webview.mjs call): stale, taken
#                                        over with a warning
#   scripts/emulator.sh unlock <label>   release the lock, only if that label holds it
#   scripts/emulator.sh unlock --force   release the lock whoever holds it (humans only)
#   scripts/emulator.sh lock-status      print the holder, its age and idle time, or "free"
#   scripts/emulator.sh start            create the AVD if missing, boot it headless, wait for boot,
#                                        reverse tcp:54321 (the local Supabase stack, app/sync/dune)
#   scripts/emulator.sh stop             remove the devtools forward, kill the emulator
#   scripts/emulator.sh install          dune build @web, cap sync, assembleDebug, adb install
#   scripts/emulator.sh install-web      dune build @web, push the web bundle into the installed
#                                        debug app and serve it from there (no Gradle); falls back
#                                        to install when the APK is missing or its native inputs
#                                        (android/, package*.json, capacitor.config.ts) changed
#   scripts/emulator.sh launch           start the app, or bring it to the front
#   scripts/emulator.sh kill-app         force-stop the app
#   scripts/emulator.sh forward          forward the app's WebView devtools socket, print the port
#   scripts/emulator.sh open [fragment]  launch, forward, reload the page at #<fragment> (none: no
#                                        fragment), wait until it is done (dev/* check pages: a
#                                        "done" or "done: <summary>" line; others, and
#                                        dev/gallery, dev/collection, dev/link, dev/drive,
#                                        dev/uploader: text unchanged for 2 s), print it
#   scripts/emulator.sh webview <cmd>... run scripts/webview.mjs on the forwarded port
#   scripts/emulator.sh env              print the exports this script uses (eval "$(… env)")
#
# install and install-web build the checkout of the current directory
# (HERBIER_REPO overrides), so the script can drive a build of another worktree.
#
# Environment (defaults): ANDROID_HOME (~/Library/Android/sdk), JAVA_HOME
# (java_home -v 21), HERBIER_AVD (herbier), HERBIER_AVD_IMAGE
# (system-images;android-35;google_apis;arm64-v8a), HERBIER_AVD_DEVICE
# (pixel_8), HERBIER_DEVTOOLS_PORT (9222), HERBIER_EMULATOR_LOG
# ($TMPDIR/herbier-emulator.log), HERBIER_EMULATOR_PORT (5554),
# HERBIER_EMULATOR_GPU (host: the -gpu mode; see the skill), HERBIER_LOCK_DIR
# (~/.cache/herbier/emulator.lock), HERBIER_LOCK_TIMEOUT (0: wait forever;
# else seconds before lock gives up, exit 1), HERBIER_LOCK_IDLE (1200: seconds
# without activity after which a lock is stale), HERBIER_LOCK_POLL (5: seconds
# between two tries of a waiting lock).
#
# Each emulator costs about 5 GB of host memory: start refuses to boot while
# another emulator runs, unless HERBIER_ALLOW_SECOND_EMULATOR=1 (with its own
# HERBIER_AVD, HERBIER_EMULATOR_PORT and HERBIER_DEVTOOLS_PORT on every call).
set -euo pipefail

unset CDPATH
here="$(cd "$(dirname "$0")" && pwd)"
# A NODE_OPTIONS preload set by a terminal wrapper breaks node, hence esbuild
# under dune, npx cap and webview.mjs, as soon as its file is gone.
unset NODE_OPTIONS
export ANDROID_HOME="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
export ANDROID_SDK_ROOT="$ANDROID_HOME"
# avdmanager follows XDG_CONFIG_HOME (~/.config/.android/avd) when it is set,
# the emulator does not (~/.android/avd): pin one place for both, or a new
# AVD is "created" where the emulator never finds it ("Unknown AVD name").
export ANDROID_AVD_HOME="${ANDROID_AVD_HOME:-$HOME/.android/avd}"
if [[ -z "${JAVA_HOME:-}" ]] && [[ -x /usr/libexec/java_home ]]; then
  JAVA_HOME="$(/usr/libexec/java_home -v 21 2>/dev/null || true)"
  export JAVA_HOME
fi
# The SDK's own cmdline-tools first: Homebrew's avdmanager resolves system
# images against its own SDK root and fails with "Package path is not valid".
export PATH="$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/emulator:$ANDROID_HOME/platform-tools:$PATH"

avd="${HERBIER_AVD:-herbier}"
image="${HERBIER_AVD_IMAGE:-system-images;android-35;google_apis;arm64-v8a}"
device="${HERBIER_AVD_DEVICE:-pixel_8}"
port="${HERBIER_DEVTOOLS_PORT:-9222}"
log="${HERBIER_EMULATOR_LOG:-${TMPDIR:-/tmp}/herbier-emulator.log}"
console_port="${HERBIER_EMULATOR_PORT:-5554}"
gpu="${HERBIER_EMULATOR_GPU:-host}"
lock_dir="${HERBIER_LOCK_DIR:-$HOME/.cache/herbier/emulator.lock}"
lock_idle_s="${HERBIER_LOCK_IDLE:-1200}"

die() { echo "emulator.sh: $*" >&2; exit 1; }

repo() {
  local dir="${HERBIER_REPO:-$PWD}"
  git -C "$dir" rev-parse --show-toplevel 2>/dev/null || git -C "$here" rev-parse --show-toplevel
}

app_id() {
  sed -n "s/^[[:space:]]*appId:[[:space:]]*'\([^']*\)'.*/\1/p" "$(repo)/capacitor.config.ts" | head -n 1
}

serial() {
  adb devices | awk -v s="emulator-$console_port" '$1 == s && $2 == "device" {print $1; exit}'
}

# Emulators other than ours, as adb lists them.
other_emulators() {
  adb devices | awk -v s="emulator-$console_port" '$1 ~ /^emulator-/ && $1 != s {print $1}'
}

booted() {
  local s
  s="$(serial)"
  [[ -n "$s" ]] && [[ "$(adb -s "$s" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" == 1 ]]
}

need() { command -v "$1" >/dev/null || die "$1 not found (is $2 installed under $ANDROID_HOME?)"; }

# The app's dev builds sign in against the local stack at 127.0.0.1:54321.
# A reverse mapping does not survive an emulator restart: set on every start.
reverse_supabase() {
  adb -s "$1" reverse tcp:54321 tcp:54321 >/dev/null 2>&1 || true
}

cmd_start() {
  need emulator emulator
  need adb platform-tools
  if ! emulator -list-avds | grep -qx "$avd"; then
    need avdmanager "cmdline-tools;latest"
    [[ -d "$ANDROID_HOME/${image//;//}" ]] || die "system image $image missing: sdkmanager '$image'"
    echo "creating AVD $avd ($image, $device)"
    echo no | avdmanager create avd -n "$avd" -k "$image" -d "$device" >/dev/null
  fi
  if booted; then
    reverse_supabase "$(serial)"
    echo "already running: $(serial)"
    return
  fi
  local others
  others="$(other_emulators | tr '\n' ' ')"
  if [[ -n "$others" ]] && [[ "${HERBIER_ALLOW_SECOND_EMULATOR:-}" != 1 ]]; then
    die "another emulator is running (${others% }): one shared emulator, \
emulator-$console_port; stop the other, or set HERBIER_ALLOW_SECOND_EMULATOR=1"
  fi
  echo "booting $avd on emulator-$console_port, -gpu $gpu (log: $log)"
  nohup emulator -avd "$avd" -port "$console_port" -no-window -no-audio \
    -no-boot-anim -no-snapshot-save -gpu "$gpu" >"$log" 2>&1 &
  adb -s "emulator-$console_port" wait-for-device
  local i
  for i in $(seq 1 180); do
    booted && break
    sleep 2
  done
  booted || die "no sys.boot_completed after 6 min; see $log"
  local s
  s="$(serial)"
  adb -s "$s" shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
  adb -s "$s" shell wm dismiss-keyguard >/dev/null 2>&1 || true
  reverse_supabase "$s"
  echo "booted: $s"
}

cmd_stop() {
  adb forward --remove "tcp:$port" >/dev/null 2>&1 || true
  local s
  s="$(serial)"
  if [[ -z "$s" ]]; then
    echo "no emulator running"
    return
  fi
  adb -s "$s" emu kill >/dev/null
  local i
  for i in $(seq 1 30); do
    [[ -z "$(serial)" ]] && break
    sleep 1
  done
  echo "stopped $s"
}

# The native inputs of the APK: what install-web cannot ship. Files tracked
# or not ignored, by content, so an uncommitted edit counts.
native_hash() {
  local root
  root="$(repo)"
  (
    cd "$root"
    git ls-files -co --exclude-standard -z -- android package.json package-lock.json capacitor.config.ts \
      | sort -z | xargs -0 shasum | shasum | awk '{print $1}'
  )
}

# Where install-web keeps its state: the bundle pushed by adb (shell-owned,
# readable by the app's run-as user) and the native hash of the last install.
device_tmp() { echo "/data/local/tmp/herbier-web/$(app_id)"; }

# The app's own copy of the bundle, which its local server hosts. Relative to
# the app's data directory (run-as starts there).
WEB_DEV_DIR=files/herbier-web-dev

app_update_time() {
  adb -s "$(serial)" shell dumpsys package "$(app_id)" \
    | tr -d '\r' | sed -n 's/^ *lastUpdateTime=//p' | head -n 1
}

# "<native hash> <lastUpdateTime>" as left by the last install: the APK on
# the device is ours and was built from these native inputs.
install_stamp() { echo "$(native_hash) $(app_update_time)"; }

cmd_install() {
  local root s id
  root="$(repo)"
  booted || die "no booted emulator: scripts/emulator.sh start"
  echo "building $root ($(git -C "$root" rev-parse --short HEAD))"
  (
    cd "$root"
    if command -v opam >/dev/null; then eval "$(opam env 2>/dev/null)" || true; fi
    dune build @web
    npx cap sync android
    cd android && ./gradlew -q assembleDebug
  )
  s="$(serial)"
  id="$(app_id)"
  adb -s "$s" install -r "$root/android/app/build/outputs/apk/debug/app-debug.apk"
  # A reinstall keeps the version code, so Capacitor would keep serving a
  # bundle pushed by install-web: remove it, the APK's own assets win again.
  adb -s "$s" shell run-as "$id" rm -rf "$WEB_DEV_DIR"
  adb -s "$s" shell "mkdir -p $(device_tmp) && echo '$(install_stamp)' > $(device_tmp).stamp"
}

# The fast path for a web-only change: build the bundle, copy it into the
# app's files and point Capacitor's local server at it, with the WebView
# plugin's setServerBasePath and persistServerBasePath (Capacitor's own live
# update API). The origin stays https://localhost, so storage, the SQLite
# databases and the secure context are those of the installed app. The
# persisted path survives a kill or relaunch; the next install drops it.
cmd_install_web() {
  local root s id tmp stamp dir dist
  root="$(repo)"
  booted || die "no booted emulator: scripts/emulator.sh start"
  s="$(serial)"
  id="$(app_id)"
  tmp="$(device_tmp)"
  stamp="$(adb -s "$s" shell cat "$tmp.stamp" 2>/dev/null | tr -d '\r' || true)"
  if [[ -z "$(app_update_time)" ]]; then
    echo "install-web: $id not installed, full install"
    cmd_install
    return
  fi
  if [[ "$stamp" != "$(install_stamp)" ]]; then
    echo "install-web: APK not built by install from these native inputs, full install"
    cmd_install
    return
  fi
  echo "building $root ($(git -C "$root" rev-parse --short HEAD)), web only"
  (
    cd "$root"
    if command -v opam >/dev/null; then eval "$(opam env 2>/dev/null)" || true; fi
    dune build @web
  )
  dist="$root/_build/default/web/dist"
  adb -s "$s" shell "rm -rf $tmp && mkdir -p $tmp && chmod 755 $tmp"
  adb -s "$s" push -q "$dist/." "$tmp/" >/dev/null
  adb -s "$s" shell "chmod -R a+rX $tmp"
  # A fresh directory per push: the WebView never mixes two bundles.
  dir="$WEB_DEV_DIR/$(date +%s)"
  adb -s "$s" shell run-as "$id" sh -c "'rm -rf $WEB_DEV_DIR && mkdir -p $dir && cp -R $tmp/. $dir/'"
  local abs
  abs="$(adb -s "$s" shell run-as "$id" sh -c "'cd $dir && pwd'" | tr -d '\r')"
  [[ "$abs" == /* ]] || die "cannot resolve $dir in $id"
  if [[ -n "$(app_pid)" ]] && ! app_in_front; then cmd_kill_app; fi
  [[ -n "$(app_pid)" ]] || { cmd_launch; sleep 2; }
  cmd_forward >/dev/null
  webview wait-for "document.readyState === 'complete'" 20000 >/dev/null
  # Both calls queue on the plugin thread in this order, before the reload
  # setServerBasePath posts can tear down this page.
  webview eval "window.__herbierOpenPending = true; const w = Capacitor.Plugins.WebView; w.setServerBasePath({ path: '$abs' }); w.persistServerBasePath(); true" >/dev/null
  sleep 1
  webview wait-for "document.readyState === 'complete' && !window.__herbierOpenPending" 60000 >/dev/null
  [[ "$(webview eval "Capacitor.Plugins.WebView.getServerBasePath().then(r => r.path)")" == "$abs" ]] \
    || die "the app does not serve $abs"
  echo "serving $abs"
}

cmd_launch() {
  local id
  id="$(app_id)"
  local s activity
  s="$(serial)"
  activity="$(adb -s "$s" shell cmd package resolve-activity --brief -c android.intent.category.LAUNCHER "$id" \
    | tr -d '\r' | tail -n 1)"
  [[ "$activity" == */* ]] || die "$id has no launcher activity (installed? scripts/emulator.sh install)"
  adb -s "$s" shell am start -W -n "$activity" >/dev/null
}

app_in_front() {
  adb -s "$(serial)" shell dumpsys activity activities \
    | grep -m1 topResumedActivity | grep -q "$(app_id)/"
}

cmd_kill_app() {
  adb -s "$(serial)" shell am force-stop "$(app_id)"
}

app_pid() {
  adb -s "$(serial)" shell pidof "$(app_id)" 2>/dev/null | tr -d '\r' | awk '{print $1}'
}

# The WebView's devtools socket is @webview_devtools_remote_<pid>; it only
# exists once the WebView is created, a moment after the activity starts.
cmd_forward() {
  local s pid sock i
  s="$(serial)"
  [[ -n "$s" ]] || die "no emulator running"
  for i in $(seq 1 30); do
    pid="$(app_pid)"
    if [[ -n "$pid" ]] && adb -s "$s" shell cat /proc/net/unix | grep -q "@webview_devtools_remote_$pid\b"; then
      sock="webview_devtools_remote_$pid"
      break
    fi
    sleep 1
  done
  [[ -n "${sock:-}" ]] || die "no WebView devtools socket for $(app_id) (debug build running?)"
  adb -s "$s" forward "tcp:$port" "localabstract:$sock" >/dev/null
  for i in $(seq 1 20); do
    node "$here/webview.mjs" --port "$port" targets >/dev/null 2>&1 && break
    sleep 0.5
  done
  echo "$port"
}

webview() { node "$here/webview.mjs" --port "$port" "$@"; }

# Dev pages that show a screen rather than a check log, so print no "done".
INTERACTIVE_DEV_PAGES="dev/gallery dev/collection dev/sheet dev/photos dev/capture dev/link dev/auth dev/drive dev/uploader"

cmd_open() {
  local fragment="${1:-}"
  fragment="${fragment#\#}"
  # After back exits the app, its process can outlive the activity (no WebView
  # to drive) and die on the next launch: restart unless the app is in front.
  if [[ -n "$(app_pid)" ]] && ! app_in_front; then cmd_kill_app; fi
  [[ -n "$(app_pid)" ]] || { cmd_launch; sleep 2; }
  cmd_forward >/dev/null
  webview wait-for "document.readyState === 'complete'" 20000 >/dev/null
  local hash=""
  [[ -n "$fragment" ]] && hash="#$fragment"
  # Set the fragment and reload, for a clean state (binding baseline, no
  # SQLite connection left by the previous page). The marker tells the
  # reloaded page from the old one; the hash is not compared, since the app
  # may rewrite a non-canonical fragment ("" or an unknown route).
  webview eval "window.__herbierOpenPending = true; history.replaceState(null, '', location.pathname + location.search + '$hash'); location.reload(); true" >/dev/null
  sleep 1
  webview wait-for "document.readyState === 'complete' && !window.__herbierOpenPending" 20000 >/dev/null
  # Dev pages print a "done" line (or "done: <summary>") once every group
  # has settled, last in their log; an interactive page has its controls
  # below it. A slow step can leave the text unchanged for seconds before
  # that.
  # An unknown dev page is rewritten to a tab: wait for "done" only on a
  # dev page the app actually shows. The screen pages (a widget gallery, a
  # screen over the seeded db) have no end to report: they are waited on like
  # a tab, until their text stops changing.
  if [[ "$fragment" == dev/* ]] \
    && [[ " $INTERACTIVE_DEV_PAGES " != *" $fragment "* ]] \
    && [[ "$(webview eval "location.hash")" == "#$fragment" ]]; then
    webview wait-for "/^done(: .*)?\$/m.test(document.body.innerText)" 120000 >/dev/null \
      || { webview text; die "#$fragment did not print done within 2 min"; }
    webview text
  else
    webview wait-stable 2000 60000
  fi
}

# The device lock: an mkdir'd directory (atomic) holding who took it
# (label, pid, since) and its last activity (last). Agents call from a fresh
# shell each time, so the caller's PID is a hint for humans, not a liveness
# test: a lock is stale once nothing used the emulator for lock_idle_s.
# Every device subcommand and every webview.mjs call refreshes last.
lock_touch() {
  [[ -d "$lock_dir" ]] || return 0
  date +%s >"$lock_dir/last.$$" 2>/dev/null && mv -f "$lock_dir/last.$$" "$lock_dir/last" 2>/dev/null || true
}

# Seconds since the last activity (or since the lock was taken).
lock_idle() {
  local t
  t="$(cat "$lock_dir/last" 2>/dev/null || cat "$lock_dir/since" 2>/dev/null || true)"
  # A lock dir without its files is one being written: young.
  [[ "$t" =~ ^[0-9]+$ ]] || { echo 0; return; }
  echo $(( $(date +%s) - t ))
}

lock_info() {
  local label pid since now
  label="$(cat "$lock_dir/label" 2>/dev/null || echo '?')"
  pid="$(cat "$lock_dir/pid" 2>/dev/null || echo '?')"
  since="$(cat "$lock_dir/since" 2>/dev/null || echo 0)"
  now="$(date +%s)"
  echo "\"$label\" (pid $pid, since $(date -r "$since" '+%H:%M:%S' 2>/dev/null || echo '?'), age $(( now - since ))s, idle $(lock_idle)s)"
}

cmd_lock() {
  local label="${1:-${USER:-?}@$(hostname -s)}" timeout="${HERBIER_LOCK_TIMEOUT:-0}"
  local start next_report=0 waited=0
  start="$(date +%s)"
  mkdir -p "$(dirname "$lock_dir")"
  while ! mkdir "$lock_dir" 2>/dev/null; do
    # The retry of a killed run of the same step takes over its own lock.
    if [[ "$(cat "$lock_dir/label" 2>/dev/null)" == "$label" ]]; then
      lock_touch
      echo "locked: \"$label\" (re-entered, it already held the lock)"
      return
    fi
    if (( $(lock_idle) > lock_idle_s )); then
      # Rename first: of two callers taking over, one mv wins, so the other
      # cannot remove the lock the winner then makes.
      local old="$lock_dir.stale.$$"
      if mv "$lock_dir" "$old" 2>/dev/null; then
        echo "emulator.sh: warning: taking over a stale lock (idle > ${lock_idle_s}s): $(lock_dir="$old" lock_info)" >&2
        rm -rf "$old"
      fi
      continue
    fi
    waited=$(( $(date +%s) - start ))
    if (( waited >= next_report )); then
      echo "waiting for the device lock, held by $(lock_info)"
      next_report=$(( waited + 60 ))
    fi
    if (( timeout > 0 && waited >= timeout )); then
      die "device lock still held after ${timeout}s by $(lock_info)"
    fi
    sleep "${HERBIER_LOCK_POLL:-5}"
  done
  echo "$label" >"$lock_dir/label"
  echo "$PPID" >"$lock_dir/pid"
  date +%s >"$lock_dir/since"
  lock_touch
  echo "locked: \"$label\""
}

cmd_unlock() {
  local label="${1:-}"
  if [[ ! -d "$lock_dir" ]]; then
    echo "not locked"
    return
  fi
  if [[ -z "$label" ]]; then
    die "unlock needs the label the lock was taken with (held by $(lock_info)); a human clearing someone else's lock: unlock --force"
  fi
  if [[ "$label" != "--force" ]] && [[ "$(cat "$lock_dir/label" 2>/dev/null)" != "$label" ]]; then
    die "the lock is held by $(lock_info), not \"$label\""
  fi
  echo "unlocked $(lock_info)"
  rm -rf "$lock_dir"
}

cmd_lock_status() {
  if [[ -d "$lock_dir" ]]; then
    echo "held by $(lock_info); stale after ${lock_idle_s}s idle"
  else
    echo "free"
  fi
}

cmd_env() {
  cat <<ENV
export ANDROID_HOME="$ANDROID_HOME"
export ANDROID_SDK_ROOT="$ANDROID_HOME"
export ANDROID_AVD_HOME="$ANDROID_AVD_HOME"
export JAVA_HOME="${JAVA_HOME:-}"
export PATH="$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/emulator:$ANDROID_HOME/platform-tools:\$PATH"
ENV
  # Plain adb then targets this emulator too.
  echo "export ANDROID_SERIAL=emulator-$console_port"
}

# Using the device counts as activity on the lock: refresh it now and when
# the command ends (a long install or wait).
case "${1:-}" in
  start|stop|install|install-web|launch|kill-app|forward|open|webview)
    lock_touch; trap lock_touch EXIT ;;
esac

case "${1:-}" in
  start) cmd_start ;;
  stop) cmd_stop ;;
  install) cmd_install ;;
  install-web) cmd_install_web ;;
  launch) cmd_launch ;;
  kill-app) cmd_kill_app ;;
  forward) cmd_forward ;;
  open) shift; cmd_open "$@" ;;
  webview) shift; webview "$@" ;;
  env) cmd_env ;;
  lock) shift; cmd_lock "$@" ;;
  unlock) shift; cmd_unlock "$@" ;;
  lock-status) cmd_lock_status ;;
  *) sed -n '2,/^set -euo/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; exit 2 ;;
esac
