# Herbier front-end stack: Eliom + Cordova feasibility (2026)

Date: 2026-09-15

All version numbers and dates below were checked on 2026-09-15 against opam (ocaml.org), the npm registry, GitHub and the vendors' sites. Items I could not confirm are marked UNVERIFIED.

## Summary

### Verdicts

**(a) Eliom + Cordova: not viable for Herbier, and not for lack of life in Eliom.** Eliom is alive (eliom 12.1.0 on 2026-06-23, ocsigenserver 7.0.0 on 2026-02-19, ocsigen-start 8.0.0 on 2026-02-27, TyXML 5.0.0 on 2026-09-08). The mobile path is the problem:

- The ocsigen-start mobile template is fossilised: `mobile!config.xml.in` pins `cordova-plugin-whitelist` (removed in cordova-android 10, 2021), `cordova-hot-code-push-plugin ~1.5.3` (last published 2017-05-27), a fork of `cordova-universal-links-plugin` (upstream 2016-10-23) and the deprecated `cordova-plugin-wkwebview-engine`. The README was tested with Node v10.24.1 and says Android images "> android-26 may not work". Last mobile-related commit to `Makefile.mobile`: 2021-11-26.
- The Ocsigen team's 2026-06-19 status post says "Ocsigen Start is switching from Cordova to Capacitor" and lists "Eliom offline apps" as backlog "waiting for funding". Nothing Capacitor-related has landed yet.
- An Eliom mobile app is a thin client of an ocsigenserver (`__eliom_server`, `Eliom_client.init_client_app`); the generated JS "must match exactly the version of the app" on the server. With Supabase as backend, Eliom's multi-tier RPC buys nothing and forces an extra OCaml server with no offline story.

What would hurt most: rebuilding the Cordova pipeline against cordova-android 15, no offline mode, the mandatory ocsigenserver.

**(b) Recommended OCaml stack:** js_of_ocaml 6.4.1 (2026-07-03) + Brr 0.0.9 (2026-09-09) for browser APIs and hand-written `Jv` FFI, a small UI layer (vdom 0.3, or hand-rolled Brr; Bonsai v0.17.0 on opam dates from 2024-05-26 and is heavy), packaged with **Capacitor 8** (8.5.2, 2026-09-11, ~1M downloads/week). Capacitor is framework-agnostic (`webDir` = any folder of built JS) and every plugin Herbier needs had a 2026 release. If you want React-ecosystem widgets, Melange 7.0.1 (2026-07-13) + reason-react 0.17.0 (2026-01-04) is the second choice. Wasm_of_ocaml (Chrome 119+) is optional and unnecessary here.

**(c) Native plugins:** share-target and deep-link intents, background upload (WorkManager), Google auth (Credential Manager + AuthorizationClient), SQLite if IndexedDB is outgrown, optionally camera preview. **WebView:** map (MapLibre GL JS), image compression, all UI, GPS, Supabase/PostgREST via fetch.

### Capability ratings (jsoo + Brr + Capacitor 8)

| Capability | Rating | How |
|---|---|---|
| Full-screen viewfinder + capture | doable | `getUserMedia` works in Capacitor's WebView (permission bridge in `BridgeWebChromeClient`); Brr_io.Media binds it. Native: @capacitor-community/camera-preview 8.0.1 |
| Pick from gallery | easy | `<input type=file>` or @capacitor/camera 8.2.4 `pickImages` |
| GPS with accuracy | easy | Brr_io.Geolocation or @capacitor/geolocation 8.2.2 |
| MapLibre slippy map + clusters | doable | maplibre-gl 6.9.1 via hand FFI (no opam bindings; leaflet 0.2 bindings exist). Android WebView slower than Chrome |
| Drag map under fixed pin | easy | overlay + `map.getCenter()` |
| Offline tile cache | painful | PMTiles 4.5.0 + maplibre-offline-pmtiles (OPFS). OPFS in Android WebView: UNVERIFIED |
| VIEW+BROWSABLE on gbif.org etc. | doable | manifest intent-filter + @capacitor/app `appUrlOpen`. Android 12+: unverified domains need the user to enable them in "Open by default" (same for Kotlin) |
| SEND text/plain share sheet | easy | @capgo/capacitor-share-target 8.0.52 or send-intent 7.0.0 |
| Google sign-in + Drive/Photos token | painful | WebView OAuth blocked; custom-scheme redirect "no longer supported on Android" per Google. Use @capgo/capacitor-social-login 8.5.8 (Credential Manager + AuthorizationClient, 1h tokens) or Supabase Auth as broker (`provider_refresh_token`). Photos Library API is app-created-content only since 2025-03-31 |
| Background upload queue | doable | @capgo/capacitor-uploader 8.3.15 (WorkManager + foreground service). Network-constraint options: UNVERIFIED |
| Offline-first local store | easy | IndexedDB via Jv FFI (ezjs_idb 0.1.1 is stale) or @capacitor-community/sqlite 8.1.1 |
| Client-side ≤1600px compression | easy | Brr_canvas.C2d + Blob |
| Shared-element / bottom sheets / swipe | doable | View Transitions + CSS + pointer events, hand-rolled |
| Custom fonts | easy | bundled woff2 |
| Zoomable photo viewer | doable | pointer events or FFI to a JS lib |
| Supabase | easy | PostgREST over Brr_io.Fetch (`apikey` + `Authorization`), or FFI to supabase-js 2.116.0 |

