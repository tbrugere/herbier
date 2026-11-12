---
name: emulator
description: Run the app on a headless Android emulator and drive its WebView over the DevTools Protocol, with scripts/emulator.sh and scripts/webview.mjs. Use for the "Manual device checks" of a PR (dev pages such as #dev/storage, #dev/store, #dev/seed), to inspect a dev page's output, take a screenshot of the app, or evaluate JS in the running app when no phone is attached.
---

# Emulator and WebView devtools

Two scripts do the work; this skill is how to use them and what goes wrong.

- `scripts/emulator.sh` (bash): `lock [label]`, `unlock [label]`,
  `lock-status`, `start`, `stop`, `install`, `install-web`, `launch`,
  `kill-app`, `forward`, `open [fragment]`, `webview <cmd>…`, `env`.
  Run with no argument for the usage text.
- `scripts/webview.mjs` (Node 22+, no dependency): `targets`, `eval <js>`,
  `text`, `screenshot <file>`, `wait-for <js> [ms]`,
  `wait-stable [quiet-ms] [ms]`, on `--port` (default 9222).

## One shared emulator, one check at a time

Each emulator costs about 5 GB of host memory (the API 35 image forces
2560 MB of guest RAM whatever `hw.ramSize` says, plus the GPU renderer) and
the Mac has 16 GB. So every agent and worktree shares one emulator, AVD
`herbier` on `emulator-5554`, and device checks take turns:

```sh
scripts/emulator.sh lock "<step or PR, e.g. M5.44 #46>"   # first, before start
# ... start, install-web, open, screenshots ...
scripts/emulator.sh unlock                                # last, also on failure
```

- `lock` waits until it holds the lock, printing the holder (label, PID,
  start time) every minute. It can wait long: run it in the background and
  poll, or set `HERBIER_LOCK_TIMEOUT=<s>` (exit 1 when still held). The lock
  is a directory, `~/.cache/herbier/emulator.lock` (`HERBIER_LOCK_DIR`);
  one older than 90 min is stale, and the next `lock` takes it over with a
  warning. `lock-status` prints the holder or `free`.
- Release it on every path out, failure included (a trap in a script:
  `trap 'scripts/emulator.sh unlock' EXIT`). `unlock "<label>"` refuses when
  another label holds it.
- Never boot a second AVD and never set `HERBIER_AVD` or
  `HERBIER_EMULATOR_PORT` for a check. `start` refuses to boot while
  another emulator runs (`HERBIER_ALLOW_SECOND_EMULATOR=1` overrides, for
  tooling work only). Without the lock, someone else's `install` replaces
  your APK under you.
- The emulator may be left running for the next holder; `stop` it when no
  other check is queued (`lock-status` free after your `unlock`).

### GPU mode

`start` boots with `-gpu host` (`HERBIER_EMULATOR_GPU` overrides). Measured
2026-11-12 on the M4 Mac, API 35 Google APIs arm64 image, headless, after
`#dev/seed`, `#dev/gallery` and `#dev/map` (`vmmap --summary <qemu pid>`):

| `-gpu` | boots | WebGL renderer | `#dev/map` | footprint | boot |
|---|---|---|---|---|---|
| `host` | yes | Apple M4 (via the emulator's GLES translator) | map, tiles and 13/13 points | 4.8–4.9 GB | 20–23 s (52 s first boot in this mode) |
| `swiftshader_indirect` | yes | SwiftShader (host side, ANGLE/Vulkan) | map and 13/13 points; "System UI isn't responding" dialogs | 5.2–5.3 GB | 42–47 s |
| `guest` | yes | SwiftShader (in the guest) | map and 13/13 points; ANR dialogs, `#dev/seed` past 2 min | 5.2 GB | 65 s |

Guest RAM is 2560 MB in every mode (the image forces it), so the renderer
is the only lever: `host` is the cheapest and the fastest. The emulator
warns that host OpenGL rendering is deprecated on macOS; if `host` stops
booting or the map goes blank after an emulator update,
`HERBIER_EMULATOR_GPU=swiftshader_indirect` is the fallback.

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
   scripts/emulator.sh lock "M5.44 #46"   # waits for the shared emulator
   scripts/emulator.sh start      # creates the AVD "herbier" if missing, boots headless
   scripts/emulator.sh install-web   # web-only fast path; falls back to install by itself
   scripts/emulator.sh open dev/storage      # prints the page text once it settles
   scripts/emulator.sh webview screenshot /path/in/scratchpad/storage.png
   ```
   Use `install-web` by default, including after switching branches. It
   runs `dune build @web` and serves the new bundle from the installed debug
   APK, without Gradle; it falls back to the full `install` (dune build @web,
   cap sync, assembleDebug, adb install -r) when the app is missing or the
   APK on the device was not built by `install` from the current native
   inputs: `android/`, `package.json`, `package-lock.json`,
   `capacitor.config.ts` (content hash of the checkout, uncommitted edits
   included). So the caller needs no decision; run `install` directly only
   to force an APK rebuild. See "Web-only reinstall" below.
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
5. `scripts/emulator.sh unlock` at the end, also when a check failed or the
   run was aborted. Then `scripts/emulator.sh stop` if `lock-status` says
   `free` (kills the emulator, removes the forward); the AVD stays for next
   time.

## Web-only reinstall

`install-web` copies `_build/default/web/dist` into the app's
`files/herbier-web-dev/<stamp>` (adb push to `/data/local/tmp/herbier-web/`,
then `run-as cp`) and calls Capacitor's own live-update API from the page:
`Capacitor.Plugins.WebView.setServerBasePath` then `persistServerBasePath`.
The app reloads at `https://localhost/` (no fragment; `open` sets one), with
the same origin, storage, SQLite files and plugins as before. The path is
persisted, so `kill-app` and relaunch keep the pushed bundle.

- `install` removes `files/herbier-web-dev`, so the APK's own assets are
  served again (Capacitor keeps a persisted path across a reinstall with the
  same version code). It also writes the stamp `install-web` checks,
  `/data/local/tmp/herbier-web/re.bruge.herbier.stamp` (native hash and
  `lastUpdateTime`); an APK installed any other way forces a full install.
- `pm clear` drops the pushed bundle too (back to the APK's assets); run
  `install-web` again after it.
- Which bundle is served:
  `webview eval "Capacitor.Plugins.WebView.getServerBasePath().then(r => r.path)"`
  (`public`: the APK's own assets).
- Release builds are untouched: nothing in the app or `capacitor.config.ts`
  changes.

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

- Skipping `lock`: another worktree on the same emulator replaces your APK
  under you (`dumpsys package re.bruge.herbier | grep lastUpdateTime`), and
  `#dev/<page>` falls back to a tab when the page is not in the installed
  build. `eval "$(scripts/emulator.sh env)"` sets `ANDROID_SERIAL` to
  `emulator-5554` for plain adb.
- `webview screenshot` does not capture the MapLibre WebGL canvas on the
  emulator (it comes out blank); use `adb exec-out screencap -p > file.png`
  for a map.
- `#dev/map` prints no `done`: `open dev/map` waits 2 min and fails, with
  the page loaded; read `herbierDev.mapRendered()` instead. Reach it with
  `kill-app` then `open dev/map` (a hash change from a page that holds the
  database fails with "database is locked").
- A previous run can leave airplane mode on: `adb shell cmd connectivity
  airplane-mode disable` (then `airplane-mode` prints `disabled`).

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
