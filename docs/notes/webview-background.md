# « Toute la France » in the background (M5.78 spike)

Run 2026-11-20 on the shared emulator (AVD `herbier`, API 35 Google APIs
arm64, Android 15, Android System WebView 124.0.6367.219), debug build of the
M5.78 branch, Capacitor 8.5.3. Runs through the dev hook
(`herbierDev.downloadFrance(codes)`, `""` = the whole list); device timestamps
from `adb logcat -v epoch` on `Capacitor/Console` (each département's
`communes: downloaded <code>` line, the run's `communes: france …` end line)
and `HerbierForegroundRun` (the service's start, interrupt and destroy).

## Question

M5.73's run lives in the WebView. With a foreground service of type dataSync
running (`ForegroundRunPlugin`, `ForegroundRunService`), does the WebView keep
running its JS (fetches, timers) and the run progress with the app in the
background and the screen off? Does the plugin need to touch the WebView?

## What the code says (Capacitor 8.5.3)

`BridgeActivity.onPause` → `Bridge.onPause` →
`MockCordovaWebViewImpl.handlePause(keepRunning)`, which calls
`webView.onPause(); webView.pauseTimers()` only when `keepRunning` is false.
`Bridge.shouldKeepRunning()` reads the Cordova preference `KeepRunning`,
default true, and Herbier sets none (no `res/xml/config.xml`). So Capacitor
never pauses the WebView's timers; what remains is Android (process state,
network access of background apps, Doze) and Chromium (hidden-page timer
throttling).

## Measurements

| Phase | Service | Seconds | Départements done | Notes |
|---|---|---|---|---|
| Foreground, screen on (20 codes) | yes | 59 | 20 | 1–7 s each, ~3 s on average |
| Foreground, screen on (95-code run, first phase) | yes | 26 | 7 | |
| App sent home (`KEYCODE_HOME`) | yes | 31 | 5 | larger départements in this stretch |
| Then screen off (`KEYCODE_SLEEP`) | yes | 42 | 9 | `mWakefulness=Asleep` |
| Then Doze (`deviceidle force-idle`) | yes | 41 | 15 | fetches complete under forced deep idle |
| Then `unforce`, screen still off | yes | 76 | 25 | run ends `complete 101/101`, service destroyed |
| Whole run screen off from its 4th second (95 départements) | yes | 260 | 95 | `complete 101/101 50341668`, notification gone |
| Control: service stopped by hand 3 s after the start, home + screen off | no | 120 | 4 in the first 5 s, then none | `communes: download 11 network: Failed to fetch` 6 s after home; the retry's request never answered until the screen was woken (it then timed out) |

Process state (`dumpsys activity processes re.bruge.herbier`): with the
service, the app and the WebView's sandboxed renderer
(`com.google.android.webview:sandboxed_process0`) are both `curProcState=4`
(PROCESS_STATE_FOREGROUND_SERVICE), not frozen, in every phase above. Without
it, both drop to 15 (cached) once the activity stops: the network is cut a
few seconds later (Android blocks network access for apps in the background
process states) and the run stalls on its next request.

Timers: `document.visibilityState` is `hidden` in the background, as
expected. A probe `setInterval(…, 5000)` fired every 5 s for about 60 s
after the page was hidden, then once a minute (Chromium's intensive
throttling of chained timers), with or without the service. The run is not
affected: the Geocoder's spacing and the retry waits are single `setTimeout`s
started from fetch callbacks, not chained timers, and the 95-département run
kept 2.7 s per département with the screen off (no slowdown against the
foreground). At that pace the full 101-département run takes about 5 min,
far from dataSync's 6 h budget (Android 15+).

## Verdict

**Clean.** With the service the WebView keeps running its JS, its fetches
complete (Doze included) and the run reaches `complete` with the app in the
background and the screen off; the service is what makes it work (the control
stalls within seconds). The plugin does nothing to the WebView: no
`resumeTimers`, no renderer priority, no wake lock. Capacitor does not pause
the timers (`KeepRunning` default) and the renderer inherits the app's
foreground-service priority by its binding.

## Other observations from the device checks

- The notification permission dialog (API 35) took up to 24 s to show on the
  emulator; the run had already started (it never waits for it). A run that
  ends before the answer starts no service (`stop` came first); the answer
  only logs `france: notifications denied` when refused.
- Permission refused: the service runs foreground (`curProcState=4`) with no
  notification shown, and the run goes on in the background (21 départements
  in 45 s, screen off).
- Task removed (`am stack remove`, as a swipe in recents): the system stops
  the service (`stopWithTask`) and the notification goes. The WebView is not
  destroyed at once: its JS downloaded one or two more départements (normal
  packs) before the cached process lost the network. The next run skips them.
- `am force-stop` and a WebView reload (`start_france`'s `stop`) leave no
  service and no notification.
- Tapping the notification's body brings Herbier to the front on its current
  screen, the run going on (no restart, no 4j).

## Notification checks

Same emulator, the notification permission granted, runs started from the
main page through the dev hook.

- Progress: a 20-département run sent home then screen off; two
  `dumpsys notification --noredact` reads 12 s apart show the run's notification
  (channel `downloads`, `FOREGROUND_SERVICE`, one action « Interrompre »)
  titled « IGN hors-ligne : 11 / 20 départements » (progress 11/20), then
  « … 15 / 20 … » (15/20). The run ended `complete 20/20`, the service was
  destroyed in the same 11 ms and no notification of the app was left.
- « Interrompre »: a 40-département run sent home; the action tapped in the
  shade (`input tap` on the expanded notification's button, not an `am`
  intent) → `HerbierForegroundRun: interrupt` → `communes: france cancelled
  20/40` 0.8 s later (the département in progress finished) →
  `HerbierForegroundRun: destroy`; no notification of the app left.
- A start followed at once by a stop, 20 times in a row from the page: all
  20 reached the service before it went foreground (`stopped before
  start`: it goes foreground, then stops itself); the process survived
  (same pid), no notification left.