### Top 5 links

1. Ocsigen status 2026 (Cordova to Capacitor, offline apps unfunded): https://ocsigen.org/blog/posts/status-of-the-ocsigen-project.html (2026-06-19)
2. Eliom mobile-apps manual source (server required, version lock): https://raw.githubusercontent.com/ocsigen/eliom/master/doc/mobile-apps.mld
3. Capacitor 8 announcement: https://ionic.io/blog/announcing-capacitor-8 (2025-12-08)
4. Android AuthorizationClient (scopes, on-device 1h access token): https://developer.android.com/identity/authorization
5. Google OAuth for native apps (custom schemes unsupported on Android, no embedded webviews): https://developers.google.com/identity/protocols/oauth2/native-app (updated 2026-09-14)

## 1. State of Ocsigen / Eliom in 2025–2026

### Versions and activity (opam, checked 2026-09-15)

| Package | Latest | Date | Notes |
|---|---|---|---|
| eliom | 12.1.0 | 2026-06-23 | ocaml >= 4.12; ocsigenserver >= 7.0 < 8.0; js_of_ocaml >= 6.3.2; wasm_of_ocaml-compiler >= 6.3.2. Earlier: 12.0.1 2026-03-02, 12.0.0 2026-02-23, 11.1.1 2024-12-04 |
| ocsigenserver | 7.0.0 | 2026-02-19 | ocaml >= 4.10; Lwt >= 5.7, cohttp-lwt-unix >= 6.0 |
| ocsigen-start | 8.0.0 | 2026-02-27 | ocaml >= 4.10; eliom >= 12 < 13; requires PostgreSQL (pgocaml, ocsipersist-pgsql) |
| tyxml | 5.0.0 | 2026-09-08 | blog post |
| js_of_ocaml | 6.4.1 | 2026-07-03 | see section 5 |

Sources: https://ocaml.org/p/eliom/latest/versions, https://ocaml.org/p/eliom/latest, https://ocaml.org/p/ocsigenserver/latest, https://ocaml.org/p/ocsigen-start/latest/versions, https://ocsigen.org/blog/ (posts dated 2026-06-07 to 2026-09-08). Eliom repo last commits 2026-09-10/11 (GitHub API). ocsigen-start master commits through 2026-08-28 ("template: require the same eliom as ocsigen-start does", CI work) — none touch mobile.

Note: the WebFetch summary of https://github.com/ocsigen/eliom/releases reported dates two years earlier than opam for the same tags (e.g. 12.1.0 "June 2024"); opam's dates are the ones used here.

### 2026 roadmap (Ocsigen blog, 2026-06-19)

https://ocsigen.org/blog/posts/status-of-the-ocsigen-project.html
- Funding: Jane Street, Tarides, OCaml Software Foundation, NLnet, Ahrefs; "Most of the backlog above is simply waiting for funding."
- In progress: wasm_of_ocaml performance, wodoc documentation tool, hierarchical module names (`Eliom.Service`), build-system modernisation.
- Mobile: "On mobile, Ocsigen Start is switching from Cordova to Capacitor." No further detail.
- Planned, funding-dependent: "Eliom offline apps and distributed applications", server as a plain executable without config file, Lwt multi-domain work.
- Known gaps: Merlin/LSP multi-tier support incomplete, dune integration needs "dirty build-system workarounds".
- Related post 2026-07-01: "Why Ocsigen decided not to switch from Lwt to Eio (for now)".

