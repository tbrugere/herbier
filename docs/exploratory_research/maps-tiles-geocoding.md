# Maps, tiles, offline and geocoding for Herbier

Date: 2026-09-15. Research for a single-user Android WebView app (Capacitor/Cordova, js_of_ocaml). All facts below were checked against the cited pages on this date unless marked UNVERIFIED. Prices/limits are as published on 2026-09-15.

## Summary

**"Map tiles API for a small hobby project: OSM? Google?" — neither, as first choice.** `tile.openstreetmap.org` is fine for light live browsing but its policy forbids bulk download and "offline use", so it cannot cover "tiles work offline where I've been", and it requires an identifying User-Agent (Capacitor `appendUserAgent`). Google gives 10,000 free Dynamic Maps loads/month since March 2025 but needs a billing-enabled project and key, has WebView referrer quirks, no offline story, and is the only option that can ever invoice you.

**Recommendation (free, keyless, minimal ops):**

1. **Library:** MapLibre GL JS v6 (6.9.1, 2026-09-14; ESM-only, WebGL2, 149 KB gz). Leaflet is lighter (43 KB gz) but 2.0 is still alpha and raster is worse for offline. Clusters, metric circles and custom protocols are built in.
2. **Style + tiles online:** OpenFreeMap `positron` — light vector style, no key, no stated limits, donation-funded; keep the CSS desaturation if wanted. Keyless fallbacks: VersaTiles (`graybeard`/`neutrino`) and IGN Plan IGN vector (`gris`/`attenue`, Etalab; best hiking context). Keyed fallbacks: Protomaps hosted (1M req/month non-commercial), Stadia `alidade_smooth` (200k credits/month non-commercial), Thunderforest `outdoors` (150k tiles/month, on-device caching explicitly allowed).
3. **Offline:** ship one Protomaps PMTiles extract of Alsace+Vosges on device. Measured today with `pmtiles extract` (bbox 6.0–8.4E/47.4–49.2N): **61 MB at z≤12, 237 MB at z≤14** (z≤15 ≈ 0.7–0.9 GB extrapolated, UNVERIFIED). Read it with the `pmtiles` protocol and an OPFS/Filesystem-backed `Source`; style with `@protomaps/basemaps` flavor `white`/`grayscale`. No service worker (flaky in Capacitor Android). Cheaper variant: OpenFreeMap online + `addProtocol` write-through cache of visited tiles.
4. **Geocoding:** reverse = IGN Géoplateforme `data.geopf.fr/geocodage/reverse?index=poi` (no key, 50 req/s, Etalab; verified: rural Vosges point → "Stosswihr", Colmar centre → Colmar). Forward = Photon `photon.komoot.io/api?lang=fr&lat&lon` (search-as-you-type allowed; "Hohn" → Hohneck, while Géoplateforme returned nothing for the partial). Nominatim is out (autocomplete banned, 1 req/s).

| Provider | Key | Free limit | Referrer restriction / WebView | Attribution |
|---|---|---|---|---|
| tile.openstreetmap.org | no | light use; offline/bulk forbidden | UA required → `appendUserAgent` | OSM |
| OpenFreeMap | no | none stated (may ask apps for a header) | none | OpenFreeMap+OpenMapTiles+OSM |
| VersaTiles | no | none stated | none | OSM |
| IGN Plan IGN vector | no | not stated, Etalab | none | IGN |
| Protomaps hosted | yes | 1M/month, non-commercial | optional origin allowlist | OSM |
| Protomaps PMTiles self-host | no | your storage | file on device | OSM |
| MapTiler | yes | 100k/month, non-commercial, logo | origin or UA-substring key | MapTiler+OSM |
| Stadia | yes (apps) | 200k credits/month, non-commercial | key mandatory in apps; scoping UNVERIFIED | Stadia+OSM |
| Thunderforest | yes | 150k tiles/month | honest UA/Referer | Thunderforest+OSM |
| Google Maps JS | yes+billing | 10k loads/month | allowlist `https://localhost/*` | Google |

