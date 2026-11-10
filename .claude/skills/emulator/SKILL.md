---
name: emulator
description: Run the app on a headless Android emulator and drive its WebView over the DevTools Protocol, with scripts/emulator.sh and scripts/webview.mjs. Use for the "Manual device checks" of a PR (dev pages such as #dev/storage, #dev/store, #dev/seed), to inspect a dev page's output, take a screenshot of the app, or evaluate JS in the running app when no phone is attached.
---

# Emulator and WebView devtools

Two scripts do the work; this skill is how to use them and what goes wrong.

- `scripts/emulator.sh` (bash): `start`, `stop`, `install`, `launch`,
  `kill-app`, `forward`, `open [fragment]`, `webview <cmd>…`, `env`.
  Run with no argument for the usage text.
- `scripts/webview.mjs` (Node 22+, no dependency): `targets`, `eval <js>`,
  `text`, `screenshot <file>`, `wait-for <js> [ms]`,
  `wait-stable [quiet-ms] [ms]`, on `--port` (default 9222).

## Running a PR's device checks

1. Read the checklist: `gh pr view N --comments` ("Manual device checks").
   A check belongs to the PR that introduced it; to attribute a failure,
   build that PR's head too (stacked PRs: a later PR can break an earlier
   check).
2. Check out the branch in a worktree that has `node_modules/`, clean. Never
   build in a checkout where the user may run `dune build --watch`.
3. From that checkout (install builds the current directory's repo;
   `HERBIER_REPO` overrides, so the scripts can come from another branch):
   ```sh
   scripts/emulator.sh start      # creates the AVD "herbier" if missing, boots headless
   scripts/emulator.sh install    # dune build @web, cap sync, assembleDebug, adb install -r
   scripts/emulator.sh open dev/storage      # prints the page text once it settles
   scripts/emulator.sh webview screenshot /path/in/scratchpad/storage.png
   ```
4. Lifecycle checks, with `eval "$(scripts/emulator.sh env)"` for adb on PATH:
   - reload: `open <fragment>` again (it reloads the page);
   - kill and relaunch: `scripts/emulator.sh kill-app`, then `open <fragment>`;
   - Home then reopen: `adb shell input keyevent KEYCODE_HOME`, then
     `scripts/emulator.sh launch` (resumes, does not reload), then
     `scripts/emulator.sh webview text`;
   - Android back: `adb shell input keyevent KEYCODE_BACK`; once back has
     exited the app, `open` restarts it (the process can outlive the
     activity); taps: `adb shell input tap X Y` in device pixels (CSS px ×
     `devicePixelRatio`, plus the status bar);
   - fresh install state: `adb shell pm clear re.bruge.herbier`;
   - app files: `adb shell run-as re.bruge.herbier ls databases`.
5. `scripts/emulator.sh stop` at the end (kills the emulator, removes the
   forward). The AVD stays for next time.

## Reading a dev page

Dev pages print one line per step: `<label>: ok`, `<label>: ok · <detail>`,
or `<label>: <error>`, where the error is the plugin's code and message
verbatim (`OS-PLUG-FILE-0008: …`) or `expected …, got …`. A group stops at
its first failure, so the groups after it in the same chain are absent from
the page, not passed: report them as not reached. `done` (or
`done: <summary>`, e.g. `done: 15 ok, 2 errors`) is printed when every group
has settled; `open dev/…` waits for it (2 min at most), other
fragments, and the screen pages `dev/gallery` and `dev/collection` (no
log, no `done`), wait until the text has not changed for 2 s.

The raw plugins are reachable from `webview eval` as `Capacitor.Plugins.*`
(for example `CapacitorSQLite`), which helps to probe a plugin's behaviour
without changing code. Use a throwaway database name and close it.

## Desktop browser

`webview.mjs` talks to any DevTools port. With no Google Chrome installed, the
Playwright headless shell works:
`~/Library/Caches/ms-playwright/chromium_headless_shell-*/chrome-headless-shell-mac-arm64/chrome-headless-shell --remote-debugging-port=9333 --user-data-dir=<scratch> 'http://127.0.0.1:8765/#dev/storage'`
with `python3 -m http.server 8765 -d _build/default/web/dist`, then
`node scripts/webview.mjs --port 9333 wait-stable`.

## Pitfalls

- SDK: `ANDROID_HOME` defaults to `~/Library/Android/sdk`. Homebrew's
  `avdmanager` resolves images against its own SDK root ("Package path is not
  valid"): the script puts `$ANDROID_HOME/cmdline-tools/latest/bin` first;
  install it with `sdkmanager --sdk_root=$ANDROID_HOME "cmdline-tools;latest"`.
- compileSdk 36 needs `platforms;android-36` and `build-tools;36.0.0`;
  accept licences with `yes | sdkmanager --licenses`.
- `JAVA_HOME` defaults to `java_home -v 21`.
- The script unsets `NODE_OPTIONS` (a stale preload from a terminal wrapper
  breaks node, esbuild under dune, and npx) and `CDPATH`.
- `monkey` exits non-zero even when it launches the app; the script resolves
  the launcher activity and uses `am start -W`.
- The devtools socket is `@webview_devtools_remote_<pid>` and appears a moment
  after the activity starts; `forward` polls for it. Only debug builds have it.
- Setting `location.hash` navigates in place (the router follows
  `hashchange`; leaving a `#dev/*` page reloads). `open` replaces the URL and
  reloads anyway, for a clean state: `herbierDev.live()` at its baseline and
  no SQLite connection left from the previous page.
- Native SQLite connections outlive a page reload; a probe that opens a
  database the page also opens can hit "connection already exists".
