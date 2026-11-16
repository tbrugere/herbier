# Pl@ntNet from the Capacitor WebView (M9.63 spike)

Run 2026-11-16. Desktop: `curl` from a Mac, through
`scripts/record-plantnet-fixtures.sh` and by hand on the free route
(`GET /v2/projects`). Emulator: the shared AVD `herbier` (API 35, Android System WebView
124.0.6367.219), dev build,
page `#dev/identify` (`app/ui/dev/identify_check.ml`), origin
`https://localhost`. The key is the user's own (my.plantnet.org, free plan,
500 identifications a day), read from his `.envrc`, never written anywhere.

The run had two phases: first with the key **not exposed** (the user then
ticked « expose my API key » and added `https://localhost` to its authorized
domains), then with the key **exposed**, when the recorder recorded the
fixtures. Pl@ntNet's answers say `"version": "2026-03-20 (7.5)"`.

## Question

Plan item 63: can the WebView call Pl@ntNet's identify API with the user's
key (architecture §12, option C), and what do the answers hold that 64–69
rely on? Pl@ntNet's documentation says a key used from a browser-side app,
which the WebView is (its `fetch` sends `Origin: https://localhost`), must be
exposed with its origin among the "Authorized domains", and that an exposed
key refuses requests without `Origin` unless they come from an "Authorized
IP".

## What ran

