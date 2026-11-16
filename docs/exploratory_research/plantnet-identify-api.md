# Herbier — Pl@ntNet identify API

Date of research: **2026-11-16**. Sources, all fetched that day: the API's own
OpenAPI document (`https://my-api.plantnet.org/swagger.json`, Swagger 2.0,
`info.version` **2.2.2**), its documentation as one text file
(`https://my.plantnet.org/llms-full.txt`, `Last-Modified: Tue, 03 Nov 2026`),
the pricing page (`https://my.plantnet.org/pricing`) and the terms of use
(`https://my.plantnet.org/terms_of_use`), Pl@ntNet's example repository
(`https://github.com/plantnet/my.plantnet`), `curl` probes of
`my-api.plantnet.org` without a valid key (CORS headers, error bodies), and GBIF's
species API for the ids Pl@ntNet returns. There is no Herbier key yet, so **no
identification was run**: anything that needs one is marked **UNVERIFIED** and is
the first step of plan M9 (M9.63). Earlier facts on the same API, from
2026-09-15, are in `botanical-data-sources.md` §2.1.

Why: on 2026-11-16 the user added identification through the Pl@ntNet API to
the scope, with a Claude Design tour 6 (`design_handoff_herbier/identification/`,
screens 6a–6k). This report is what plan M9 and architecture §12 rest on.

---

## Summary

- **One route does it**: `POST /v2/identify/{project}`, `multipart/form-data`,
  1 to 5 JPEG or PNG images of **one** plant, an optional organ per image (`auto`
  by default), the key as the `api-key` query parameter. It returns up to
  `nb-results` species (default 10) in decreasing score (0 to 1), each with its
  names, family, French common names with `lang=fr`, a GBIF id, and with
  `include-related-images=true` the most similar images of that species (author,
  licence, citation, three sizes). `predictedOrgans` gives the organ detected in
  each image. Everything the design shows (6b–6k) maps onto these fields.
- **Rejection**: a photo that is not a plant answers **404 "Species not found"**;
  `no-reject=true` returns the plant predictions anyway, except when no plant
  species is predicted at all (404 again). That is 6g's « Voir quand même ».
- **CORS works from the WebView**: the API answers preflights for any origin
  (`access-control-allow-origin` echoes `https://localhost`, POST allowed,
  `Content-Type` allowed), error bodies included. A key used from a browser must
  be **exposed** in the account settings, and then only the **authorized domains**
  (checked on the `Origin` header) may use it; non-browser requests are then
  refused unless they come from an **authorized IP**. Whether the settings accept
  `https://localhost` is **UNVERIFIED** (needs the account).
- **Free plan**: €0, **500 identifications a day**, reset at 00:00 UTC, commercial
  use allowed, never billed; beyond it **429** until the reset. **Since 2026-02-13
  a free-plan request that returns an error costs one credit too.** At most 20
  simultaneous requests per client. `/v2/projects` and `/v2/languages` are not
  counted.
- **Privacy**: "The photos sent by the user are not stored in the database. They
  are only kept in our server volatile memory during the identification
  process." The query history (date, time, image URLs) is kept. Hosted in Europe
  by CIRAD (Montpellier). The identify route takes **no position**.
- **Related images** are reusable under their licence (usually CC BY-SA) with
  three credits: Pl@ntNet, the licence, the contributor. The fields `author`,
  `license` and `citation` carry them. A 2022 free-account answer (third party)
  had **2 to 6 images per species**; the design draws « +14 » and « 3 / 15 »:
  fewer may come (count UNVERIFIED for 2026).
- **GBIF ids**: "Each species in `results` may have a `gbif.id` property"; the
  OpenAPI says a number, every recorded answer has a string (`"2927079"`). The
  ids checked are GBIF backbone keys of accepted species.
