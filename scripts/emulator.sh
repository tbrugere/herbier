#!/usr/bin/env bash
# Android emulator and WebView devtools for device checks (dev pages such as
# #dev/storage) without a phone.
#
#   scripts/emulator.sh start            create the AVD if missing, boot it headless, wait for boot
#   scripts/emulator.sh stop             remove the devtools forward, kill the emulator
#   scripts/emulator.sh install          dune build @web, cap sync, assembleDebug, adb install
#   scripts/emulator.sh launch           start the app, or bring it to the front
#   scripts/emulator.sh kill-app         force-stop the app
#   scripts/emulator.sh forward          forward the app's WebView devtools socket, print the port
#   scripts/emulator.sh open [fragment]  launch, forward, reload the page at #<fragment> (none: no
#                                        fragment), wait until it is done (dev/* pages: a
#                                        "done" or "done: <summary>" line; others: text
#                                        unchanged for 2 s), print it
#   scripts/emulator.sh webview <cmd>... run scripts/webview.mjs on the forwarded port
#   scripts/emulator.sh env              print the exports this script uses (eval "$(… env)")
#
# install builds the checkout of the current directory (HERBIER_REPO overrides),
# so the script can drive a build of another worktree.
#
# Environment (defaults): ANDROID_HOME (~/Library/Android/sdk), JAVA_HOME
# (java_home -v 21), HERBIER_AVD (herbier), HERBIER_AVD_IMAGE
# (system-images;android-35;google_apis;arm64-v8a), HERBIER_AVD_DEVICE
# (pixel_8), HERBIER_DEVTOOLS_PORT (9222), HERBIER_EMULATOR_LOG
# ($TMPDIR/herbier-emulator.log).
set -euo pipefail

unset CDPATH
here="$(cd "$(dirname "$0")" && pwd)"
# A NODE_OPTIONS preload set by a terminal wrapper breaks node, hence esbuild
# under dune, npx cap and webview.mjs, as soon as its file is gone.
unset NODE_OPTIONS
export ANDROID_HOME="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
export ANDROID_SDK_ROOT="$ANDROID_HOME"
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

die() { echo "emulator.sh: $*" >&2; exit 1; }

repo() {
  local dir="${HERBIER_REPO:-$PWD}"
  git -C "$dir" rev-parse --show-toplevel 2>/dev/null || git -C "$here" rev-parse --show-toplevel
}

app_id() {
  sed -n "s/^[[:space:]]*appId:[[:space:]]*'\([^']*\)'.*/\1/p" "$(repo)/capacitor.config.ts" | head -n 1
}

serial() {
  adb devices | awk '/^emulator-[0-9]+[[:space:]]+device$/ {print $1; exit}'
}

booted() {
  local s
  s="$(serial)"
  [[ -n "$s" ]] && [[ "$(adb -s "$s" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" == 1 ]]
}

need() { command -v "$1" >/dev/null || die "$1 not found (is $2 installed under $ANDROID_HOME?)"; }

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
    echo "already running: $(serial)"
    return
  fi
  echo "booting $avd (log: $log)"
  nohup emulator -avd "$avd" -no-window -no-audio -no-boot-anim -no-snapshot-save \
    -gpu swiftshader_indirect >"$log" 2>&1 &
  adb wait-for-device
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

cmd_install() {
  local root
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
  adb -s "$(serial)" install -r "$root/android/app/build/outputs/apk/debug/app-debug.apk"
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

cmd_open() {
  local fragment="${1:-}"
  fragment="${fragment#\#}"
  [[ -n "$(app_pid)" ]] || { cmd_launch; sleep 2; }
  cmd_forward >/dev/null
  webview wait-for "document.readyState === 'complete'" 20000 >/dev/null
  local hash=""
  [[ -n "$fragment" ]] && hash="#$fragment"
  # The app reads the fragment once at startup, so set it and reload.
  webview eval "history.replaceState(null, '', location.pathname + location.search + '$hash'); location.reload(); true" >/dev/null
  sleep 1
  webview wait-for "document.readyState === 'complete' && location.hash === '$hash'" 20000 >/dev/null
  # Dev pages print a "done" line (or "done: <summary>") once every group
  # has settled, last in their log; an interactive page has its controls
  # below it. A slow step can leave the text unchanged for seconds before
  # that.
  if [[ "$fragment" == dev/* ]]; then
    webview wait-for "/^done(: .*)?\$/m.test(document.body.innerText)" 120000 >/dev/null \
      || { webview text; die "#$fragment did not print done within 2 min"; }
    webview text
  else
    webview wait-stable 2000 60000
  fi
}

cmd_env() {
  cat <<ENV
export ANDROID_HOME="$ANDROID_HOME"
export ANDROID_SDK_ROOT="$ANDROID_HOME"
export JAVA_HOME="${JAVA_HOME:-}"
export PATH="$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/emulator:$ANDROID_HOME/platform-tools:\$PATH"
ENV
}

case "${1:-}" in
  start) cmd_start ;;
  stop) cmd_stop ;;
  install) cmd_install ;;
  launch) cmd_launch ;;
  kill-app) cmd_kill_app ;;
  forward) cmd_forward ;;
  open) shift; cmd_open "$@" ;;
  webview) shift; webview "$@" ;;
  env) cmd_env ;;
  *) sed -n '2,/^set -euo/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; exit 2 ;;
esac