| Request | From | Origin | Answer |
|---|---|---|---|
| `GET /v2/projects?lang=fr`, the key (not exposed) | curl | `https://localhost` | 403 `{"message":"CORS error: Origin not allowed"}`, `access-control-allow-origin: https://localhost`, 0.07–0.17 s |
| the same | curl | `http://localhost`, `https://localhost:8443`, `http://127.0.0.1`, `capacitor://localhost`, `https://example.org`, `https://bruge.re`, `null` | 403, the same body, each |
| the same | curl | none | 200 (the floras), 0.19 s |
| the same | `#dev/identify` « Flores (gratuit) » | `https://localhost` (the WebView's) | 403 in 810 ms, body `{"message":"CORS error: Origin not allowed"}` read by `fetch` |
| `POST /v2/identify/all`, key `invalid-key-for-fixtures`, `image_1` `auto` | recorder | `https://localhost` | 401 `{"statusCode":401,"error":"Unauthorized","message":"Bad token",…}`, 0.19 s → `plantnet_identify_invalid_key_401.json` |
| `GET /v2/projects?lang=fr`, the key (**exposed**) | recorder | `https://localhost` | 200, 0.08 s → `plantnet_projects_fr_200.json` |
| the same | recorder | `https://example.org` | 403 `{"message":"CORS error: Origin not allowed"}`, 0.07 s → `plantnet_projects_origin_refused_403.json` |
| the same | recorder | none | 403 `{"message":"error: remote IP not allowed"}`, 0.06 s → `plantnet_projects_no_origin_403.json` |
| `POST /v2/identify/all`, `image_1` `auto` | recorder | `https://localhost` | 200, 0.58 s → `plantnet_identify_one_auto_200.json` |
| `image_1` `flower`, `image_2` `leaf` | recorder | `https://localhost` | 200, 0.67 s → `plantnet_identify_two_flower_leaf_200.json` |
| grey 800 × 800 JPEG `auto` | recorder | `https://localhost` | 404 `{"statusCode":404,"error":"Not Found","message":"Species not found"}`, 0.49 s → `plantnet_identify_not_plant_404.json` |
| the same, `&no-reject=true` | recorder | `https://localhost` | 404, the same body, 0.27 s → `plantnet_identify_not_plant_no_reject_404.json` |

The identify query is always
`include-related-images=true&lang=fr&nb-results=5&api-key=<key>`.

## Answers

The numbers follow plan item 63's "recorded here" list. The `jq` expressions
run on `test/fixtures/`.

1. **The key, not exposed, from the WebView's origin: refused.** Every
   `Origin`, `https://localhost` included, gets 403
   `{"message":"CORS error: Origin not allowed"}`; the answer carries
   `access-control-allow-origin` set to the caller's origin, so a WebView
   `fetch` reads the status and the body (no opaque network error). The
   WebView itself got that 403 (« Flores », below). Without `Origin` the same
   key answers 200. So the documentation is right and 66's planned help text
   (expose the key, add `https://localhost`) stands. 64 classifies this 403
   as its own case (« clé non exposée pour l'app »), not as a network error:
   its body is the one above.
2. **The exposed key from `Origin: https://localhost`: 200**, for the floras
   and for identify: from curl (the recorder's rows above) and from the
   WebView itself (« Flores » and « 1 aperçu », below).
3. **Related images per species**
   (`jq '[.results[] | {n: (.images|length), organs: [.images[].organ]}]'`):
   one photo `auto`: 6, 6, 6, 6, 5 images for the five species, nearly all
   `flower` (one `other`); two photos `flower` + `leaf`: 6 per species
   (three `flower`, three `leaf`), except the fifth with 1 (`leaf`). So at
   most six per species, never the design's « +14 » or « 3 / 15 » (R11).
   Every `url.o`, `url.m` and `url.s` is under `https://bs.plantnet.org/image/`;
   each image has `organ`, `author`, `license`, `date`, `url` and `citation`
   (`"<author> / Pl@ntNet, <licence>"`).
4. **`gbif.id` is a JSON string** (`jq '[.results[].gbif.id | type]'`:
   `"string"` for four of five, e.g. `"3152559"`). A result can have
   `"gbif": null` (the key present, the value null): « Hibiscus spp. », a
   genus-level result, has no GBIF id and no POWO id either (`powo` is also
   null for « Hibiscus schizopetalus »).
5. **French names and family: present** on every result. `commonNames` is
   non-empty for all ten results (1 to 3 names, French with `lang=fr`, e.g.
   « Rose de Chine »); `species.family.scientificNameWithoutAuthor` is
   `"Malvaceae"` for all. `species` also has `genus`, `scientificName`,
   `scientificNameAuthorship`.
6. **`predictedOrgans`**: one element per image, `{image, filename, organ,
   score}`. With `auto`, `image_1` is predicted `flower` (0.866). With
   `flower` + `leaf`, the elements follow the organs sent (`flower` 0.866,
   `leaf` 0.804): observed, not documented (the OpenAPI schema says nothing
   of their order), so the decoder matches each `image` with the ids
   `query.images` lists in the order sent. `filename` echoes the uploaded part's file name
   (`image_1.jpeg`): the app sends `photo-<i>.jpg`, never a gallery name
   (plan 64, architecture §12).
7. **Floras** (`jq '[.[] | {id, title}]' plantnet_projects_fr_200.json`): 75
   projects, each `{id, title, description, speciesCount}` with French titles
   (« Flore mondiale », « Europe du Sud-Ouest », …). 53 are the KT regional
   floras (`k-*`, starting with `k-world-flora`), 22 are thematic or legacy
   ones (`useful`, `weeds`, `invasion`, `cevennes`, `alpes-maritimes`, …).
   **`all` is not listed**: 66 adds « Automatique » itself.
8. **Error bodies.** 401 (invalid key): above. 404 (no plant):
   `{"statusCode":404,"error":"Not Found","message":"Species not found"}`.
   With `no-reject=true` the grey square still gets the same 404: no-reject
   does not force proposals when nothing plant-like is seen. The exposed
   key's refusals: another `Origin` → 403 `{"message":"CORS error: Origin not
   allowed"}`; no `Origin` → 403 `{"message":"error: remote IP not allowed"}`
   (no authorized IP set). The 200s carry `remainingIdentificationRequests`
   in the body (499, then 498). The 429 is not recorded (it would spend the day's
   500): 64 classifies 429 by status.
9. **Time to answer.** Desktop: the free route answers in 0.06–0.19 s,
   identify with one image (450 × 600) in 0.58 s, two images in 0.67 s, the
   404s in 0.27–0.49 s. From the WebView (emulator on the Mac's Wi-Fi):
   one preview (40 KB) in 0.85 s, five previews (193 KB) in 1.26 s.
   `adb emu network speed umts` had no visible effect (five previews, 193 KB,
   in 0.54 s, which 384 kbit/s cannot carry), so the emulator gives no
   mobile-data figure: the phone on mobile data is still to measure (the
   user's check).
10. **R13**, a preview's scores against a q0.9 encode of the same original
    (« Aperçu q0.7 et q0.9 », `image_1`, 450 × 600, so the preview keeps the
    original's size): the q0.7 preview (40 KB) gives « Hibiscus rosa-sinensis »
    0.559, the q0.9 encode (74 KB) 0.439, the original as recorded 0.442; the
    four other proposals and their order barely move. On this image the
    preview does not identify worse. It says nothing about a camera photo
    scaled down to 1600 px: that check needs the phone (the user's).
    Pl@ntNet answers identical bytes from a cache (the same preview sent
    twice: the same scores, 82 ms instead of 849 ms) and still counts a
    credit.
11. **R10**, what « Authorized domains » accepts: **`https://localhost` is
    accepted**; with it listed, a request with `Origin: https://localhost`
    gets 200 and one with another `Origin` gets 403. R10's risk did not
    happen: the WebView path (option C) stands.
12. **Forged `Origin`.** The recorder's identify calls are curl calls from a
    desktop with `Origin: https://localhost`, and they got 200: anyone holding
    the key can spend the day's 500 from anywhere (the known weakness of any
    exposed key). Without `Origin` the exposed key is refused ("remote IP
    not allowed"), so only a forged `Origin` passes.

## From the WebView

First with the key not exposed (no identify credit spent):

- With the key field empty, each of the four buttons logs « pas de clé » and
  `performance.getEntriesByType('resource')` has no `my-api.plantnet.org`
  entry: nothing is sent.
- « Flores (gratuit) » with the pasted key: `projects: HTTP 403 in 810 ms,
  0 photo(s), 0 bytes sent, 44 chars answered`, body
  `{"message":"CORS error: Origin not allowed"}`: the WebView's own request
  gets the refusal curl got, and `fetch` reads it (status and body, no
  opaque `TypeError`). This answers item 1 from the WebView itself.
- The key is not in `document.body.innerText`, `localStorage` /
  `sessionStorage` or logcat (`adb logcat -d | grep -cF` = 0) after the
  request; the page's resource-timing entry and an open DevTools network log
  keep the request URL, key included, until the page reloads (dev builds
  only; the app's client never logs or shows that URL).
  Leaving the page (`#dev/photos`) and coming back: the field is empty
  (`autocomplete="off"`).
- Wi-Fi and mobile data off, « Flores »: `projects: failed (TypeError:
  Failed to fetch) after 27 ms`: Chromium's error carries no URL, so the
  failure line cannot leak the key.

Then with the key exposed (Pl@ntNet's two example images and three flipped
copies pushed to the emulator's gallery, chosen in Android's photo picker):

- « Flores (gratuit) »: `projects: HTTP 200 in 960 ms, 8902 chars
  answered`, the 75 floras.
- « 1 aperçu » (`image_1`): `one: HTTP 200 in 849 ms, 1 photo(s), 40144
  bytes sent`; `predictedOrgans` echoes `photo-1.jpg`, organ `flower`.
- « Aperçu q0.7 et q0.9 »: `q07: HTTP 200 in 82 ms` (40 144 bytes),
  `q09: HTTP 200 in 250 ms` (73 909 bytes), item 10.
- « 5 aperçus »: `five: HTTP 200 in 1259 ms, 5 photo(s), 193139 bytes
  sent`, « Hibiscus rosa-sinensis » 0.720, each photo's organ predicted.
- At `umts`: « 1 aperçu » (`image_2`) 686 ms, « 5 aperçus » 543 ms (item 9).
- `adb logcat -d` holds the key 0 times. The page's resource-timing buffer
  has one entry per request, its URL with the key.

## Credits

The recorder spent 4 of the day's 500 (one per identify fixture; the 401 of
an unknown key and the projects route cost none). The emulator checks spent
6 more (`remainingIdentificationRequests` 495 down to 490).

## Consequences for 64–69

- 64: a 403 whose body is `{"message":"CORS error: Origin not allowed"}` is
  "key not exposed for the app" (the user fixes it on my.plantnet.org), not a
  network error (what the user sees: architecture.md §12); the 401 body is `{"statusCode":401,…,"message":"Bad token"}`;
  the 404 is `"Species not found"`, with or without `no-reject`. `gbif` can
  be `null` and `gbif.id` comes as a string. Related images are under
  `https://bs.plantnet.org/`, at most six per species.
- 66: the help text (expose the key, authorize `https://localhost`) is
  needed and sufficient (items 1 and 11); `all` is not in the flora list, so
  « Automatique » is added by the app.
- 6c / 6d (R11): « +N » beyond four tiles shows at most « +2 ».