- **Floras**: `project` is a flora id from `GET /v2/projects` (`all` = "the most
  relevant project", answered in `preferedReferential`). Regional floras are the
  "KT" ones (POWO + WGSRPD level 2): France is in `k-southwestern-europe`. The
  design's « Europe de l'Ouest » is a placeholder that matches the name of the
  legacy `weurope` flora, whose model "will be dropped in the near future".
  `/v2/projects` can sort by `lat`/`lon`, which would send a position.
  **Tristan decided on 2026-11-16 for `all` (« Automatique ») as the default**
  (section 4).
- **The key was a decision for Tristan** (section 10): in the APK (exposed, only
  `https://localhost` authorized; the protection is the quota and the obscurity
  of a sideloaded APK in a private repository), behind a Supabase Edge Function
  (secret key, signed-in user only, one more hop and a dependency on an unpaused
  project), or typed in 4m. The report recommended the APK; **Tristan decided on
  2026-11-16 for C, the key typed in 4m, one per user** (section 10). That key
  must still be exposed for `https://localhost`, since the WebView's calls are
  browser calls.

| Question | Answer (2026-11-16) | Source |
|---|---|---|
| Endpoint | `POST https://my-api.plantnet.org/v2/identify/{project}` | swagger 2.2.2 |
| Auth | `api-key` query parameter ("not in body") | swagger; llms-full "Identify your images" |
| Images | 1–5, `image/jpeg` or `image/png`, total POST ≤ 50 MB (52 428 800 bytes); resized to 1280 px on the smaller side; ≥ 800 × 800 px and JPEG q90 advised | swagger; llms-full "Images and organs" |
| Organs | `auto` (default), `leaf`, `flower`, `fruit`, `bark` documented; the enum also has `habit`, `scan`, `branch`, `sheet`, `other`, `drawing`, `seed`, `bud`, `anatomy`, `aerial` | llms-full; swagger |
| Organ detection | `predictedOrgans[]`: `image` (hash), `filename`, `organ`, `score` (top 1 per image) | llms-full "Ouput format"; changelog 2025-01-14 |
| French names | `lang=fr` → `species.commonNames` | swagger `lang` enum; llms-full |
| Related images | `include-related-images=true` → `results[].images[]` {`organ`, `author`, `license`, `date`, `citation`, `url` {`o`,`m`,`s`}} | swagger `Image`; llms-full "Using images" |
| Not a plant | 404 "Species not found"; `no-reject=true` → predictions anyway, still 404 when none | llms-full "Rejection" |
| GBIF id | `results[].gbif.id`, "may have"; number in the OpenAPI, string in answers | swagger `gbif`; llms-full |
| Floras | `GET /v2/projects?lang=…` (`id`, `title`, `description`, `speciesCount`), not counted in the quota | swagger; pricing FAQ |
| Quota | 500/day free, 00:00 UTC reset, 429 + `Retry-After` beyond, errors cost a credit since 2026-02-13 | pricing; llms-full "Quota management"; changelog |
| CORS | preflight 200, origin echoed, POST, `Content-Type`; per-key "expose" + authorized domains | curl probes; llms-full "Expose your API key" |
| Photos kept | no ("volatile memory"); query history kept | terms of use; pricing FAQ |
| Credit | "Photo(s): [Contributor Username] / Pl@ntNet, CC BY-SA"; "Powered by Pl@ntNet" appreciated, not required on the free plan | llms-full "Using images"; pricing |

---

## 1. The identify route

From the OpenAPI (`/v2/identify/{project}`, POST, `operationId`
`postV2IdentifyProject`, `consumes: multipart/form-data`): "This service allows
plant identification (one request => one plant). Mime: image/jpeg or image/png.
Max POST size: 52428800 bytes".

| Parameter | In | Default | Meaning (quoted) |
|---|---|---|---|
| `project` | path | `all` | "Referential in which to search the plant (use one of the available projects or "all" to get the results of the most relevant project)" |
| `images` | form, 1–5 files | — | "Images (all images must respresent the same plant) [max: 5 images]" |
| `organs` | form, as many as images | `auto` | "Organs associated to images [max 5 organs and organs.length must be equal to images.length]. Defaults to "auto"." |
| `include-related-images` | query | false | "If true, for each probable species, the most similar images will be returned" |
| `no-reject` | query | false | "Disables "no result" in case of reject class match" |
| `nb-results` | query | 10 | "Max. number of species in identification results − a higher number increases response time" |
| `lang` | query | `en` | "i18n" (`fr` in the enum) |
| `detailed` | query | false | "results other than species predictions (family, genus…) will be added (slower)" |
| `type` | query | (`kt`) | deprecated: `kt` floras are the default since 2023-10-01 |
| `api-key` | query | — | "Your private API key" |

Documentation, "Images and organs": "Submitted images are **resized to 1280
pixels on the smaller side**, but smaller submitted images are never upscaled";
"Identification performance is not guaranteed for images smaller than
**800x800px**"; "We recommend to use jpeg compression with a quality of 90%";
"Omitting parameter `organs` sets every organ to `auto`"; organs ranked "flower,
fruit, leaf, entire plant, bark" (best first); "the AI automatically assigns
different weights to the different organs". "One request identifies one plant.
When multiple images are submitted at once, they must represent **the same
individual**."

Pl@ntNet's own browser example
(`examples/post/client_side_js/run.js`) builds a `FormData` with
`form.append('organs', 'auto'); form.append('images', file)` per image, adds
`include-related-images` and `api-key` to the URL and calls `fetch` with
`method: 'POST', body: form`: the shape Herbier would use from the WebView (Brr
has `Form.Data.append_blob` and `Fetch.Body.of_form_data`).

For Herbier: a device preview is ≤ 1600 px on its long side, JPEG q0.7, with
no EXIF (`photos/preview_size.ml`, `photos_io/preview.ml`): a 4:3 photo becomes
1600 × 1200, above the 800 px floor and close to Pl@ntNet's 1280, at a lower
quality than the advised q90 (effect on scores UNVERIFIED; plan R13).

## 2. The answer

OpenAPI definition `Identification result`: `query` {`project`, `images`,
`organs`, `includeRelatedImages`, `noReject`, `type`}, `language`,
`preferedReferential`, `switchToProject`, `bestMatch`, `results`,
`remainingIdentificationRequests`, `version`, `predictedOrgans`, `otherResults`.
Each of `results[]`: `score`, `species` {`scientificNameWithoutAuthor`,
`scientificNameAuthorship`, `scientificName`, `genus` {…}, `family`
{`scientificNameWithoutAuthor`, `scientificNameAuthorship`, `scientificName`},
`commonNames`[]}, `images`[] (see section 7), `gbif` {`id`}, `powo` {`id`},
`iucn` {`id`, `category`}.

The documentation's example answer (`curl -X POST
'https://my-api.plantnet.org/v2/identify/all?api-key=…' -F
'images=@/path/to/image.jpg'`), abridged:

```json
{"query":{"project":"all","images":["5440fc78d0dd7c382ee5d743eafb68d9"],"organs":["auto"],
  "includeRelatedImages":false,"noReject":false,"type":null},
 "predictedOrgans":[{"image":"5440fc78d0dd7c382ee5d743eafb68d9","filename":"image.jpg","organ":"flower","score":0.66656}],
 "language":"en","preferedReferential":"k-world-flora","bestMatch":"Ajuga genevensis L.",
 "results":[{"score":0.90734,
   "species":{"scientificNameWithoutAuthor":"Ajuga genevensis","scientificNameAuthorship":"L.",
     "genus":{"scientificNameWithoutAuthor":"Ajuga","scientificNameAuthorship":"","scientificName":"Ajuga"},
     "family":{"scientificNameWithoutAuthor":"Lamiaceae","scientificNameAuthorship":"","scientificName":"Lamiaceae"},
     "commonNames":["Blue bugleweed","Blue bugle","Geneva Bugle"],"scientificName":"Ajuga genevensis L."},
   "gbif":{"id":"2927079"},"powo":{"id":"444576-1"}}],
 "version":"2025-01-17 (7.3)","remainingIdentificationRequests":498}
```

What Herbier reads, per design screen: the order and `score` of `results`
(6c: "Ordre et score de Pl@ntNet"); `scientificNameWithoutAuthor` and
`scientificNameAuthorship` (the Latin line, author in roman); `commonNames`
with `lang=fr` (the French line, and 6e's name for a new fiche); `family`'s
`scientificNameWithoutAuthor`; `gbif.id` (6c « Dans ma collection », the link);
`images` (the four closest photos, 6d); `predictedOrgans` (« fleur ▾ »);
`preferedReferential` (which flora `all` used); `remainingIdentificationRequests`
(logged). `bestMatch`, `powo`, `iucn`, `version` and `otherResults` are not
needed.

"The identification model is updated approximately every two months, following
a principle of non-regression" (documentation, "Identification model"): the
same photos may score differently a few months apart.

## 3. Errors and rejection

OpenAPI responses of the POST: 200, 400 Bad Request, 401 Unauthorized, 404
Species Not Found, 413 Payload Too Large, 414 URI Too Long, 415 Unsupported
Media Type, 429 Too Many Requests, 500 Internal Server Error.

Documentation, "Rejection": "Images identified as non-plants (landscape, human
being, object…) are rejected, and lead to a "404 Species not found" error."
"Set `no-reject` to `true` to still get the (less probable) plant species
predictions when the most probable result is not a plant." "When no plant
species is predicted at all, even with a very low score, a "404 Species not
found" error is returned regardless of `no-reject`."

Observed on 2026-11-16 (no valid key, a 150 × 150 JPEG):

```
POST /v2/identify/all?lang=fr                      → 401
{"statusCode":401,"error":"Unauthorized","message":"Missing authentication"}
POST /v2/identify/all?lang=fr&api-key=<invalid>    → 401, www-authenticate: Bearer error="Bad token"
{"statusCode":401,"error":"Unauthorized","message":"Bad token","attributes":{"error":"Bad token"}}
GET  /v2/_status                                   → 200 {"status":"ok"}  (no key needed)
```

The bodies of a 404 "Species not found" and an unauthorized origin were
recorded by M9.63 (`docs/notes/plantnet-webview.md`); the 429's body is
UNVERIFIED (not recorded: it would spend the day's 500). Changelog 2026-02-13, "Credits consumption for
free plan": on the free plan, "requests returning an error will consume 1
credit as well". So a client must not retry on its own: every retry, `no-reject`
re-ask, organ correction or added photo is one of the day's 500.

## 4. Floras (projects)

Documentation, "Taxonomy related routes": "Pl@ntNet identification engine will
give better results if you request identification within a particular
**project**"; "the `k-*` projects, known as "Kew-TDWG" or "KT" projects, are all
related to a geographical area from TDWG's WGSRPD, `k-world-flora` being the
union of all KT projects". `GET /v2/projects` (`lang`, `lat`, `lon`, `type`,
`api-key`) returns `id`, `title`, `description`, `speciesCount`; with `lat` and
`lon`, "only projects close to your position are returned by order of
proximity decreasing" (example: `k-southwestern-europe`, `salad`, `cevennes`,
`provence` for 43.451, 3.145). The pricing FAQ: "Lookup routes such as
`/languages` or `/projects` don't count."

"Kew / TDWG floras" page: legacy floras keep an identification model that "will
not be updated anymore"; the identify section: "Identification requests on
legacy projects are performed by an outdated model and will be dropped in the
near future! You should always use KT projects instead." WGSRPD level 2 has no
"Western Europe": France (with Corsica) is in region 12, Southwestern Europe,
i.e. `k-southwestern-europe` (identify.plantnet.org lists it, and
`k-middle-europe`). « Europe de l'Ouest » in the design (a placeholder, like the
handoff's places) matches the name of the legacy `weurope` flora (Pl@ntNet's
example script still says "try 'weurope', 'canada'…"). The French titles of
`/v2/projects?lang=fr` are UNVERIFIED.

For Herbier: positions stay on the phone unless the user turns a source on
(plan M5.57), so the flora list is asked without `lat`/`lon`. `all` lets
Pl@ntNet pick the flora per request and works outside France; a pinned KT flora
is what the documentation says gives better results.

**Decision (Tristan, 2026-11-16): the default flora is `all` (« Automatique »)**,
in his words: « using 'europe de l'ouest' would make it harder to identify non-indigenous plants ». The design's « Europe de l'Ouest »
is replaced as the default; the list from `/v2/projects` stays selectable in 4m
and 6c.

## 5. Authentication, CORS and the WebView

Documentation, "Expose your API key":

> To enable usage of your API key in browser-side client apps, you need to
> explicitly authorize all domain names the service is accessed from.
>
> **Enable client access to your API key (CORS).** From your account API key
> settings page, check "expose my API key". You can now use your API key in a
> client-side browser application, ie. in a CORS-enabled environment.
>
> **Authorize domain(s).** Under "Authorized domains", add one domain per line.
> CORS requests will be rejected if domain present in `Origin` header is not in
> this list. (CORS considers http://domain.com and https://domain.com as
> different origins.)
>
> **Authorize IP addresses (optional).** Once "expose my API key" is checked, any
> non-CORS request will be rejected if it does not come from a server with an IP
> address matching the "Authorized IPs" list. This prevents the exposed API key
> from being stolen and used server-side on a machine that isn't yours.

The account's `security` object in the OpenAPI (`GET /v2/subscription`) has
`exposeKey`, `ips` and `domains`, the same three settings.

Probes on 2026-11-16 (Herbier's WebView origin is `https://localhost`:
Capacitor 8's Android default, as for Google Picker in
`notes/google-picker-webview.md`):

