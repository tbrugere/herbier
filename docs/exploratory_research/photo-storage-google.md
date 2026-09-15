# Photo storage for Herbier: Google Photos vs Google Drive vs alternatives

Date: 2026-09-15. Single-user Android WebView app (Cordova/Capacitor, JS from OCaml); a few thousand
field photos (originals 3-8 MB) plus a <=1600 px preview; Supabase free tier (1 GB Storage) for data.
Every claim cites a source with its date; **UNVERIFIED** marks things I could not confirm from a
primary source.

## Summary

**Recommendation.** Implement **Google Drive with the `drive.file` scope** first: folder
`Herbier/<species>/`, one Drive file per original, `appProperties` carrying the Herbier photo id and
hash. `drive.file` is the only Drive scope that is *non-sensitive*, so the OAuth client can be published
"In production" with **no verification, no "unverified app" screen, and no 7-day token expiry**. Keep the
compressed preview on device and in Supabase Storage. **Defer Google Photos** (Library upload and
Picker): Google states every Photos scope must pass OAuth verification, so a personal app is stuck in
Testing (re-consent every 7 days) or behind the unverified-app screen; the Library API also has a
10,000 requests/day quota and 60-minute baseUrls. The camera-roll backup still puts originals in Google Photos. If originals outgrow the 15 GB
Google quota, add **Cloudflare R2** (10 GB free, egress free, then $0.015/GB-month: ~20 GB of originals
is ~$0.15/month) via presigned URLs from a Supabase Edge Function.

**Key rules (2026).**
- Photos Library API since 2025-03-31: `photoslibrary`, `.readonly`, `.sharing` removed (403); all
  list/get/search/album methods only see **app-created** content; scopes are `photoslibrary.appendonly`,
  `photoslibrary.readonly.appcreateddata`, `photoslibrary.edit.appcreateddata`. Uploads are original
  quality and **count against the shared 15 GB**. Quotas: **10,000 requests/day + 75,000 media-bytes
  requests/day per project**; baseUrl valid **60 min**; upload token 1 day; photos <=200 MB. No API can
  delete a media item. No 2026 changes in the release notes.
- Photos Picker API: scope `photospicker.mediaitems.readonly`; 100,000 req/min; picked items come with
  60-minute baseUrls (`=d` strips GPS); after the session expires there is no way to re-fetch a picked,
  non-app-created item, so bytes must be downloaded during the session.
- Drive: `drive.file` non-sensitive; `drive`/`drive.readonly` restricted (annual re-verification).
  Quota model since 2026-05-01: 1,000,000 units/min/project, 325,000/min/user (read 5, list 100,
  download 200, edit 50). `thumbnailLink` lasts "hours" and accepts `=s1600`; `files.get?alt=media` for
  bytes; deletion shows as `trashed:true`, then 404. New desktop/mobile Drive Picker supports Android via
  `AuthorizationRequest` + `PICKER_OAUTH_TRIGGER`, `drive.file` only.
- OAuth audience: **Testing** = max 100 test users, grants and refresh tokens expire **7 days** after
  consent for every scope except name/email/profile (so `drive.file` too). **In production** with only
  non-sensitive scopes = no verification. In production with unverified sensitive scopes = warning screen
  and a lifetime cap of **100 users**. 100 refresh tokens per account per client; 6-month inactivity
  revocation. A Workspace org ("Internal" apps, ~$7/user/month) removes all of this; unnecessary for `drive.file`.
- Android: Google returns `403 disallowed_useragent` for OAuth in embedded WebViews, and its native-app
  guide (updated 2026-09-14) now says custom-URI-scheme redirects are **no longer supported on Android**
  and loopback is deprecated for Android clients, so AppAuth/Custom-Tabs against an Android client is
  out. Use **Credential Manager + `AuthorizationClient`** (Play Services keeps the refresh token; the app
  gets 1-hour access tokens, cached automatically; nothing to store in localStorage or Keystore).
  Capacitor wrappers: `@capawesome/capacitor-google-sign-in` (2026-07-08 docs), `@capgo/capacitor-social-login`.
- Preview budget: a 1600 px JPEG at q80 is realistically **300-500 KB**, so a 200 MB cap is ~570
  photos and "a few thousand" previews is ~1 GB (the whole Supabase free tier). Use 1280-1600 px at
  q0.7 or WebP (~150-250 KB). Canvas/`createImageBitmap` auto-apply EXIF orientation (Chrome 81+) and
  strip all EXIF; read GPS/date once with `exifr` into the Supabase row instead.

**Storage targets.**