**Offline verdict:** on-device PMTiles extract (237 MB, z≤14) via the pmtiles protocol; never cache from tile.openstreetmap.org.

**Geocoders:** Géoplateforme (reverse) + Photon (forward), each the other's fallback.

**Top links:** https://openfreemap.org/ · https://docs.protomaps.com/pmtiles/cli · https://operations.osmfoundation.org/policies/tiles/ · https://cartes.gouv.fr/aide/fr/guides-utilisateur/utiliser-les-services-de-la-geoplateforme/geocodage/ · https://github.com/maplibre/maplibre-gl-js/discussions/6910

---

## 1. Map library in a WebView

### MapLibre GL JS
- Latest: **v6.9.1, published 2026-09-14** (GitHub releases API, checked 2026-09-15). v6.0.0 shipped 2026-07-22 and is **ESM-only**: `maplibre-gl.js` UMD is gone, `maplibre-gl.mjs` loads its worker as a real URL, so the CSP `worker-src blob:` requirement is dropped. Other v6 breaking changes: `Map` composes `Camera`, events are real classes, `styleimagemissing` is notify-only (`Map.setMissingStyleImageResolver`). Source: https://github.com/maplibre/maplibre-gl-js/releases/tag/v6.0.0 (2026-07-22).
- Size measured today from jsDelivr: `maplibre-gl@6.9.1/dist/maplibre-gl.mjs` 586 KB raw / **149 KB gzip**, CSS 83 KB / 11 KB gz. For comparison v5.19 UMD was 1.0 MB / 269 KB gz. For a bundled app the size is irrelevant except for first-parse time.
- WebGL: MapLibre ≥ 3.0 requires **WebGL2** (https://github.com/maplibre/maplibre-gl-js/releases/tag/v3.0.0, "Full transition from WebGL1 to WebGL2"). Android System WebView is Chromium-based and ships WebGL2; a historical Mali-GPU WebGL2 bug in WebView was tracked at https://issues.chromium.org/issues/40615157 (2019). No 2025–2026 reports of WebGL2 being unavailable in WebView were found (general support statement UNVERIFIED against a primary doc).
- Known WebView/Capacitor issues:
  - https://github.com/maplibre/maplibre-gl-js/issues/1368 (2022-07, closed): crash in Cordova WebView with 3D terrain at max pitch, memory-related. Not relevant to a 2D map.
  - https://github.com/maplibre/maplibre-gl-js/issues/6919 (2025-12): temporary white gaps at map edges during pan/zoom in WebView (Flutter desktop/Android) with cached tiles; cosmetic.
  - https://github.com/maplibre/maplibre-gl-js/discussions/5250 (2024-12-20): tile requests are issued from a Web Worker, so `CapacitorHttp` patching does not apply; fix is `addProtocol()` on the main thread plus `transformRequest`. For Herbier this matters only if a provider needs a non-CORS header; OpenFreeMap/VersaTiles/IGN/Protomaps send CORS headers.
  - MapLibre GL JS has no persistent tile cache and the maintainers do not plan one: "You can use `addProtocol` to achieve this functionality" (https://github.com/maplibre/maplibre-gl-js/discussions/6910, 2025-12-24/29).
- Capacitor: latest 8.5.2 (2026-09-11). Android WebView is served from **`https://localhost`** by default (`server.androidScheme` default `https`, hostname `localhost`; secure-context APIs like geolocation work) — https://capacitorjs.com/docs/config. iOS uses `capacitor://localhost`.

### Leaflet
- 1.9.4 (2023-05-18) is still `latest` on npm; **2.0 is only at 2.0.0-alpha.1 (2025-08-16)** with "no timeline for the final release" (https://github.com/Leaflet/Leaflet/issues/9869; https://leafletjs.com/2025/05/18/leaflet-2.0.0-alpha.html). 2.0 is ESM, Pointer Events, no IE.
- Size measured: leaflet@1.9.4 148 KB / **43 KB gz**; 2.0.0-alpha.1 145 KB / 41 KB gz.
- Raster only (unless using `maplibre-gl-leaflet`), Canvas/DOM rendering, no WebGL dependency — the safest fallback if WebGL2 ever misbehaves on the target phone. Clustering needs a plugin (Leaflet.markercluster). Offline raster caching means many small PNGs (see section 3).

### Google Maps JS SDK
- Works in a WebView if the key's HTTP-referrer allowlist contains the WebView origin. Capacitor Android's default origin `https://localhost` is a standard scheme; custom schemes (`capacitor://`) broke for a week in 2019 when Google tightened referrer parsing (https://github.com/ionic-team/capacitor/discussions/1579, 2019-05-26; Google tracker 124858510 requires sign-in, UNVERIFIED). Requires a Cloud project with billing enabled (Google's standard requirement; the pricing page implies a billing account, direct statement UNVERIFIED). Custom light styling via cloud map IDs. No offline. Rejected.

### Free light/desaturated styles
| Style | Type | Key | Notes |
|---|---|---|---|
| OpenFreeMap `positron` | vector | no | https://tiles.openfreemap.org/styles/positron (HTTP 200 today; 55 layers, sources `openmaptiles`, `ne2_shaded`). Also `bright`, `liberty`, `dark`, `fiord`, `3d`. |
| Protomaps `light` / `white` / `grayscale` | vector (self-host or hosted) | hosted: yes | Flavors in `@protomaps/basemaps`: light, dark, white, grayscale, black (https://docs.protomaps.com/basemaps/flavors). `white`/`grayscale` are "for data visualization" — closest to the paper look. |
| VersaTiles `graybeard`, `neutrino`, `eclipse`, `colorful` | vector | no | https://tiles.versatiles.org/assets/styles/<name>/style.json all HTTP 200 today. |
| IGN Plan IGN `gris`, `attenue`, `epure`, `sans_toponymes`, `standard`, `classique`, `accentue` | vector | no | https://data.geopf.fr/annexes/ressources/vectorTiles/styles/PLAN.IGN/<name>.json all HTTP 200 today. IGN cartography with relief — good hiking context. |
| MapTiler `dataviz-light`, `toner` | vector | yes | 100k req/month free, non-commercial, logo attribution. |
| CARTO Positron raster | raster | yes | needs key; raster being retired (UNVERIFIED — from docs.carto.com FAQ summary). |
| Stadia `alidade_smooth` | vector/raster | yes (apps) | 1 credit/tile, 200k credits/month. |
| Thunderforest `outdoors` / `landscape` | raster | yes | hiking styles with contours; 150k tiles/month. |

## 2. Tile providers and terms (2026-09-15)

- **OSM tile.openstreetmap.org** — https://operations.osmfoundation.org/policies/tiles/ (no date on page; 2025 rewrite with sections "3.4 Apps, Library defaults & SDKs" and "4. Prohibited: bulk downloading and offline use"). Requirements: a unique, stable User-Agent naming the app (+contact), contact email in the app store listing, honour cache headers (≥7 days), HTTPS only, visible attribution. Prohibited: bulk download, prefetch features, "Offline use is not permitted on tile.openstreetmap.org", library-default UAs ("will be blocked"). Native apps need no Referer. In a WebView the only way to set a UA is the WebView setting: Capacitor `appendUserAgent` / `overrideUserAgent` (https://capacitorjs.com/docs/config). Community reports of 403s after the policy update: https://community.openstreetmap.org/t/request-for-temporary-exemption-app-blocked-by-user-agent-policy-users-on-older-versions-affected/141796.
- **OpenFreeMap** — https://openfreemap.org/ : "no limits on the number of map views or requests", "no registration, no user database, no API keys, and no cookies"; attribution "OpenFreeMap © OpenMapTiles Data from OpenStreetMap" (OpenFreeMap part optional). Funded by ~$500/month donations, Cloudflare-sponsored bandwidth; after the Wplace.live surge (100k req/s) the author plans per-referer limits (~100M/24h) and "for native apps, I'll probably ask them to add a custom header identifying their app" (https://blog.hyperknot.com/p/openfreemap-survived-100000-requests, 2025-08-09). Self-host script for Ubuntu 24.04 + weekly planet dumps (https://github.com/hyperknot/openfreemap, 6k stars, pushed 2026-09-13).
- **VersaTiles** — https://docs.versatiles.org/guides/use_tiles_versatiles_org : "a free vector tiles server open for public use", `https://tiles.versatiles.org/tiles/osm/{z}/{x}/{y}`, no key; warns assets may change so copy styles/fonts if you depend on them. No limits stated (operator/funding not documented on that page — UNVERIFIED).
- **IGN Géoplateforme (Plan IGN vector)** — public style without key: https://data.geopf.fr/annexes/ressources/vectorTiles/styles/PLAN.IGN/standard.json (https://guides.data.gouv.fr/guides/reutiliser-des-donnees/utiliser-les-api-geographiques/utiliser-les-tuiles-vectorielles). Plan IGN is open (Etalab); SCAN 25 is **not** free (third-party rights; transitional key `ign_scan_ws`) — https://ideo.data.arnia-bfc.fr/actualites/acces-aux-scan-25r-scan-100r-et-scan-oaci. Usage limits for the public vector service not published (UNVERIFIED).
- **Protomaps** — hosted API https://protomaps.com/api : key required, "free for non-commercial use", commercial via GitHub Sponsors from $14/month, up to 1M tile requests/month (also https://protomaps.com/blog/free-tier-maps/, 2022-03-23); per-key CORS origin allowlist, localhost exempt; attribution "© OpenStreetMap". Serves ZXY/MVT, not PMTiles. Self-host: daily planet build ~120 GB z0–15 (https://docs.protomaps.com/basemaps/downloads), e.g. https://build.protomaps.com/20260915.pmtiles (mvt, z0–15, verified with `pmtiles show` today). Regional extracts with `pmtiles extract --bbox --maxzoom` (https://docs.protomaps.com/pmtiles/cli). **Measured 2026-09-15:** Alsace+Vosges bbox `6.0,47.4,8.4,49.2`: 1,192 tiles/61 MB (z≤12), 18,304 tiles/**237 MB (z≤14)**, 72,397 tiles (z≤15, not downloaded; ~0.7–0.9 GB extrapolated at ~13 KB/tile, UNVERIFIED). Whole-France bbox: 460k tiles (z≤14) → ~6 GB, 1.77M tiles (z≤15) → ~15–20 GB (extrapolated, UNVERIFIED). Cloudflare R2 free tier (10 GB) would hold a France z≤14 extract but is unnecessary: a 237 MB regional file fits on the phone.
- **MapTiler** — https://www.maptiler.com/cloud/pricing/ : Free = 100k requests/month, 5k map sessions, 1k search sessions, "personal or non-commercial", MapTiler logo mandatory, **no Static Maps API**, service pauses at the limit. Keys protected by allowed HTTP origins **or** a User-Agent substring ("Create a separate API key for each platform") — https://docs.maptiler.com/guides/maps-apis/maps-platform/how-to-protect-your-map-key/. In a WebView use a UA-restricted key with `appendUserAgent`.
- **Stadia Maps** — https://stadiamaps.com/pricing : Free = 200,000 credits/month, "Commercial use not allowed", no credit card; raster or vector tile = 1 credit, static map 20, forward/reverse geocode 20, autocomplete v2 = 1. https://docs.stadiamaps.com/authentication/ : domain auth (Origin/Referer) for websites; **API key mandatory for mobile apps**; key scoping to domains is not documented (UNVERIFIED). https://docs.stadiamaps.com/limits/ : "Proxying and bulk downloading/caching (with few exceptions) are prohibited".
- **Thunderforest** — https://www.thunderforest.com/pricing/ : Hobby Project free, 150,000 tiles/month, attribution cannot be removed. Terms https://www.thunderforest.com/terms/ : "Tiles may be cached in-browser and on-device for offline use", "Apps may retain tiles beyond the HTTP Expiry date, until fresh tiles are downloaded", honest Referer/UA required, attribution to Thunderforest and OSM. The only commercial provider here that explicitly permits on-device offline caching.
- **CARTO** — https://carto.com/basemaps/ : free up to 5M tile requests/month with an API key (no account needed). docs FAQ (via search summary, UNVERIFIED): raster `basemaps.cartocdn.com` now requires the key and is "being retired".
- **Mapbox** — 50k web map loads/month free, then ~$5/1k (https://storerocket.io/learn/mapbox-pricing, 2026). Requires account + card. Not needed.
- **Google Maps Platform** — https://developers.google.com/maps/billing-and-pricing/march-2025 : from 2025-03-01 the $200 credit is replaced by per-SKU caps: Essentials 10k, Pro 5k, Enterprise 1k events/month. https://developers.google.com/maps/billing-and-pricing/pricing : Dynamic Maps, Static Maps, Geocoding, Autocomplete are all Essentials → 10,000 free each/month.

## 3. Offline tiles in a Capacitor WebView

- **Service workers**: Ionic maintainers, https://github.com/ionic-team/capacitor/discussions/3205 (2020-07): "on Android they work on the WebView, but doesn't work well when using Capacitor"; recommendation was to disable SW in native builds. Capacitor now routes SW requests through the bridge (`resolveServiceWorkerRequests`, default true — https://capacitorjs.com/docs/config). Not worth the risk for a single-user app.
- **MapLibre `addProtocol`** (main thread) is the sanctioned hook (discussion #6910). Pattern: `addProtocol('cached', async (req) => ...)` → look up Cache API/IndexedDB by URL → else `fetch` and store; `transformRequest` rewrites tile URLs to `cached://…`. Libraries doing exactly this: `map-gl-offline` (IndexedDB, https://medium.com/@muimsd/map-gl-offline-complete-offline-maps-for-maplibre-gl-js-ea41b21a1324) and **makinacorpus/maplibre-offline-pmtiles** (MIT, OPFS-backed `offline-pmtiles://` protocol, vector MVT + raster, download progress, quota; pushed 2026-03-03, 9 stars — https://github.com/makinacorpus/maplibre-offline-pmtiles). Protomaps' own advice (https://github.com/protomaps/PMTiles/discussions/588, 2025-07-25): ship z8 sub-pyramid PMTiles files, 100 MB–2 GB, store in OPFS.
- **PMTiles from the filesystem**: `pmtiles` JS 4.5.0 (8 KB gz) lets you implement `Source.getBytes(offset, length)`; back it with Capacitor Filesystem (whole-file read into an `ArrayBuffer`/Blob and `slice`, fine at 237 MB? — memory heavy; better: copy the asset into OPFS once, then `FileSystemSyncAccessHandle.read` at offsets, which is what the makinacorpus plugin does). Serving the file over `https://localhost` via Capacitor's local server with Range requests is UNVERIFIED (older Cordova project https://github.com/Yermo/maplibre-gl-capacitor-offline, 2022, did MBTiles via a plugin).
- **Sizes**: vector Alsace+Vosges z≤14 = 237 MB measured (z≤12 = 61 MB). Raster equivalent estimate (UNVERIFIED): the same bbox at z≤14 ≈ 12k 256-px PNG tiles × ~15 KB ≈ 180 MB, z≤15 ≈ 700 MB — comparable size but without over-zoom (vector tiles at z14 render crisply to z17+, raster does not).
- **Verdict**: simplest robust path = PMTiles regional file on device + `pmtiles` protocol + Protomaps `white`/`grayscale` flavor; you get full offline for the whole region, not only visited tiles, and zero provider dependency. Simplest-to-code path = OpenFreeMap online + `addProtocol` write-through cache to the Cache API for visited tiles (OpenFreeMap has no anti-caching term; OSM and Stadia do).

## 4. Geocoding

| Service | Key | Limit / policy | Autocomplete | FR data | Source |
|---|---|---|---|---|---|
| Nominatim public | no | max 1 req/s, identifying UA/Referer, results must be cached; "Auto-complete search … you must not implement such a service" | **forbidden** | good | https://operations.osmfoundation.org/policies/nominatim/ |
| Photon (komoot) | no | "reasonable limit", throttled/banned if extensive, no guarantees; ~1 req/s rule of thumb | **allowed** (search-as-you-type is a feature) | names in fr | https://github.com/komoot/photon, https://github.com/komoot/photon/discussions/598 |
| IGN Géoplateforme géocodage | no | 50 req/s per IP; Etalab 2.0; indexes address/poi/parcel | search needs a full token (partial "Hohn" → 0 results today) | authoritative (BAN, BD TOPO) | https://cartes.gouv.fr/aide/fr/guides-utilisateur/utiliser-les-services-de-la-geoplateforme/geocodage/ ; api-adresse.data.gouv.fr redirects and is decommissioned end of Jan 2026 (https://adresse.data.gouv.fr/blog/lapi-adresse-de-la-base-adresse-nationale-est-transferee-a-lign) |
| Geocode Earth (Pelias) | yes | 1,000 req/day free, then $100/month (UNVERIFIED, third-party summary) | yes | ok | https://geocode.earth/ |
| Stadia geocoding | yes | 20 credits/geocode, 1/autocomplete within 200k credits | yes | ok | https://stadiamaps.com/pricing |
| MapTiler geocoding | yes | 1,000 search sessions/month free | yes | ok | https://www.maptiler.com/cloud/pricing/ |
| Google Geocoding | yes+billing | 10k/month | (Places autocomplete 10k) | ok | pricing page above |
| Android `android.location.Geocoder` via plugin | no | vendor backend (Google on GMS phones), `isPresent()` may be false; online only | n/a | ok | https://developer.android.com/reference/android/location/Geocoder ; plugin @capgo/capacitor-nativegeocoder (MPL-2.0, pushed 2026-09-15; Google key only for the web platform) https://github.com/Cap-go/capacitor-nativegeocoder ; Capawesome's Geocoder is paid "Insiders" https://capawesome.io/plugins/geocoder/ |

Live tests today: Géoplateforme `reverse?index=poi` at (7.02, 48.05) → "Stosswihr" (category commune, 3,120 m), "la Petite Fecht"; at Colmar centre → "Mairie de Colmar", city Colmar. Photon `reverse?layer=city&lang=fr` at Colmar → "Colmar"; at the rural point → "Mittlach"/"Le Valtin" (with `radius=10`), default reverse → "Chaume des Trois Fours" (lieu-dit). Photon `api?q=Hohn&lang=fr&lat&lon` → "Hohneck". Géoplateforme `search?q=Hohneck&index=poi` → Hohneck (lieu-dit, sommet).

**Recommendation**: reverse → Géoplateforme (derive "Près de <commune>" from the nearest `category: commune` hit, or the `city` of the nearest POI); forward → Photon with `lat/lon` bias, `lang=fr`, debounced ≥300 ms, ≤1 req/s. Each falls back to the other; both are keyless and free. Note the `getcapabilities` of Géoplateforme lists only `search` and `reverse`; a `completion` endpoint exists but returned nothing for the test and its terms are UNVERIFIED.

## 5. Clustering and UI bits

- **MapLibre clusters**: GeoJSON source `cluster: true`, `clusterRadius` (default 50; "A value of 512 indicates a radius equal to the width of a tile", i.e. screen pixels at 512-px tiles), `clusterMaxZoom`, `clusterMinPoints` — https://maplibre.org/maplibre-style-spec/sources/. Uses Supercluster (pixel radius, constant across zooms — https://github.com/mapbox/supercluster). At lat 48°, metres/pixel ≈ 104,750 / 2^z: 500 m ≈ 78 px at z14, 20 px at z12, 5 px at z10. So a fixed pixel radius cannot mean "500 m" at all zooms.
- **Getting 500 m semantics**: do the 500 m grouping in the database (the "adjacent plants" query already exists) or once client-side with `@turf/clusters-dbscan` (`maxDistance` in km, `minPoints`; https://turfjs.org/docs/7.3.0/api/clustersDbscan) and feed cluster centroids with `count` and member ids to the map. Then let MapLibre's pixel clustering (`clusterRadius` ~30–40, `clusterMaxZoom` ~13) only merge overlapping dots at low zoom. On click use `getClusterLeaves`/`getClusterExpansionZoom` (https://maplibre.org/maplibre-gl-js/docs/examples/create-and-style-clusters/) or the DB cluster id for the bottom drawer.
- **GPS accuracy circle in metres**: simplest exact way is `turf.circle(center, radius_m/1000, {steps: 64})` → `fill` layer. Alternative pure-style: `circle-radius: ['interpolate', ['exponential', 2], ['zoom'], 0, r/(156543.03*cos(lat)), 22, r*2^22/(156543.03*cos(lat))]` (Mercator scale trick discussed at https://github.com/maplibre/maplibre-style-spec/discussions/1373).
- **Fixed centre pin**: absolutely-positioned HTML pin over the map container; read `map.getCenter()` on `moveend`. Trivial.
- **Static mini-map**: no keyless static-image API exists (MapTiler static is excluded from Free; Stadia static = 20 credits + key; Google static 10k/month + billing). Use a second MapLibre instance with `interactive: false` and controls removed (browsers allow ~16 WebGL contexts, one extra is fine), or reuse the single map instance by re-parenting its container. If a raster snapshot is preferred, render once with `canvas.toDataURL()` (needs `preserveDrawingBuffer` — v6 API name UNVERIFIED) and cache the PNG per observation.

## 6. OCaml / js_of_ocaml side

- opam `leaflet` 0.2 (added 2025-02-06; binds Leaflet 1.9.4; depends on **brr** and js_of_ocaml; BSD-2; maintainer swrup; NGI0-funded) — https://ocaml.org/p/leaflet/0.2. Its dev-repo `git.zapashcanon.fr/swrup/leaflet` refused connections today; tarball is https://release.kumikode.org/leaflet/0.2.tar.gz (API coverage UNVERIFIED).
- **No MapLibre or Mapbox bindings on opam** (https://ocaml.org/packages/search?q=maplibre → no results).
- FFI estimate: MapLibre's surface needed here is ~15 calls — `new Map({container, style, center, zoom, interactive})`, `on('load'|'moveend'|'click', cb)`, `getCenter`, `jumpTo/flyTo`, `addSource` (GeoJSON with cluster options), `addLayer`, `getSource(id).setData`, `getClusterLeaves`, `queryRenderedFeatures`, `addProtocol`, `Marker`, `resize`, `remove`. With brr's `Jv` (or `Js.Unsafe`) that is 150–300 lines. Lower effort still: a 100-line hand-written JS facade (`herbierMap.create/setPoints/onSelect/getCenter/setCenter/accuracy`) and bind only those six functions from OCaml; the JSON payloads cross the boundary as strings.

## 7. Recommendation and fallbacks

- Library: MapLibre GL JS 6.x (ESM, WebGL2). Fallback: Leaflet 1.9.4 with raster tiles if WebGL2 ever fails on the device.
- Style/tiles online: OpenFreeMap `positron` (+ optional CSS desaturation). Fallbacks in order: VersaTiles `graybeard`, IGN Plan IGN `gris`/`attenue`, Protomaps hosted (key), Stadia `alidade_smooth` (key), Thunderforest `outdoors` (key).
- Offline: on-device Protomaps PMTiles extract (Alsace+Vosges z≤14 = 237 MB; z≤12 = 61 MB if space matters), `pmtiles` protocol + OPFS/Filesystem-backed source, `@protomaps/basemaps` `white`/`grayscale` flavor. Because the app can render entirely from that file, online tiles become optional; if OpenFreeMap ever adds limits or a header requirement, nothing breaks.
- Geocoders: Géoplateforme reverse (poi index) and Photon forward; swap roles if one goes down; both keyless.
- Cost: €0, no accounts, no keys. Ops: re-run `pmtiles extract` a couple of times a year for fresh data.
- Attribution to show: "© OpenStreetMap contributors" (+ "OpenFreeMap © OpenMapTiles" when online, "© IGN" if Plan IGN or Géoplateforme results are shown).