```
OPTIONS /v2/identify/all   Origin: https://localhost, Access-Control-Request-Method: POST,
                           Access-Control-Request-Headers: content-type
→ 200  access-control-allow-origin: https://localhost
       access-control-allow-methods: POST
       access-control-allow-headers: Accept,Authorization,Content-Type,If-None-Match
       access-control-max-age: 86400
       access-control-expose-headers: WWW-Authenticate,Server-Authorization
OPTIONS with Origin: https://example.org → the same, origin echoed
GET /v2/projects?lang=fr, Origin: https://localhost → 401 with access-control-allow-origin: https://localhost
```

So the WebView can call the API with `fetch` and read its answers and error
bodies; the per-key domain check happens after authentication. A `FormData`
POST is a CORS "simple" request anyway (no preflight). The quota headers
(`RateLimit`, `RateLimit-Policy`, `Retry-After`) are **not** in
`access-control-expose-headers`, so the WebView cannot read them: the body's
`remainingIdentificationRequests` is what it gets. UNVERIFIED: whether "Authorized
domains" accepts `https://localhost` (or `localhost`), and the status of a
request from an origin not in the list.

The key travels in the query string (the documented way; the OpenAPI declares
no header for it), so any log line that prints the request URL prints the key.

## 6. Quota, plans and rate