| Target | Free | Ops/verification | Fit for originals |
|---|---|---|---|
| Google Drive `drive.file` | 15 GB shared | none; publish unverified | **Best**: folders per species, user-visible, appProperties, trashed/404 detection |
| Google Photos Library | 15 GB shared | verification required; 7-day Testing expiry | Poor: app-only album, 60-min URLs, 10k/day, sensitive scope |
| Cloudflare R2 | 10 GB, egress free | tiny signer (Edge Function/Worker) | Good second target; ~$0.15/mo for 20 GB |
| Backblaze B2 | 10 GB, egress 3x stored | same pattern | Similar; cheapest at scale ($6.95/TB) |
| Supabase Storage | 1 GB, 50 MB/file | already integrated | Previews only; Pro is $25/mo |
| Immich self-hosted | free software | server >=6 GB RAM | Only if a home server already exists |
| Phone gallery only | free | none | Fragile: picker grants are temporary, lost on phone change |

**Top links.**
1. https://developers.google.com/photos/support/updates (2025-08-28)
2. https://developers.google.com/workspace/drive/api/guides/api-specific-auth
3. https://support.google.com/cloud/answer/15549945 (Manage App Audience)
4. https://developers.google.com/identity/protocols/oauth2/native-app (2026-09-14)
5. https://developer.android.com/identity/authorization (2025-10-27)

---

# Detailed findings

## 1. Google Photos Library API in 2026

### 1.1 What changed on March 31 / April 1, 2025 (confirmed, primary source)

Source: https://developers.google.com/photos/support/updates (last updated 2025-08-28) and
https://developers.google.com/photos/support/release-notes (entry "April 1, 2025"; no 2026 entries).
Original announcement: https://developers.googleblog.com/en/google-photos-picker-api-launch-and-library-api-updates/ (2024-09-16).

- **Scopes removed** (calls relying only on them return `403 PERMISSION_DENIED`):
  `photoslibrary`, `photoslibrary.readonly`, `photoslibrary.sharing`.
- **Methods now operate only on content your app created:**
  `albums.create`, `mediaItems.batchCreate`, `albums.get`, `albums.list`, `mediaItems.batchGet`,
  `mediaItems.get`, `mediaItems.list`, `mediaItems.search`, `albums.addEnrichment`,
  `albums.batchAddMediaItems`, `albums.batchRemoveMediaItems`.