### The Cordova workflow in ocsigen-start today

- `template.distillery/Makefile.mobile` (GitHub API, path history): last commits 2026-01-27 "Update template from os_template", 2025-03-05 "Remove dependency on lwt_ppx", 2021-11-26 "use version of cordova-hot-code-push-cli with up-to-date dependencies". Targets: `make android`, `android-release`, `emulate-android`, `run-android`, `chcp`. It `npm install`s cordova plus `git+https://github.com/besport/cordova-hot-code-push-cli.git`. No version pins.
- `template.distillery/mobile!config.xml.in` declares: cordova-plugin-whitelist@1, cordova-hot-code-push-plugin ~1.5.3, cordova-plugin-network-information ~1.2.0, cordova-plugin-globalization ~1.0.3, cordova-plugin-wkwebview-engine (GitHub), cordova-plugin-statusbar (GitHub), cordova-plugin-keyboard ~1.1.4, cordova-universal-links-plugin (besport fork). `android-minSdkVersion` is a template variable; no targetSdk preference. (https://raw.githubusercontent.com/ocsigen/ocsigen-start/master/template.distillery/mobile!config.xml.in)
- Template README (https://raw.githubusercontent.com/ocsigen/ocsigen-start/master/template.distillery/README.md): "npm : 6.14.12", "nodejs : v10.24.1", JDK 11, `system-images;android-26;default;x86` with the note "version > android-26 may not work"; warns that "NPM packages (and especially Cordova plugins) are very sensitive to version changes". Server address is injected via `APP_SERVER`, `APP_REMOTE`, `APP_PATH`; the app self-updates at launch via Cordova Hot Code Push (`make chcp`).
- npm status of those plugins (registry, 2026-09-15): cordova-hot-code-push-plugin 1.5.3 published 2017-05-27; cordova-universal-links-plugin 1.2.1 published 2016-10-23; cordova-plugin-whitelist is obsolete since cordova-android 10 (2021-07-20, https://cordova.apache.org/announcements/2021/07/20/cordova-android-10.0.0.html). Current cordova-android is 15.1.0 (2026-07-22) requiring Node >= 20.17 and targetSdk 36.
- Open ocsigen-start issues: #596 "demo apk does not launch" (2020-05-25, open), #419 "Get rid of chcp" (2017, open), #462 iOS build failure (2017, open). (https://github.com/ocsigen/ocsigen-start/issues?q=capacitor+OR+cordova+OR+android). Zero results for "capacitor" in PRs/issues.
- Conclusion: `make android` as shipped will not work against cordova-android 15 / Android 15–16 without rewriting `config.xml.in`, dropping CHCP/whitelist/wkwebview-engine, and replacing universal-links. The Play targetSdk requirement is moot if sideloaded, but cordova-android 15 itself targets SDK 36 anyway.

### Does an Eliom mobile app need ocsigenserver?

Yes, by design. From the Eliom manual source (https://raw.githubusercontent.com/ocsigen/eliom/master/doc/mobile-apps.mld): the mobile app "starts client-side, whereas the Web app is sent by the server"; you must "Define JavaScript variables `__eliom_server` and `__eliom_app_name` in the `index.html`" and call `Eliom_client.init_client_app`; "the server won't be able to send global injections to the client", worked around by ocsigen-start's `Eliom_loader`, which fetches global data from the server at startup; and "The JavaScript file generated by Js_of_ocaml will be included in your mobile app. But it must match exactly the version of the app" (hence hot code push or multiple server versions behind a load balancer). The doc also warns about iOS cookies (`__eliom_use_cookie_substitutes`). No mention of Capacitor or offline operation.

You can technically compile Eliom client-side code with no services registered and call Supabase from it, but then you are using js_of_ocaml with an unused framework on top; the things Eliom provides (shared client/server sections, services, RPC, server push, sessions) all presuppose ocsigenserver.

### What Eliom buys vs plain js_of_ocaml

For Herbier: essentially nothing. Eliom's value is a single OCaml codebase across an OCaml server and its client (typed RPC, injections, server-side rendering). With Supabase as backend there is no OCaml server to share code with. Costs: ocsigenserver + PostgreSQL deployment, Lwt-only, version lock between app and server, no offline-first, ocsigen-start's demo-heavy template, and an unmaintained mobile pipeline.

## 2. Cordova vs Capacitor in 2026

### Cordova
- Not deprecated; volunteer-maintained. 2025–2026 releases (https://cordova.apache.org/blog/): cordova-android 14.0.0 (2025-03-26, targetSdk 35), 14.0.1 (2025-04-30), 15.0.0 (2026-03-06, targetSdk 36 / minSdk 24, Gradle 8.14.2, AGP 8.10.1, Node >= 20.17, Kotlin 2.1.21, built-in status bar, edge-to-edge), 15.1.0 (2026-07-22, "fixes getUserMedia() permission handling", PermissionHelper deprecated); cordova-ios 8.0.0 (2025-11-23), 8.1.x (2026); cordova CLI 13.0.0 (2025-11-25, Node >= 20.17, telemetry and `cordova serve` removed); InAppBrowser 7.0.0 (2026-06-16) and 6.0.1 security fix CVE-2026-47430 (2026-06-07); file-transfer 2.0.1 (2026-08-10); network-information 3.1.0 (2026-05-16).
- WebView: system Android WebView since cordova-android 10 content is served from `https://localhost` via WebViewAssetLoader (file:// mode is opt-in and "insecure") — https://cordova.apache.org/announcements/2021/07/20/cordova-android-10.0.0.html.
- Plugin ecosystem (npm registry, 2026-09-15):

| Plugin | Latest | Published | Verdict |
|---|---|---|---|
| cordova-plugin-camera | 8.0.0 | 2024-11-02 | Apache, alive (native camera UI only) |
| cordova-plugin-camera-preview | 0.14.0 | 2025-07-12 | community, alive-ish |
| cordova-plugin-geolocation | 5.0.0 | 2023-09-21 | Apache, stable |
| cordova-plugin-file | 8.1.3 | 2024-11-20 | Apache |
| cordova-sqlite-storage | 7.0.0 | 2025-01-28 | alive |
| cordova-plugin-background-upload | 1.1.0 | 2019-07-15 | dead |
| cordova-universal-links-plugin | 1.2.1 | 2016-10-23 | dead |
| cordova-plugin-openwith | (no latest tag) | last modified 2020-04-16 | dead |
| cordova-plugin-customurlscheme | 5.0.2 | 2020-07-30 | dead |
| cordova-plugin-intent | 0.1.2 | 2015-12-25 | dead |
| cordova-plugin-googleplus | 8.5.2 | 2021-02-11 | archived repo (https://github.com/EddyVerbruggen/cordova-plugin-googleplus) |
| cordova-hot-code-push-plugin | 1.5.3 | 2017-05-27 | dead |
| cordova-plugin-inappbrowser | 7.0.0 | 2026-06-22 | Apache |

Everything Herbier needs beyond camera/geo/file/sqlite (share receiver, App Links, Google auth, background upload) is dead on Cordova; you would write your own plugins.

### Capacitor
- Capacitor 8 GA 2025-12-08 (https://ionic.io/blog/announcing-capacitor-8): "nearing one million downloads per week", SPM default on iOS, internal SystemBars plugin for edge-to-edge. @capacitor/core & android 8.5.2 published 2026-09-11. Requirements (https://capacitorjs.com/docs/updating/8-0): minSdk 24, target/compile SDK 36, AGP 8.13, Gradle 8.14.3, Kotlin 2.2.20, Android Studio Otter 2025.2.1+. Android docs: API 24+, "an Android WebView with Chrome version 60 or later" (https://capacitorjs.com/docs/android).
- Framework-agnostic packaging (https://capacitorjs.com/docs/basics/workflow): build web code into `webDir`, `npx cap sync`, `npx cap open android`. A js_of_ocaml `.js` plus an `index.html` is exactly that; no bundler needed.
- Can also consume Cordova plugins (no hooks/variables) (https://capacitorjs.com/docs/plugins/cordova).
- Plugins (npm registry, 2026-09-15): @capacitor/camera 8.2.4 (2026-09-01), @capacitor/geolocation 8.2.2 (2026-08-13), @capacitor/filesystem 8.1.3 (2026-08-19), @capacitor/app 8.1.1 (2026-07-15; `appUrlOpen`), @capacitor/browser 8.0.4 (2026-07-15; Custom Tabs), @capacitor/share 8.0.1, @capacitor-community/sqlite 8.1.1 (2026-08-06; SQLCipher-based, maintained by Capawesome, "maintenance: yes/2026"), @capacitor-community/camera-preview 8.0.1 (2026-04-17), @capgo/camera-preview 8.11.2 (2026-07-15), @capgo/capacitor-uploader 8.3.15 (2026-09-14), @capgo/capacitor-share-target 8.0.52 (2026-09-14), send-intent 7.0.0 (2025-02-27), @capgo/capacitor-social-login 8.5.8 (2026-09-14), @capawesome/capacitor-google-sign-in 0.1.4 (2026-09-02), @capacitor-community/generic-oauth2 7.1.0 (2026-04-22), @capacitor/background-runner 3.0.0 (2025-12-10), @transistorsoft/capacitor-background-fetch 8.1.3 (2026-04-21), @capgo/capacitor-supabase (MPL-2.0, native Supabase auth).
- Camera in WebView: Capacitor's `BridgeWebChromeClient.onPermissionRequest` maps `android.webkit.resource.VIDEO_CAPTURE` to `Manifest.permission.CAMERA`, requests it, then `request.grant(...)`, so `navigator.mediaDevices.getUserMedia` works (https://raw.githubusercontent.com/ionic-team/capacitor/main/android/capacitor/src/main/java/com/getcapacitor/BridgeWebChromeClient.java). Content is served from `http(s)://localhost`, which getUserMedia requires.
- Background upload: @capgo/capacitor-uploader "uses WorkManager for reliable uploads and shows a foreground service notification"; "continue in the background even if the app is closed" (https://capgo.app/docs/plugins/uploader/). Whether it exposes WorkManager network constraints (unmetered only etc.): UNVERIFIED.
- Which is more alive: Capacitor, by a wide margin (weekly releases across the plugin set vs. a handful of Apache core releases per year and dead community plugins).

## 3. Maps in a WebView

- maplibre-gl 6.9.1 published 2026-09-14 (npm registry); pmtiles 4.5.0 (2026-08-10); leaflet 1.9.4 (2023-05-18, unchanged).
- MapLibre GL JS runs in Android WebView (WebGL2 is available in Chromium WebView). Historical crash with 3D terrain in a Cordova WebView, maplibre 2.2.0-pre.3, 2022-07-10, closed (https://github.com/maplibre/maplibre-gl-js/issues/1368). General Android WebView performance is below Chrome ("less CPU and GPU power than the Google Chrome app itself", accessibility services can block the JS thread) — https://github.com/ionic-team/capacitor/discussions/3899 (2020, still referenced). Clusters are built into MapLibre GeoJSON sources.
- Offline: https://github.com/makinacorpus/maplibre-offline-pmtiles (MIT) downloads PMTiles archives into OPFS and serves them to MapLibre; it recommends 10–100 MB regions. Older mbtiles approach: https://github.com/Yermo/maplibre-gl-capacitor-offline (based on maplibre-gl-js 1.15.2, stale). OPFS availability inside Android System WebView: UNVERIFIED (Chromium supports it; WebView-specific behaviour not checked). Fallback: store PMTiles via @capacitor/filesystem and add a custom `addProtocol` fetcher.
- Native alternative: Capawesome's Capacitor MapLibre plugin wraps MapLibre Native on Android/iOS, but "Marker clustering and offline maps are not supported" (2026-08-26, https://capawesome.io/blog/alternative-to-the-capacitor-google-maps-plugin/). Not suitable for Herbier's cluster/offline needs.
- OCaml bindings: no MapLibre bindings on opam. `leaflet` 0.2 (2025-02-06, Brr/js_of_ocaml, Leaflet 1.9.4, NGI0-funded) exists: https://ocaml.org/p/leaflet/latest. Hand FFI for MapLibre via Brr's `Jv` is routine: `Jv.get`, `Jv.call`, `Jv.obj` for options; a day or two for map/marker/source/layer/event coverage. gen_js_api 1.1.7 (https://ocaml.org/p/gen_js_api/latest) is the alternative for larger surfaces.

## 4. Google Photos / Drive OAuth from a WebView

- Google rejects OAuth in embedded WebViews (`disallowed_useragent`) since 2023-07-24 (https://developers.googleblog.com/upcoming-security-changes-to-googles-oauth-20-authorization-endpoint-in-embedded-webviews/).
- "OAuth 2.0 for Mobile & Desktop Apps" (updated 2026-09-14, https://developers.google.com/identity/protocols/oauth2/native-app): "Custom URI schemes are no longer supported on Android and Chrome apps"; loopback redirect "DEPRECATED for Android, Chrome app and iOS"; no client secret for Android clients; PKCE recommended; refresh tokens issued to installed apps. So the AppAuth/@capacitor-community/generic-oauth2 route (AppAuth + PKCE, https://github.com/capacitor-community/generic-oauth2) is off-policy for Google on Android even though it is maintained (7.1.0, 2026-04-22).
- The supported Android pattern (https://developer.android.com/identity/authorization): Credential Manager for sign-in, then `Identity.getAuthorizationClient(activity).authorize(AuthorizationRequest{scopes})` which returns an on-device access token ("Short-lived: 1-hour lifespan") and, with `requestOfflineAccess(serverClientId)`, a `serverAuthCode` to exchange on a backend for a refresh token ("Never store refresh tokens on device"). play-services-auth 22.0.0 in the doc.
- Capacitor wrappers: @capgo/capacitor-social-login 8.5.8 uses "Google Credential Manager on Android"; result has `idToken`, `accessToken` ("May be null on Android when Credential Manager authentication succeeds but AuthorizationClient does not return an access token"), `mode: 'offline'` returns only `serverAuthCode`; extra scopes can be requested (https://raw.githubusercontent.com/Cap-go/capacitor-social-login/main/README.md). @capawesome/capacitor-google-sign-in 0.1.4 also uses Credential Manager + AuthorizationClient but only returns `serverAuthCode` for scopes and tells you to exchange it server-side (https://capawesome.io/docs/sdks/capacitor/google-sign-in/, updated 2026-07-08). CodetrixStudio/CapacitorGoogleAuth is "virtually archived" (Capacitor 6 max, legacy GoogleSignIn SDK) and points to Cap-go.
- Broker option: Supabase Auth `signInWithOAuth({provider:'google', options:{scopes, queryParams:{access_type:'offline', prompt:'consent'}, redirectTo}})` returns `provider_token` and `provider_refresh_token` in the session (https://supabase.com/docs/guides/auth/social-login/auth-google; https://github.com/orgs/supabase/discussions/36740). Open the URL with @capacitor/browser (Custom Tabs) and redirect to a custom scheme handled by `appUrlOpen`; use PKCE flow. Supabase does not refresh the Google token for you: refreshing needs the Web client's secret, i.e. a Supabase Edge Function.
- Photos: since 2025-03-31 the Library API "will only manage photos and videos created by your app"; `photoslibrary.appendonly`, `readonly.appcreateddata`, `edit.appcreateddata` remain (https://developers.google.com/photos/overview/authorization; https://developers.google.com/photos/support/updates). Drive `drive.file` is unaffected. Both are sensitive scopes; an unverified app works for the developer's own account in Testing mode.

## 5. js_of_ocaml ergonomics

- js_of_ocaml/wasm_of_ocaml share one repo and release together since 6.0.1 (2025-02-13): 6.1.0 2025-07-05 (drops OCaml 4.12), 6.2.0 2025-08-04, 6.3.0/6.3.2 2026-02-18, 6.4.0 2026-06-23, 6.4.1 2026-07-03 (https://ocaml.org/p/js_of_ocaml/latest/versions). 6.4.0 adds Promise/Fetch bindings, OCaml 5.5 support, Wasm dynlink/toplevel.
- Wasm_of_ocaml: first release 2025-02-19 (Tarides); Jane Street reports 2x–8x over jsoo; targets Chrome 119+, Firefox 120+, Safari 18.2+ (https://ocaml.org/backstage/2026-04-16-wasm-of-ocaml-what-changed-since-6-1, 2026-04-16; https://tarides.com/blog/2026-02-11-announcing-new-wasm-of-ocaml-optimisations/). Android System WebView tracks Chromium, so WasmGC is available on any updated device; but Herbier is UI-bound, not CPU-bound, so JS output is the safer default (smaller toolchain surface, sourcemaps).
- Bindings: Brr 0.0.9 (2026-09-09, requires js_of_ocaml-compiler >= 6.0.1, https://ocaml.org/p/brr/latest) covers Fetch, Storage, Clipboard, File/Blob, Geolocation, Media capture (getUserMedia), Canvas 2D/WebGL2/WebGPU, Web Audio, Workers/Service Workers, Notification, History, FormData; "Exhaustiveness is a non-goal". Not covered: IndexedDB (write ~200 lines over `Jv`, or ezjs_idb 0.1.1 from 2021, LGPL, https://ocaml.org/p/ezjs_idb/latest), MapLibre, Capacitor plugin objects (all are plain JS objects/promises, trivial with `Jv` + `Fut`).
- UI frameworks: vdom 0.3 (LexiFi, Elm architecture over gen_js_api, 2023-10-10, https://ocaml.org/p/vdom/latest); Bonsai v0.17.0 on opam (2024-05-26, OCaml >= 5.1, 49 deps incl. core/async/incr_dom; `bonsai_web` is not a separate opam package) — heavy for a phone app; Brr + hand-rolled state is the lightest. Melange 7.0.1 (2026-07-13; builds for OCaml 4.14, 5.1–5.5 per the `-414/-51..-55` suffixes, https://ocaml.org/p/melange/latest/versions) + reason-react 0.17.0 (2026-01-04, requires melange >= 6, https://ocaml.org/p/reason-react/latest) gives npm React libraries (bottom sheets, gesture libs, framer-motion) at the cost of a JS bundler and looser typing at the FFI. Tarides' 2025-05-15 overview: https://tarides.com/blog/2025-05-15-ocaml-web-development-essential-tools-and-libraries-in-2025/.
- Bundle size: the 2022-01-23 study measured a jsoo runtime baseline of 51.6 KB parsed / 17.5 KB gzipped, growing to 110 KB / 33 KB with nine components; "same order of magnitude" as ReScript (https://www.javierchavarri.com/js_of_ocaml-bundle-size-study/). Irrelevant for a local Capacitor bundle; MapLibre GL JS alone is far larger.
- Dev loop: `dune build -w` (watch mode rewritten in Dune 3.0) with separate compilation in the dev profile; no hot module reload; Capacitor's `server.url` live-reload can point the WebView at a local static server, so edit -> dune -> refresh is a few seconds. UNVERIFIED for this exact setup.
- Supabase: call PostgREST directly with Brr_io.Fetch and the `apikey` + `Authorization: Bearer` headers (https://supabase.com/docs/guides/api); FFI to supabase-js 2.116.0 (2026-09-07) is also easy if you want Auth/Storage helpers, or @capgo/capacitor-supabase for native session handling.

## 6. Verdict detail

(a) Eliom + Cordova: the Ocsigen team is itself leaving Cordova, the template's Cordova config is from the cordova-android 6–9 era, hot-code-push and universal-links plugins are dead, and Eliom mandates an ocsigenserver that Herbier does not otherwise need. Pain ranking: (1) rebuilding the mobile pipeline, (2) no offline mode in Eliom, (3) hosting/version-locking an OCaml server next to Supabase, (4) dead auth/share/upload plugins on Cordova.

(b) js_of_ocaml + Brr (+ vdom or hand-rolled) + Capacitor 8, or Melange + reason-react + Capacitor 8 if you want React-ecosystem widgets. Cordova is workable as a packaging layer only if you write four plugins yourself; Capacitor already has them.

(c) Native: share-target, App Links/deep-link delivery, Google sign-in + AuthorizationClient, WorkManager upload queue, optional SQLite and camera preview. WebView: everything else.

Cross-cutting caveat independent of stack: intercepting `https://www.gbif.org/species/*` etc. requires the user to enable the domains manually under "Open by default" on Android 12+, because App Links verification needs an `assetlinks.json` on a domain you own (https://developer.android.com/training/app-links/verify-android-applinks: "When the user turns on Open supported links ... They can also select Add link to add domains"). A Kotlin app has the same limitation.

## All sources

- https://ocaml.org/p/eliom/latest and /versions (2026-09-15)
- https://ocaml.org/p/ocsigenserver/latest
- https://ocaml.org/p/ocsigen-start/latest and /versions
- https://ocsigen.org/blog/ ; https://ocsigen.org/blog/posts/status-of-the-ocsigen-project.html (2026-06-19)
- https://raw.githubusercontent.com/ocsigen/eliom/master/doc/mobile-apps.mld
- https://raw.githubusercontent.com/ocsigen/ocsigen-start/master/template.distillery/Makefile.mobile
- https://raw.githubusercontent.com/ocsigen/ocsigen-start/master/template.distillery/mobile!config.xml.in
- https://raw.githubusercontent.com/ocsigen/ocsigen-start/master/template.distillery/README.md
- https://github.com/ocsigen/ocsigen-start/issues/292 (2016), /issues?q=capacitor+OR+cordova+OR+android
- GitHub API: repos/ocsigen/ocsigen-start/commits?path=template.distillery/Makefile.mobile ; repos/ocsigen/eliom/commits
- https://cordova.apache.org/blog/ ; https://cordova.apache.org/announcements/2026/03/06/cordova-android-15.0.0.html ; .../2026/07/22/cordova-android-15.1.0.html ; .../2025/03/26/cordova-android-14.0.0.html ; .../2021/07/20/cordova-android-10.0.0.html
- https://cordova.apache.org/deprecation_policy.html ; https://github.com/EddyVerbruggen/cordova-plugin-googleplus
- https://ionic.io/blog/announcing-capacitor-8 (2025-12-08) ; https://capacitorjs.com/docs/updating/8-0 ; https://capacitorjs.com/docs/android ; https://capacitorjs.com/docs/basics/workflow ; https://capacitorjs.com/docs/plugins/cordova ; https://capacitorjs.com/docs/guides/deep-links
- https://raw.githubusercontent.com/ionic-team/capacitor/main/android/capacitor/src/main/java/com/getcapacitor/BridgeWebChromeClient.java
- https://github.com/ionic-team/capacitor/discussions/3899
- npm registry JSON for every package listed in section 2 (queried 2026-09-15)
- https://capgo.app/docs/plugins/uploader/ ; https://github.com/Cap-go/capacitor-uploader ; https://github.com/Cap-go/capacitor-share-target ; https://github.com/carsten-klaffke/send-intent ; https://github.com/capacitor-community/sqlite ; https://github.com/capacitor-community/camera-preview ; https://github.com/Cap-go/capacitor-supabase
- https://capawesome.io/docs/sdks/capacitor/google-sign-in/ (2026-07-08) ; https://github.com/CodetrixStudio/CapacitorGoogleAuth ; https://raw.githubusercontent.com/Cap-go/capacitor-social-login/main/README.md ; https://github.com/capacitor-community/generic-oauth2
- https://developer.android.com/identity/authorization ; https://developers.google.com/identity/protocols/oauth2/native-app (2026-09-14) ; https://developers.googleblog.com/upcoming-security-changes-to-googles-oauth-20-authorization-endpoint-in-embedded-webviews/ ; https://developer.android.com/training/app-links/verify-android-applinks
- https://developers.google.com/photos/overview/authorization ; https://developers.google.com/photos/support/updates
- https://supabase.com/docs/guides/auth/social-login/auth-google ; https://github.com/orgs/supabase/discussions/36740 ; https://supabase.com/docs/guides/api
- https://github.com/makinacorpus/maplibre-offline-pmtiles ; https://github.com/Yermo/maplibre-gl-capacitor-offline ; https://github.com/maplibre/maplibre-gl-js/issues/1368 ; https://capawesome.io/blog/alternative-to-the-capacitor-google-maps-plugin/ (2026-08-26) ; https://ocaml.org/p/leaflet/latest ; https://ocaml.org/p/gen_js_api/latest
- https://ocaml.org/p/js_of_ocaml/latest/versions ; https://ocaml.org/backstage/2026-04-16-wasm-of-ocaml-what-changed-since-6-1 ; https://tarides.com/blog/2026-02-11-announcing-new-wasm-of-ocaml-optimisations/ ; https://tarides.com/blog/2025-02-19-the-first-wasm-of-ocaml-release-is-out/ ; https://tarides.com/blog/2025-05-15-ocaml-web-development-essential-tools-and-libraries-in-2025/
- https://ocaml.org/p/brr/latest ; https://erratique.ch/software/brr/doc/index.html ; https://ocaml.org/p/vdom/latest ; https://ocaml.org/p/bonsai/latest/versions ; https://ocaml.org/p/ezjs_idb/latest ; https://ocaml.org/p/melange/latest/versions ; https://raw.githubusercontent.com/melange-re/melange/main/README.md ; https://ocaml.org/p/reason-react/latest
- https://www.javierchavarri.com/js_of_ocaml-bundle-size-study/ (2022-01-23)