Pricing page, 2026-11-16, "Free — For prototypes, small apps and personal
projects — €0": "500 identifications / day, reset at midnight UTC", "Commercial
use allowed", "No credit card, no contract", "All features", "87,000+ species,
names in 50+ languages", "Hosted in Europe, continuously updated", "One account
per person or organisation", and the "Powered by Pl@ntNet" mention
"appreciated, not required". FAQ: "One request to the identify endpoint, with 1 to 5 images of the
same plant, counts as one identification"; "Further requests are refused with an
HTTP 429 Too Many Requests error until your quota resets at midnight UTC. You are
never billed on the free plan."; "every client is limited to 20 simultaneous
requests, whatever the plan"; "several free accounts sending requests from the
same IP address are forbidden". Pro: €1,000 a year for 200,000, then €0.005 per
identification up to 3 M (same figures in the terms). Non-profit plan: 500 to
10,000 a day, "Powered by Pl@ntNet" logo required.

Documentation, "Quota management": quotas are "per user, per request category,
per day"; `GET /v2/quota/daily` gives `count`, `total`, `remaining` per category;
a 429 comes with `Retry-After` (the next 00:00 UTC). Changelog 2026-02-13: errors
consume a credit on the free plan.

For one person the cap is far: a field day of 50 photos identified twice each is
100. What spends credits without the user asking would be an automatic retry or
an automatic identification of a queue; the design has neither.

