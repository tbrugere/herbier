# Google Picker in the Capacitor WebView (M7.61 spike)

Run 2026-11-16 on the shared emulator (AVD `herbier`, API 35 Google APIs
image, Android System WebView 124.0.6367.219, user agent with `; wv`), dev
build, page `#dev/picker` (`app/ui/dev/picker_check.ml`), origin
`https://localhost`. No Google account on the emulator, so every run used a
dummy token (`ya29.invalid`) and a dummy app id (`123456789012`).

## Question

Does the web Picker (`https://apis.google.com/js/api.js`,
`gapi.load('picker')`, `PickerBuilder` with `setOAuthToken`, `setAppId`,
folder view) run inside the app's WebView with the drive.file token of
M7.51? Does it need a developer key (`setDeveloperKey`), or are the OAuth
token and the project number enough?

Google's overview
(https://developers.google.com/workspace/drive/picker/guides/overview) says
that the *desktop & mobile* Picker (an OAuth URL opened in the system
browser) "can no longer be displayed within an embedded webview". That
sentence is about that OAuth-URL Picker, not about the web Picker's iframe.
The web Picker guide lists an API key among its prerequisites.

## What ran

| Step | Result |
|---|---|
| `api.js` from `https://localhost` | loads (123 ms), `gapi.load('picker')` calls back (picker module 30 ms); `google.picker.*` present |
| Picker, dummy token, no key | the overlay and its `docs.google.com/picker` iframe render; the iframe shows Google's generic « 403. Il s'agit d'une erreur. » page; no callback action |
| Picker, dummy token, dummy key | the same 403 page |
| « Fermer » (`dispose`) | overlay and iframe removed; the future resolves `cancelled` |

The iframe is not refused as a frame (no `X-Frame-Options` /
`frame-ancestors` block for `https://localhost`), and no "embedded webview" or
"disallowed user agent" page appears.

To tell a WebView refusal from a token refusal, the iframe URL the WebView
built was requested again with curl (dummy values only), under three user
agents: the WebView's (`; wv`), mobile Chrome, desktop Chrome:

| Query | WebView UA | Mobile Chrome UA | Desktop Chrome UA |
|---|---|---|---|
| token + key | 403 | 403 | 403 |
| token, no key | 403 | 403 | 403 |
| token, no key, no app id | 403 | 403 | 403 |
| token, no key, origin `https://example.com` | 403 | 403 | 403 |
| no token, no key | 401 « Autorisez Google à accéder aux cookies nécessaires … Connectez-vous » | same | same |

So the 403 is the answer to the invalid token, whatever the browser, and does
not single out the WebView. Without a token the Picker falls back to the
browser's Google session (cookies), which the app's WebView has none of
(and third-party cookies are off by default in Android WebView): the token
path is the only one that can work, and it is the one the binding uses.

## Verdict

**Pass, provisionally** (plan rule: "an error that is clearly about the
dummy token"). The Picker loads and renders its frame in the WebView; the
only refusal seen is the token's. What a dummy token cannot show:

- whether the real Picker UI, once the token is valid, makes further
  requests that need Google cookies (third-party cookies are off in the
  WebView, and the spike does not turn them on);
- whether the key is needed: the dummy runs answer 403 with and without a
  key.

Both are the phone check: `#dev/picker` « Ouvrir (jeton Drive, sans clé) »
with the real drive.file token. If the folder list appears and a pick comes
back, the Picker works in the WebView with **no API key**
(`setOAuthToken` + `setAppId(<project number>)` only). Then « Choisir » in
4m stores a folder: it runs `files.get` on the picked id with the
Play-Services token before storing it, so a stored folder proves that the
Picker's grant reaches that token (a `No_access` error says it does not).
The dev page has no separate « Vérifier le dossier » button for this: 4m
runs the same check. On the emulator the Picker frame was viewport-wide at
phone width with no `setSize`; the real folder list's layout is part of the
phone check.

## Key or no key

The app ships the **keyless** Picker: only the Cloud project number
(`HERBIER_GOOGLE_CLOUD_PROJECT_NUMBER`, not a secret: it is the prefix of
the OAuth client ids already in the APK) is a build-time value. There is no
API key variable. The dev page has a « Clé API (essai) » field (never logged
or stored) so the phone check can try a key without a rebuild. If the phone
shows that only the keyed run works, adding a key is a decision for the
user: a Picker browser key restricted to the Picker API is not a secret
(it identifies the project for quota, gives no access to anyone's data, and
Google's samples put it in page JavaScript), but it would be extractable
from the APK.

## Trust

`api.js` is the first remote script run in the app's own origin, with the
page's full privileges (the Capacitor bridge, SQLite, the Supabase session,
the Drive token). It is Google's, over HTTPS, loaded only on « Choisir »,
trusted as Google sign-in already is; no Subresource Integrity is possible
(Google versions it in place). There is no Content Security Policy yet: one
would not limit what `api.js` can do once allowed, and the hosts it pulls
need checking on a device, so it is left as a question for M8.

## If the phone check fails

Do not work around it (no Storage Access Framework, no own Drive browser,
no user-agent rewrite, no third-party-cookie switch). Options for the user:

A. Google's mobile Picker: an OAuth URL with `trigger_onepick=true` and
   `allow_folder_selection=true`, opened in a Custom Tab, back through a
   redirect URI (custom scheme or App Link), code exchanged with PKCE.
B. No picking: M7.60 already follows the app's « Herbier » folder by id, so
   the user can move and rename it anywhere in Drive.

## Account (M7.62)

Checked 2026-11-16 in Google's docs, for 4m's « Dossier Drive » sheet:

- The Picker shows the account of the OAuth token it is given. The web
  Picker sample guide
  (developers.google.com/workspace/drive/picker/guides/web-picker-sample):
  « The `setOAuthToken` function allows an app to use the current auth token
  to determine which Google Account the Google Picker uses to display the
  files », and « If a user is signed in with multiple Google Accounts, the
  Google Picker can display the files of the appropriate authorized
  account ». There is no account switcher inside the Picker on this path,
  and no builder method names an account: the PickerBuilder reference
  (fetched 2026-11-16) lists `addView`, `addViewGroup`, `build`,
  `disableFeature`, `enableFeature`, `getRelayUrl`, `getTitle`,
  `hideTitleBar`, `isFeatureEnabled`, `setAppId`, `setCallback`,
  `setDeveloperKey`, `setDocument`, `setLocale`, `setMaxItems`,
  `setOAuthToken`, `setOrigin`, `setRelayUrl`, `setSelectableMimeTypes`,
  `setSize`, `setTitle` and `toUri` (no `setAuthUser`).
- The PickerBuilder reference
  (developers.google.com/workspace/drive/picker/reference/picker.pickerbuilder)
  has no option to render into a page element: its only layout controls are
  `setSize` (« The dialog will be auto-centered. It has a minimum size of
  (566,350) », wider than a phone, so it spans the width), `setTitle` and
  `hideTitleBar`, and the guide calls the Picker « an inline, modal
  window ».

So the sheet cannot hold the Picker under its own « Compte : … » line.
The Picker opens as Google's overlay over the sheet, with
`setTitle("Dossier Drive · <email>")` naming the account; its ✕ or Android
back shows the sheet again, with « Utiliser un autre compte » (the account
chooser, a drive.file token for the new account, a new Picker) and
« Par défaut ». Rejected as hacks: restyling Google's `.picker-dialog` nodes
(undocumented classes), raising our header over the overlay with a z-index
picked to beat Google's, embedding `PickerBuilder.toUri()` in our own iframe
(the callbacks travel over internal gadgets.rpc).