- **Removed entirely:** `albums.share`, `albums.unshare`, `sharedAlbums.*`.
- New "Photos API User Data and Developer Policy" replaced the Acceptable Use Policy on 2025-04-01
  (https://developers.google.com/photos/support/api-policy, last updated 2025-08-28). It forbids using
  the API to "store or serve media ... not of a personal nature" or as a CDN; personal field photos are fine.
- **2026 changes:** none in the release notes as of 2026-09-15.

### 1.2 Current scopes (https://developers.google.com/photos/overview/authorization, fetched 2026-09-15)

| Scope | Allows |
|---|---|
| `photoslibrary.appendonly` | upload bytes, create media items, create albums, add enrichments (write-only) |
| `photoslibrary.readonly.appcreateddata` | read app-created media items and albums (recommended alongside appendonly) |
| `photoslibrary.edit.appcreateddata` | edit app-created content (titles, descriptions, album organisation) |
| `photospicker.mediaitems.readonly` | Picker API: create/get/delete sessions, list picked items |

The same page: "If your application accesses the Google Photos APIs, it **must pass the OAuth
verification review**." I could not find a Google page that literally prints "Sensitive" next to the
Photos scopes (the label only shows in the Cloud Console scope table), so the classification
"sensitive" is **UNVERIFIED by document**, but the verification requirement itself is stated by Google and
is what matters (see section 3).

### 1.3 Can the app do what the Herbier design wants? (Library API)

| Need | Answer | Source |
|---|---|---|
| Create album "Herbier" and upload into it | Yes with `appendonly`. Items always land in the library first, then can be added to an album **created by the app** (`albums.batchAddMediaItems`). | https://developers.google.com/photos/library/guides/upload-media (fetched 2026-09-15) |
| Upload limits | photos <=200 MB (suggested <50 MB), videos <=20 GB; upload token valid 1 day. | same |
| Original quality? | Yes: "All uploads are stored at original quality" (no "storage saver" option through the API). | same, and https://developers.google.com/photos/overview/api-limits-quotas |
| Counts against Google storage quota? | **Yes.** Uploads count toward the user's Google Account storage (the docs ask you to warn users once uploads exceed 25 MB per user). The 15 GB free quota is shared by Gmail, Drive and Photos. | quotas page above; https://support.google.com/mail/answer/9312312 (fetched 2026-09-15) |
| List app-created items later | Yes: `mediaItems.list` / `mediaItems.search` (album filter) with `readonly.appcreateddata`; listing "excludes archived and deleted items". Media item IDs are permanent. | https://developers.google.com/photos/library/guides/list, https://developers.google.com/photos/library/guides/access-media-items |
| Thumbnails | Only via `baseUrl` + `=w1600-h1600` etc.; **baseUrl expires after 60 min** (sooner if the user revokes). You must call `mediaItems.get`/`batchGet` to get fresh URLs; each media-bytes fetch counts against the media-bytes quota. | access-media-items guide |
| Detect user deletion | Deleted items disappear from list/search results. For `mediaItems.get` on a deleted app-created item I found no documented error code; expect NOT_FOUND/404 (**UNVERIFIED**: infer by testing). | list guide |
| Delete from the API | No delete method exists for media items; `edit.appcreateddata` only lets you re-organise. "Never delete originals" is therefore enforced by the API itself. | authorization page |

### 1.4 Quotas (https://developers.google.com/photos/overview/api-limits-quotas, fetched 2026-09-15)

- **Library API: 10,000 requests / project / day** (uploads, listing, filtering) and **75,000 media-bytes
  requests / project / day** (loading from baseUrl). Exceeding -> HTTP 429. Increases only via the
  "partner program" (aimed at large consumer apps), not self-service.
- **Picker API: 100,000 requests / minute / project** and **1,000,000 media-bytes requests / minute / project**.
- For one user, 10k/day is plenty for uploads, but note that every preview refresh after a
  60-minute URL expiry is a `mediaItems.get` (1 request) + a bytes fetch.

---

## 2. Google Photos Picker API ("pick from Google Photos")

Sources: https://developers.google.com/photos/picker/guides/get-started-picker (last updated 2025-10-06),
https://developers.google.com/photos/picker/guides/sessions (2025-10-06),
https://developers.google.com/photos/picker/guides/media-items (fetched 2026-09-15),
https://developers.google.com/photos/picker/reference/rest/v1/sessions (fetched 2026-09-15).

- Flow: get an access token with `photospicker.mediaitems.readonly` -> `sessions.create` -> open
  `pickerUri` (it "will securely open their Google Photos app"; QR code is the alternative; cannot be
  iframed) -> poll `sessions.get` using `pollingConfig.pollInterval`/`timeoutIn` until
  `mediaItemsSet` -> `mediaItems.list?sessionId=` -> use `mediaFile.baseUrl` -> `sessions.delete`.
- Session has an `expireTime` ("Time when access to this session (and its picked media items) will
  expire"); the default duration is not documented (**UNVERIFIED**).
- `baseUrl` "remain active for 60 minutes"; `=d` downloads the bytes "retaining all the Exif metadata
  except the location metadata" (so GPS is stripped on download); `=wN-hN` gives a resized copy.
- **Persistence:** you get an `id` per picked item, but after the session expires there is no API to
  turn that id back into bytes: the Library API's `mediaItems.get` now only serves **app-created**
  items, and the Picker has no get-by-id outside a session. So the design must **download the bytes
  during the session** (full `=d` for the original, `=w1600` for the preview) and either re-upload them
  to the app's own storage or just keep the local copies. Storing the Picker media-item id is only useful
  as a de-dup key.
- Scope is a Google Photos scope -> same OAuth verification requirement as the Library API (section 3).

---

## 3. Google Drive API for the same purpose

### 3.1 Scopes and sensitivity (https://developers.google.com/workspace/drive/api/guides/api-specific-auth, fetched 2026-09-15)

| Scope | Class | Notes |
|---|---|---|
| `drive.file` | **Non-sensitive** | "Create new Drive files, or modify existing files, that you open with an app or that the user shares with an app." App can only see files it created or the user picked. |
| `drive.appdata` / `drive.appfolder` | Non-sensitive | Hidden app-config folder; files are not visible to the user in Drive (unsuitable: design wants user-visible folder). |
| `drive` | **Restricted** | Full Drive; requires restricted-scope verification + annual re-verification. |
| `drive.readonly`, `drive.metadata(.readonly)` | Restricted | same |

Google's help page (https://support.google.com/cloud/answer/9110914, fetched 2026-09-15): apps using only
non-sensitive scopes "are not required to complete verification"; brand verification is an optional
lighter step only if you want your logo/name on the consent screen. See also
https://developers.google.com/drive/about-auth: drive.file grants per-file access to files "created by the
app", "opened via Google Picker" or "shared with the app", per user.

Practical consequence for one file per photo: `files.create` (multipart or resumable) with
`parents: [speciesFolderId]`. Files are ordinary Drive files: visible in the user's Drive, count
against the shared 15 GB, can be moved/renamed/deleted by the user. The app keeps access to files it
created as long as the OAuth grant stands (access is tied to the OAuth client/project, so a re-install on
a new phone with the same client ID sees the same files; **UNVERIFIED** beyond the scope definition,
but this is how drive.file is designed and widely used).

### 3.2 Quotas (https://developers.google.com/workspace/drive/api/guides/limits, last updated 2026-09-11)

New unit model "as of May 1, 2026": **1,000,000 quota units / minute / project**, **325,000 / minute /
user**, 400,000,000 units/day before charges. Costs: read 5, list 100, download 200, edit 50 units.
Uploads: 750 GB/day, 5 TB max file. Self-service quota increases exist. For one user this is
effectively unlimited.

### 3.3 Thumbnails and downloads

Source: https://developers.google.com/workspace/drive/api/reference/rest/v3/files (fetched 2026-09-15),
https://developers.google.com/workspace/drive/api/guides/manage-downloads (last updated 2026-09-03).

- `thumbnailLink`: "A short-lived link to the file's thumbnail... Typically lasts on the order of
  hours." Must be fetched with a credentialed request unless the file is public. It ends in `=s220`;
  replacing with `=s1600` returns a larger rendition (community-documented trick, e.g.
  https://community.latenode.com/t/how-to-get-better-quality-thumbnails-from-google-drive-api/34219;
  **UNVERIFIED** by Google docs but long-standing). Cost: one `files.get?fields=thumbnailLink`
  (5 units) whenever the cached link expires.
- Full bytes: `files.get?alt=media` (200 units). No server-side resize parameter; `webContentLink`
  is a browser download link, not an API-friendly resized image.
- `imageMediaMetadata` (location, rotation, time) is populated by Drive from EXIF, and `appProperties`
  lets you tag a file with your own plant-id/hash, private to the app.
- Photos-side comparison: Drive thumbnails last hours, Photos baseUrls last 60 min; both need re-fetch.
  Since Herbier keeps its own local preview anyway, neither matters much day to day.

### 3.4 Detecting user-side deletion

Source: https://developers.google.com/workspace/drive/api/guides/delete (fetched 2026-09-15) and the
files reference. Trash: `files.get?fields=trashed,explicitlyTrashed` returns `trashed: true`
(auto-purged after 30 days). Permanent delete (or the user removing the app's access): `files.get`
returns 404 `notFound`. Note that 404 is also what you get for "no access", so treat 404 as
"original missing" without trying to distinguish. The Drive `changes` API (start page token,
`changes.list`) gives incremental sync of moves/renames/trash for all files the app can see.

### 3.5 Google Drive Picker

Sources: https://developers.google.com/workspace/drive/picker/guides/overview (last updated 2026-09-14),
https://developers.google.com/workspace/drive/picker/guides/desktop-mobile-picker (2026-09-14).

- Web Picker: JavaScript, needs an API key + OAuth token; works with `drive.file` and grants the app
  access to whatever the user picks. It "can no longer be displayed within an embedded webview".
- New **desktop/mobile Picker**: driven by OAuth URL params (`prompt=consent`, `trigger_onepick=true`,
  optional `allow_multiple`, `mimetypes`, `allow_folder_selection`), opens in the system browser, returns
  `picked_file_ids` + an auth code; **Android is explicitly supported via `AuthorizationRequest` with the
  `PICKER_OAUTH_TRIGGER` resource parameter**, and "only the drive.file scope is permitted". This is the
  right way to do "pick existing photos from Drive" from Herbier later.

### 3.6 Drive vs Photos: fit for Herbier

| Criterion | Google Photos Library | Google Drive (`drive.file`) |
|---|---|---|
| Verification for a personal app | Required (Google states it) -> Testing mode 7-day re-consent or unverified screen | Not required; publish "In production" |
| Upload original, count against 15 GB | Yes / yes | Yes / yes |
| Album/folder per species | Only one flat album membership; app-created albums only | Real folders, user can reorganise |
| Thumbnails | baseUrl 60 min, needs `mediaItems.get` | thumbnailLink ~hours, needs `files.get` |
| Extra metadata | description only | `appProperties`, `description`, `imageMediaMetadata` |
| Deletion by user | item vanishes from list | `trashed` flag, then 404 |
| Delete from API | impossible (good) | possible; just don't call it |
| Picker for existing photos | Picker API, 60-min URLs, must download during session | Desktop/mobile Picker, permanent file access |
| Daily quota | 10,000 req + 75,000 bytes req | effectively unlimited |
| Photos app niceties (AI search, "memories") | yes | no (photos in Drive are not in the Photos library) |

Drive is the better fit for the app; Photos is the nicer consumer experience for the human. Because the
originals are also in the phone's camera roll, the user still gets them in Google Photos via the normal
Photos backup, without any API.

---

## 4. OAuth consent screen, verification, token lifetime (personal Gmail account)

Primary sources:
- https://support.google.com/cloud/answer/15549945 "Manage App Audience" (fetched 2026-09-15)
- https://support.google.com/cloud/answer/7454865 "Unverified apps" (fetched 2026-09-15)
- https://support.google.com/cloud/answer/9110914 "OAuth App Verification" (fetched 2026-09-15)
- https://developers.google.com/identity/protocols/oauth2 "Refresh token expiration" (last updated 2026-05-26)
- Secondary: https://www.unipile.com/google-oauth-refresh-token/ (2026),
  https://dev.to/just_a_side_project/my-oauth-tokens-kept-expiring-every-7-days-and-the-reason-was-a-dropdown-labeled-testing-47ni,
  https://tech.queenofsandiego.com/posts/2026-05-06-1820.html (2026-05-06)

Rules as of 2026:

1. **Testing status (External user type):** max 100 test users; a warning screen before consent;
   "authorizations by a test user will expire seven days from the time of consent" and refresh tokens
   expire with them. Google's OAuth doc: the 7-day expiry applies "unless the only OAuth scopes requested
   are a subset of name, email address, and user profile". **So it applies to `drive.file` too, and to
   every Photos scope, in Testing.** It is not tied to sensitivity.
2. **In production, non-sensitive scopes only (`drive.file`, `drive.appdata`, openid/email/profile):**
   no verification needed, no unverified-app screen, no 7-day expiry, no 100-user cap. Without brand
   verification the consent screen shows the project name/domain rather than a logo. (Google 9110914;
   confirmed by several 2025-2026 write-ups, e.g. https://www.gmass.co/blog/five-annoying-issues-google-oauth-scope-verification/.)
3. **In production, sensitive scopes (all Photos scopes) without verification:** the "Google hasn't
   verified this app" screen appears, and the project is capped at **100 new users in total, for its
   lifetime** (cannot be reset). One developer-user fits in that cap, and the tokens are then normal
   long-lived ones (the 7-day rule is a Testing-status rule). The advanced -> "Go to app (unsafe)" click
   is needed at each consent. Whether Google will let a Photos-scope app be *published* unverified, or
   force it back to Testing, I could not confirm from documentation (**UNVERIFIED**; the Unverified-apps
   page only describes the screen and the cap).
4. **Restricted scopes (`drive`, `drive.readonly`) unverified:** not usable for a user-facing app;
   avoid.
5. **Other refresh-token limits:** 100 refresh tokens per Google Account per client ID (the OAuth page
   now says 100; older articles say 50); tokens die after 6 months of non-use, on revocation, or on
   password change if Gmail scopes are involved.
6. **Internal user type:** requires the project to be inside a Google Workspace organisation
   (Business Starter is $7/user/month annual, $8.40 monthly, per
   https://www.name.com/blog/google-workspace-pricing, 2026). Internal apps skip the test-user cap, the
   7-day expiry and verification; for Drive/Gmail-type restricted APIs the Workspace admin must also
   allow the app. For $84/year it buys a clean solution to the Photos-scope problem, but it is not
   needed for `drive.file`.

**Practical path for one developer-user with a personal Gmail:** create the OAuth consent screen as
External, add only `drive.file` (+ openid/email if you want the account e-mail), fill in the mandatory
privacy-policy/homepage URLs (a static page is fine), click **Publish**. Done; no review, no expiry.
If you later add a Photos scope, keep it in a *separate* OAuth client/project in Testing so it does not
drag the Drive client into the unverified state.

---

## 5. Doing it from an Android WebView app

### 5.1 Google blocks OAuth in embedded WebViews

Google's "Use secure browsers" policy returns `403 disallowed_useragent` for authorization requests
from `android.webkit.WebView`/`WKWebView`; enforced since 2023
(https://developers.googleblog.com/upcoming-security-changes-to-googles-oauth-20-authorization-endpoint-in-embedded-webviews/,
https://auth0.com/blog/google-blocks-oauth-requests-from-embedded-browsers/). The Drive web Picker
likewise "can no longer be displayed within an embedded webview" (overview page, 2026-09-14).

### 5.2 Which flow is still supported on Android (important 2026 detail)

https://developers.google.com/identity/protocols/oauth2/native-app (last updated 2026-09-14) now says:
"Custom URI schemes are no longer supported on Android and Chrome apps" and "The loopback IP address
redirect option is DEPRECATED for Android, Chrome app and iOS OAuth client types." So a classic
AppAuth/Custom-Tabs PKCE flow against an *Android* OAuth client (redirect
`com.googleusercontent.apps.<id>:/oauth2redirect`) is no longer a supported configuration. The
supported Android path is:

- **Credential Manager** (`androidx.credentials`, "Sign in with Google") for authentication, then
  **`AuthorizationClient.authorize()`** (Play Services `com.google.android.gms.auth.api.identity`) with
  `requestedScopes = [DriveScopes.DRIVE_FILE]`; if `hasResolution()` launch the PendingIntent once,
  afterwards `authorize()` silently returns a fresh **1-hour access token**, cached and auto-expired by
  Play Services. `getServerAuthCode()` (with `requestOfflineAccess(serverClientId)`) is only for a
  backend; Google explicitly says do **not** keep refresh tokens on device.
  (https://developer.android.com/identity/authorization, last updated 2025-10-27;
  https://android-developers.googleblog.com/2024/09/streamlining-android-authentication-credential-manager-replaces-legacy-apis.html.)
- Requirements: Google Play services on the device (fine for a sideloaded APK); an **Android OAuth client**
  (package name + SHA-1 of *your* signing key, so sideloaded builds must use a stable keystore) and a
  **Web client** whose ID is passed as `serverClientId`.
- Consequence for token storage: **nothing to store in the app.** No refresh token ever reaches JS;
  `localStorage` only holds the 1-hour access token at most (or better, ask the plugin each time). If you
  still need to persist a secret (e.g. an R2 presigned-URL signer key), use a Keystore-backed plugin
  (`@aparajita/capacitor-secure-storage`, `capacitor-secure-storage-plugin` v7 Feb 2025, Capawesome
  Secure Preferences). `EncryptedSharedPreferences` is deprecated in Jetpack Security; current advice
  is DataStore + Tink/Keystore, which those plugins wrap
  (https://medium.com/@n20/encryptedsharedpreferences-is-deprecated-what-should-android-developers-use-now-7476140e8347;
  https://capgo.app/blog/secure-token-storage-best-practices-for-mobile-developers/).
- In Testing status, the 7-day grant expiry means `authorize()` will again return `hasResolution()==true`
  after a week and the user re-taps consent (inference from the audience rules; **UNVERIFIED** as a
  documented statement, but it follows directly).

### 5.3 Plugins (Capacitor)

- **`@capawesome/capacitor-google-sign-in`** (docs dated 2026-07-08, open source, Capacitor >= 8):
  Android uses Credential Manager + AuthorizationClient; `initialize({ scopes: [...] })` enables
  `accessToken` and `serverAuthCode` in the result. https://capawesome.io/docs/sdks/capacitor/google-sign-in/
- **`@capgo/capacitor-social-login`** (MPL-2.0): Credential Manager on Android; scopes; `offline` mode
  returning `serverAuthCode`; `refresh()` and `getAuthorizationCode()` helpers.
  https://github.com/Cap-go/capacitor-social-login
- `@codetrix-studio/capacitor-google-auth` is the legacy GoogleSignIn-based plugin; avoid for new work.
- Generic OAuth plugins (`@byteowls/capacitor-oauth2`, Capawesome OAuth, `capacitor-oidc`) use Custom
  Tabs/Auth Tab + PKCE and are fine for other IdPs, but see 5.2: Google no longer supports the custom
  scheme redirect on Android, so they are not the right tool for Google scopes.
- Cordova: `cordova-plugin-googleplus` is effectively unmaintained; if you stay on Cordova you would
  write a small native plugin around AuthorizationClient (a few dozen lines of Kotlin).
- **Alternative via Supabase Auth**: `supabase.auth.signInWithOAuth({provider:'google', options:{scopes:'https://www.googleapis.com/auth/drive.file', queryParams:{access_type:'offline', prompt:'consent'}, redirectTo:'herbier://auth'}})`
  runs the OAuth in the system browser through the Supabase https callback (a Web OAuth client, so the
  Android-redirect limitation does not apply) and returns `provider_token` / `provider_refresh_token`
  once; Supabase does not persist the provider refresh token, the app must (Keystore plugin).
  https://supabase.com/docs/guides/auth/social-login/auth-google (fetched 2026-09-15). This works but
  puts a Google refresh token on the device, against Google's Android guidance; Credential Manager +
  AuthorizationClient is cleaner.

### 5.4 Uploading from the WebView

Google APIs generally serve CORS headers for `Authorization: Bearer` requests, but I did not find a
statement covering `photoslibrary.googleapis.com/v1/uploads` (**UNVERIFIED**). Drive
`upload/drive/v3/files?uploadType=multipart|resumable` is routinely called from browser JS. If CORS
bites, Capacitor's `CapacitorHttp` (`plugins.CapacitorHttp.enabled=true`) patches `fetch`/XHR to native
HTTP; binary bodies need base64 or the `@capacitor/file-transfer` plugin
(https://capacitorjs.com/docs/apis/http, fetched 2026-09-15).

---

## 6. Alternatives for originals, and the compressed-preview budget

### 6.1 Object storage

| Option | Free | Paid | Notes |
|---|---|---|---|
| **Cloudflare R2** | 10 GB-month, 1M Class A + 10M Class B ops/month, **egress free** | $0.015/GB-month, $4.50/M Class A, $0.36/M Class B | S3 API; upload from the phone via presigned URLs signed by a Supabase Edge Function or a tiny Worker. https://developers.cloudflare.com/r2/pricing/ (fetched 2026-09-15) |
| **Backblaze B2** | first 10 GB always free; egress free up to 3x stored/month and free via Cloudflare CDN | $6.95/TB-month; $0.01/GB egress beyond 3x | S3-compatible; same presigned-URL pattern. https://www.backblaze.com/cloud-storage/pricing (fetched 2026-09-15) |
| **Supabase Storage** | 1 GB, 5 GB cached egress, 50 MB max file | Pro $25/mo: 100 GB incl., then $0.0213/GB; egress 250 GB incl. then $0.03/GB | Already integrated (auth, RLS, image transforms on Pro). Pro is overkill for one user unless already paid. https://supabase.com/pricing (fetched 2026-09-15) |
| **Google account (Photos or Drive)** | 15 GB shared with Gmail/Drive | Google One 100 GB ~ $1.99/mo | The user already has it; zero infra. |
| **Immich (self-hosted)** | free software | needs a box: >=6 GB RAM recommended, disk = library + 10-20% | Full API + Android app with auto backup; only worth it if you already run a home server. https://ossalt.com/guides/how-to-self-host-immich-2026 (2026) |
| **Phone gallery only (MediaStore/Photo Picker)** | free | - | Android Photo Picker grants are temporary (until reboot/app stop) unless `takePersistableUriPermission`, capped at 5,000 grants; SAF `ACTION_OPEN_DOCUMENT` URIs are persistable but provider-dependent. Lost on phone change or gallery deletion. https://developer.android.com/training/data-storage/shared/photo-picker (fetched 2026-09-15) |

Sizing: "a few thousand" originals x ~5.5 MB ~ 11-22 GB. That exceeds the free 10 GB of R2/B2 and most
of the 15 GB Google quota, but costs ~$0.03-0.18/month on R2 or ~$0.08/month on B2 beyond the free
tier; Google One is $1.99/month. All three are "near-free".

### 6.2 Is "app-only compressed, capped at 200 MB in Supabase Storage" realistic?

- Empirical size guides: a 12 MP JPEG at q80 ~ 700 KB; 1920x1080 at q80 ~ 590 KB; 1600 px long edge at
  q80 typically **300-500 KB** for detailed photographs (https://minipx.com/blog/jpeg-quality-settings-guide/,
  https://imganva.com/jpeg-quality-vs-file-size-chart/, 2025-2026). Plant/foliage photos are high-frequency
  and sit at the top of that range. The design's 200-300 KB assumes ~q70 or ~1280 px.
- Budget at 350 KB/preview: 200 MB ~ **570 photos**; 1 GB (Supabase free) ~ **2,900 photos**. At
  200 KB: 1,000 and 5,000 respectively.
- Levers: 1280-1440 px long edge, quality 0.7, or `image/webp` from `canvas.toBlob` (Chrome WebView
  supports it; typically 25-35% smaller than JPEG at similar quality). Keep the local on-device copy at
  1600 px and upload a smaller one to Supabase if the cap matters.

### 6.3 Client-side compression in a WebView

- `createImageBitmap(file, {imageOrientation:'from-image'})` (default) and `<img>` decoding honour EXIF
  orientation since Chrome 81 / Firefox 77 (CSS `image-orientation: from-image` is the initial value),
  so drawing to a canvas produces an upright bitmap; the exported JPEG has **no EXIF at all**
  (orientation tag gone, which is what you want, but GPS/date gone too).
  https://developer.mozilla.org/en-US/docs/Web/API/CreateImageBitmap, https://paul.kinlan.me/correct-image-orientation-for-images-chrome-81/.
- `browser-image-compression` (v2.0.2; https://github.com/Donaldcwl/browser-image-compression) handles
  `maxWidthOrHeight`, `maxSizeMB`, `initialQuality`, Web Worker, and `preserveExif: true` copies the
  original JPEG's EXIF (APP1) segment into the output; whether GPS survives is not stated in the README
  (**UNVERIFIED**, but it copies the whole APP1 block so GPS IFD should survive). Caveat: when EXIF is
  copied verbatim, the orientation tag is copied too while the pixels are already rotated, so either
  rewrite Orientation=1 (e.g. with `piexifjs`/`exifr` + a small writer) or accept double rotation risk in
  some viewers. Recommended: read EXIF (GPS, DateTimeOriginal) once with `exifr` into the Supabase row,
  write previews without EXIF.
- Capacitor `@capacitor/camera` returns `exif` on `getPhoto`, has `correctOrientation`, `width/height`
  and `quality` (native resize, cheaper than canvas), and `pickImages` uses the Android Photo Picker on
  Android 11+ (https://capacitorjs.com/docs/apis/camera, fetched 2026-09-15). Keep the original bytes
  (`resultType: 'uri'`, no `width/height`) for the original upload and let native code produce the preview.

---

## 7. Recommendation and phasing

**Phase 1 (build now):**
1. Originals -> **Google Drive, `drive.file`**, folder `Herbier/<species>/`, one file per photo with
   `appProperties: {herbier_photo_id, sha256}`; store `fileId`, `md5Checksum`, `thumbnailLink` (+ fetch
   time) in Supabase. OAuth client External + In production, no verification.
2. Auth on Android: Credential Manager + AuthorizationClient through `@capawesome/capacitor-google-sign-in`
   (or Cap-go social-login); request `drive.file` only; ask for a fresh access token before each sync.
   No refresh token on device.
3. Preview -> local filesystem (1600 px) + Supabase Storage (1280-1600 px, q0.7 or WebP, target
   ~200 KB) with EXIF stripped and GPS/date stored in the row.
4. "Original missing" = Drive `files.get` -> `trashed:true` or 404; never call `files.delete`.

**Phase 2 (nice to have):** "pick from Drive" using the desktop/mobile Picker (`PICKER_OAUTH_TRIGGER`,
drive.file). R2 as a second target if the Google quota fills (presigned URLs from a Supabase Edge Function).

**Defer / probably never:** Google Photos Library upload and Picker (verification requirement, 7-day
Testing expiry or unverified-app screen, 10k/day quota, 60-minute URLs, and the picked-item bytes must
be captured during the session anyway). The user still gets photos in Google Photos through the normal
camera-roll backup.

---

## 8. Source list (all accessed 2026-09-15)

Google Photos
- https://developers.google.com/photos/support/updates (updated 2025-08-28)
- https://developers.google.com/photos/support/release-notes (last entry 2025-04-01)
- https://developers.googleblog.com/en/google-photos-picker-api-launch-and-library-api-updates/ (2024-09-16)
- https://developers.google.com/photos/overview/authorization
- https://developers.google.com/photos/overview/api-limits-quotas
- https://developers.google.com/photos/library/guides/upload-media
- https://developers.google.com/photos/library/guides/list
- https://developers.google.com/photos/library/guides/access-media-items
- https://developers.google.com/photos/support/api-policy (updated 2025-08-28)
- https://developers.google.com/photos/picker/guides/get-started-picker (updated 2025-10-06)
- https://developers.google.com/photos/picker/guides/sessions (updated 2025-10-06)
- https://developers.google.com/photos/picker/guides/media-items
- https://developers.google.com/photos/picker/reference/rest/v1/sessions
- https://memorykpr.com/blog/google-photos-api-deprecation-what-it-means-for-third-party-apps-and-how-to-prepare/

Google Drive
- https://developers.google.com/workspace/drive/api/guides/api-specific-auth
- https://developers.google.com/drive/about-auth
- https://developers.google.com/workspace/drive/api/guides/limits (updated 2026-09-11)
- https://developers.google.com/workspace/drive/api/reference/rest/v3/files
- https://developers.google.com/workspace/drive/api/guides/manage-downloads (updated 2026-09-03)
- https://developers.google.com/workspace/drive/api/guides/delete
- https://developers.google.com/workspace/drive/picker/guides/overview (updated 2026-09-14)
- https://developers.google.com/workspace/drive/picker/guides/desktop-mobile-picker (updated 2026-09-14)
- https://community.latenode.com/t/how-to-get-better-quality-thumbnails-from-google-drive-api/34219
- https://www.tutorialpedia.org/blog/file-not-found-error-google-drive-api/

OAuth / verification
- https://support.google.com/cloud/answer/15549945 (Manage App Audience)
- https://support.google.com/cloud/answer/7454865 (Unverified apps)
- https://support.google.com/cloud/answer/9110914 (OAuth App Verification)
- https://developers.google.com/identity/protocols/oauth2 (updated 2026-05-26)
- https://developers.google.com/identity/protocols/oauth2/native-app (updated 2026-09-14)
- https://developers.googleblog.com/upcoming-security-changes-to-googles-oauth-20-authorization-endpoint-in-embedded-webviews/
- https://auth0.com/blog/google-blocks-oauth-requests-from-embedded-browsers/
- https://www.unipile.com/google-oauth-refresh-token/ (2026)
- https://dev.to/just_a_side_project/my-oauth-tokens-kept-expiring-every-7-days-and-the-reason-was-a-dropdown-labeled-testing-47ni
- https://tech.queenofsandiego.com/posts/2026-05-06-1820.html (2026-05-06)
- https://www.gmass.co/blog/five-annoying-issues-google-oauth-scope-verification/
- https://www.name.com/blog/google-workspace-pricing (2026)

Android / Capacitor
- https://developer.android.com/identity/authorization (updated 2025-10-27)
- https://android-developers.googleblog.com/2024/09/streamlining-android-authentication-credential-manager-replaces-legacy-apis.html
- https://capawesome.io/docs/sdks/capacitor/google-sign-in/ (2026-07-08)
- https://github.com/Cap-go/capacitor-social-login
- https://capacitorjs.com/docs/apis/http
- https://capacitorjs.com/docs/apis/camera
- https://supabase.com/docs/guides/auth/social-login/auth-google
- https://github.com/aparajita/capacitor-secure-storage
- https://medium.com/@n20/encryptedsharedpreferences-is-deprecated-what-should-android-developers-use-now-7476140e8347
- https://capgo.app/blog/secure-token-storage-best-practices-for-mobile-developers/
- https://developer.android.com/training/data-storage/shared/photo-picker

Storage alternatives / compression
- https://developers.cloudflare.com/r2/pricing/
- https://www.backblaze.com/cloud-storage/pricing
- https://supabase.com/pricing
- https://support.google.com/mail/answer/9312312 (15 GB shared)
- https://ossalt.com/guides/how-to-self-host-immich-2026
- https://github.com/Donaldcwl/browser-image-compression
- https://developer.mozilla.org/en-US/docs/Web/API/CreateImageBitmap
- https://paul.kinlan.me/correct-image-orientation-for-images-chrome-81/
- https://minipx.com/blog/jpeg-quality-settings-guide/
- https://imganva.com/jpeg-quality-vs-file-size-chart/