## 7. Related images: licences, credits, storage

Documentation, "Using images": "Images shared on Pl@ntNet are usually licensed
under Creative Commons Attribution-ShareAlike (CC BY-SA)" (share, adapt, "even
commercially"). "When using Pl@ntNet images, you must include the following
attributions: Pl@ntNet app credit (…), License indication (…), Contributor credit
(…)". Example: "Photo(s): [Contributor Username] / Pl@ntNet, CC BY-SA".
"Single-image, diseases and varieties identification routes return images under
`.images`. Relevant fields are: `author`, `license`, `citation`."

The diseases example in the documentation shows the object:

```json
{"organ":"bark","author":"Ephytia − D.Blancard - INRAE − Ephytia","license":"cc-by-sa",
 "date":{"timestamp":1702309142589,"string":"11 décembre 2023"},
 "url":{"o":"https://bs.plantnet.org/image/o/7ea38c7be4b07a8ad11ca555b4139cd3c66dcda1",
        "m":"https://bs.plantnet.org/image/m/7ea38c7b…","s":"https://bs.plantnet.org/image/s/7ea38c7b…"},
 "citation":"Ephytia − D.Blancard - INRAE − Ephytia / Pl@ntNet, cc-by-sa"}
```

How many per species: not documented. A recorded identify answer of a free
account (`"remainingIdentificationRequests":472`, model `"2022-10-24 (7.0)"`,
`include-related-images=true`, one leaf photo), committed 2023-04-23 in a third
party's code (`rktejesh/observation-of-trees-using-RFID-tags`,
`lib/models/detect_species_model.dart`), has 8 species with **6, 6, 6, 2, 6, 6,
2 and 3 images**, mostly of the queried organ, every `gbif.id` a string. So
related images work on the free plan (2022), and a species may come with fewer
than the four tiles 6c draws and far fewer than 6d's « 3 / 15 ». 2026 counts
UNVERIFIED (M9.63). The species-list routes' `images=true` is "pro" only
(changelog 2026-03-03); the identify route's related images are not marked so.

`bs.plantnet.org` sends no CORS headers (seen in M4.37), which does not matter for
an `<img>`: 6c and 6d show the `s` and `m` URLs directly, nothing is downloaded
or stored. The terms' "No element of the Pl@ntNet application shall be copied
(…) without the written and prior authorization" governs the platform; the
returned images are licensed for reuse by the "Using images" page, under their
licence and credits.

## 8. Privacy: what Pl@ntNet keeps

Terms of use, "Main Pl@ntNet API feature": "The photos sent by the user are not
stored in the database. They are only kept in our server volatile memory during
the identification process. We store the query history of each user (i.e. the
date, time and image URL(s) of the submitted queries). We don't store the images
themselves, only the image URL(S)." Pricing FAQ: "Do you store the photos I send?
No. Images are only kept in memory during identification." "Where is the
service hosted? In Europe, by CIRAD (Montpellier, France)". The design's « Pl@ntNet
ne conserve pas la photo » (6b) and « Pl@ntNet ne conserve pas les photos
envoyées » (6h) are what these pages say.

The identify route has no position parameter, and a device preview carries no
EXIF (canvas re-encode). Sending previews, never originals, keeps the photo's GPS
on the phone.

## 9. GBIF ids

Documentation: "Each species in `results` may have a `gbif.id` property. Use it
with the GBIF species API". OpenAPI `gbif`: `{"id": {"type": "number"}}`; the
documentation's examples and the 2022 recording: strings (`"2927079"`). A decoder
takes both. Checked on GBIF on 2026-11-16:

```
GET https://api.gbif.org/v1/species/2927079 → Ajuga genevensis L., SPECIES, ACCEPTED, dataset d7dddbf4-… (backbone)
GET https://api.gbif.org/v1/species/7307097 → Ajuga orientalis L., SPECIES, ACCEPTED, backbone
GET https://api.gbif.org/v1/species/3189863 → Acer campestre L., SPECIES, ACCEPTED, backbone
```

So the id is a GBIF backbone `usageKey`, Herbier's primary key (`stack.md`).
Pl@ntNet's KT floras follow WCVP v13 (changelog 2025-09-24), whose names may be
synonyms in GBIF's backbone: Herbier's resolver already replaces a synonym by
its accepted taxon (one hop, `refs/resolve.mli`), and falls back to
`species/match` on the name when the id is missing.

## 10. The API key: options for Herbier

Facts that bear on it: the key is free and the free plan can never bill; a
stolen key can spend the day's 500 (identification then fails until 00:00 UTC)
or get the account blocked; a key is regenerated in the account settings. The
repository is private, the APK is sideloaded on the user's phone (built by
`scripts/release.sh`, or by `android.yml` into a private release). The WebView
calls with `Origin: https://localhost`; a non-browser client can send the same
header, so "authorized domains" stops casual reuse, not a determined one.

| | A. Key in the APK | B. Supabase Edge Function | C. Key typed in 4m |
|---|---|---|---|
| Where the key is | built in from `HERBIER_PLANTNET_API_KEY` (`.env.prod`, a CI secret), optional like `HERBIER_GOOGLE_CLOUD_PROJECT_NUMBER` | a Supabase secret; the app sends the photos to `/functions/v1/…` with the session's JWT | the device's settings, pasted once per install |
| Pl@ntNet settings | exposed, authorized domain `https://localhost`, no IP | not exposed (server use from any IP) | as A |
| Who can spend it | anyone who extracts it from the APK and forges the `Origin` | only the signed-in account (sign-ups are off) | anyone who reads it off the phone and forges the `Origin` |
| Works signed out / project paused | yes | no (needs the session and an unpaused project) | yes |
| New code | a dune rule and one `.env.prod` line | the first Edge Function (Deno, TypeScript): outside the OCaml stack, deployed with `supabase functions deploy` | a 4m row with a text field, not in the design (6h) |
| Photos go through | Pl@ntNet only | Supabase's edge runtime, then Pl@ntNet | Pl@ntNet only |
| Limits | Pl@ntNet's | plus 150 s wall clock, 2 s CPU, 500,000 invocations a month on the free plan (Supabase limits and pricing pages, 2026-11-16; no request size limit stated) | Pl@ntNet's |
| Rotation | regenerate, rebuild, reinstall | `supabase secrets set` | paste the new key |

Recommendation: **A**, on the condition M9.63 checks (an exposed key accepted
from `https://localhost` in the WebView). It matches the stakes (a free quota, one
user, a private sideloaded APK) and the existing pattern of optional build-time
values, adds no server and no sign-in dependency, and sends the photos to one
processor. Its mitigations: the key never in a commit, a fixture or a log line
(the URL is logged without its query string), a build without it disables
« Identifier » with its reason, and the key is regenerated if the APK ever leaves
the user's devices. **B** if the WebView cannot use an exposed key, or if the APK
is ever shared. C only if keys must not be built in at all: it adds a row the
design does not have.

**Decision (Tristan, 2026-11-16): C.** In his words: « une clé dans les réglages
c'est bien pour le moment. 500 c'est largement suffisant pour une app que seul
moi utilise. et si on maintient une clé chacun, pas de problème ». The key is
the user's own, typed in 4m, one key per user, each with its 500 a day; nothing
is built into the APK and there is no Edge Function. Herbier keeps it on the
device only (Capacitor Preferences, left out of Android's backups like the
Supabase session), never syncs or logs it, and identification works signed out
(plan Decisions « Clé API Pl@ntNet », architecture §12). On exposure, the
documentation quoted in section 5 answers for C as for A: a key used "in
browser-side client apps" must have « expose my API key » checked, and CORS
requests are "rejected if domain present in `Origin` header is not in this
list". The WebView's `fetch` is such a request (`Origin: https://localhost`), so
the user's key needs both, and 4m's help text says so. Not yet observed: that a
key left unexposed is refused from the WebView, and that the list takes
`https://localhost` (section 11).

## 11. Open points (UNVERIFIED until M9.63)

- "Authorized domains" accepting `https://localhost`, the answer to an origin
  outside the list, and whether a request from outside a browser passes with a
  forged `Origin: https://localhost` (expected: yes, the weakness any exposed
  key has, option C's included); whether the same key, not exposed, is refused
  from the WebView (the documentation says so).
- The count and organs of related images per species in 2026, with `nb-results`
  5 and `lang=fr`; the French titles of the floras.
- The bodies of 404 "Species not found" (with and without `no-reject`) and 429.
- Response time on mobile data for one and five previews with related images.
- Scores of a q0.7 preview against a q0.9 encode of the same original.

## Sources

1. OpenAPI: https://my-api.plantnet.org/swagger.json (version 2.2.2), browsable at https://my-api.plantnet.org/ — fetched 2026-11-16.
2. Documentation, one file: https://my.plantnet.org/llms-full.txt (index https://my.plantnet.org/llms.txt; pages https://my.plantnet.org/doc/api/identify, /doc/api/quota, /doc/api/taxonomy, /doc/references/using-images, /doc/references/newfloras, /doc/references/changelog, /doc/getting-started/introduction) — fetched 2026-11-16, Last-Modified 2026-11-03.
3. Pricing and FAQ: https://my.plantnet.org/pricing — 2026-11-16.
4. Terms of use: https://my.plantnet.org/terms_of_use — 2026-11-16.
5. Example client: https://github.com/plantnet/my.plantnet/blob/master/examples/post/client_side_js/run.js — 2026-11-16.
6. Recorded 2022 answer (third party): https://github.com/rktejesh/observation-of-trees-using-RFID-tags/blob/869f303/lib/models/detect_species_model.dart — commit of 2023-04-23.
7. Floras on identify.plantnet.org: https://identify.plantnet.org/k-southwestern-europe/species, https://identify.plantnet.org/k-middle-europe/species — 2026-11-16 (search results).
8. GBIF species API: https://api.gbif.org/v1/species/2927079 (and 7307097, 3189863) — 2026-11-16.
9. Supabase Edge Functions limits: https://supabase.com/docs/guides/functions/limits; pricing: https://supabase.com/pricing — 2026-11-16.
10. Earlier Herbier research on the same API: `botanical-data-sources.md` §2.1 (2026-09-15).
