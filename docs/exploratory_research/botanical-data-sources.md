# Herbier — External botanical data sources

Date of research: **2026-09-15**. Every endpoint below was hit live on that date with `curl` (User-Agent `Herbier-research/0.1 (https://github.com/tbrugere/herbier)`) for *Digitalis purpurea* (GBIF 5414995, TaxRef 94959, Tela bdtfx nn 22437, Wikidata Q157555) and, where useful, *Arnica montana* (GBIF 5405976, TaxRef 83874, Tela nn 6646, Q207848). Raw responses are kept in the session scratchpad (`research/raw/`). Anything not directly observed is marked **UNVERIFIED**.

---

## Summary

### Recommended pipeline

1. **Primary key = GBIF backbone `usageKey`** (dataset `d7dddbf4-2cf0-4f39-9b2a-bb099caae36c`). Every entry path resolves to it: a `gbif.org/(xx/)species/{key}` link gives it directly; a Pl@ntNet species link carries the scientific name with author (`…/species/Digitalis%20purpurea%20L./data`) → `GET /v1/species/match?name=…&kingdom=Plantae`; a Wikipedia link → REST summary `wikibase_item` → Wikidata P846; free-text search → `species/suggest` (scientific) + `species/search?qField=VERNACULAR` (French names).
2. **Cross-ids via Wikidata hub**: `action=query&list=search&srsearch=haswbstatement:P846={key}` (one call, no SPARQL) then `wbgetentities` for P5037/P961 (POWO/IPNI), P3186 (TaxRef), P3105 (Tela), P3031 (EPPO), P3151 (iNat) and fr/en/de/it sitelinks. Coverage check (SPARQL, 2026-09-15): of 33,732 items with a Tela id, 93% have GBIF, 96% POWO, but only **31% have a TaxRef id** → for TaxRef/Tela fall back to **Tela `bdtfx/noms?masque={name}`**, whose taxon record includes `cd_nom` (= TaxRef id) and `nom_fr`.
3. **Per-source fetch, cached as raw JSON + `fetchedAt`**, refreshed on demand or after 90 days: GBIF (taxonomy, vernaculars, WCVP distributions, occurrence count, map tiles), Tela (Baseflor ecology/flowering/life form, Coste description, vernaculars, images by tag), `odata-inpn.mnhn.fr` (French vernaculars, protection, red lists), Wikipedia REST summary fr→en, Pl@ntNet images-by-organ **through GBIF's Pl@ntNet occurrence dataset** (CC BY-SA), Commons as image fallback.

### Fields → source → availability

| Field | Source (verified endpoint) | Availability | Licence |
|---|---|---|---|
| Vernacular fr | GBIF `species/{k}/vernacularNames` (source TAXREF) or `odata-inpn /taxa/{cd_nom}` `names.vernacular.fr`; Tela `nvjfl` | available | CC BY 4.0 (TAXREF on GBIF) / CC BY-SA (Tela) |
| Vernacular de/en/it | GBIF vernacularNames (Flora Helvetica, Info Flora, CoL); Tela `nvjfl?masque.lg=deu` | available (it sparser) | CC BY / CC BY-SA |
| Family | GBIF backbone | available | CC0 backbone |
| Life form ("Herbacée bisannuelle, 50–150 cm") | Tela Baseflor `type_bio.libelle` ("Hémicryptophytes (>= 1m) bisannuels"); height from Coste text ("50 cm à 1 m 50") | available / height partial (text parse) | CC BY-SA 2.0 |
| Native / introduced range | GBIF `species/{k}/distributions` rows with `source` = WCVP (TDWG codes, `establishmentMeans` INTRODUCED vs null=native) | partial (WCVP mapping incomplete for some taxa; POWO API itself blocked) | CC BY 4.0 |
| FR indigène/introduite | Tela `bdtfx/taxons/{nn}` `statut_origine.libelle`, `statut_introduction.libelle` | available | CC BY-SA |
| Protection | `odata-inpn /taxa/protections/articles/entries?taxrefId=` (+ decree/article links) | available (undocumented API) | INPN terms UNVERIFIED |
| Red list | `odata-inpn /taxa/redLists/entries?taxrefId=` (category, year, trend) | available | idem |
| Flowering months | Baseflor `floraison` ("5-9") | available | CC BY-SA |
| Habitat / ecology chips | Baseflor `carac_ecolo`, `ve_*` labels, `vi_*` indices, `chorologie` | available | CC BY-SA |
| Altitude range | none structured; Coste / Info Flora prose only | not available (text only) | — |
| Toxicity | Wikipedia fr REST summary (`description`/`extract`) + section-title scan | partial (heuristic) | CC BY-SA 4.0 |
| Photos by organ | GBIF `occurrence/search?datasetKey=7a3679ef-…&taxonKey=…&mediaType=StillImage` → `media[].title` "…: leaf/flower/fruit/bark/habit"; Tela `del:0.1/images?masque.tag=fleur` | available | CC BY-SA (Pl@ntNet, Tela) |
| Distribution map | GBIF `v2/map/occurrence/density/{z}/{x}/{y}@1x.png?taxonKey=` | available | attribute GBIF + OSM basemap |
| Outbound links | ids from Wikidata/Tela/odata | available | — |

### URL patterns to intercept

- GBIF: `https://www.gbif.org/species/{key}`, `https://www.gbif.org/{lang}/species/{key}` (e.g. `/fr/species/5414995`), `…/occurrence/{id}`.
- Pl@ntNet: `https://identify.plantnet.org/{lang}/{project}/species/{Scientific name with author, URL-encoded}/data` (without `{lang}` it 302s to `/fr/…`); observations `https://identify.plantnet.org/{project}/observations/{id}` (projects seen: `k-world-flora`, `k-middle-europe`). Images: `https://bs.plantnet.org/image/{o|m|s}/{sha1}`. What the app's Share sheet emits (text vs URL) is **UNVERIFIED**.
- Wikipedia: `https://{fr|en|de|it}.wikipedia.org/wiki/{Title}` (fr title is `Digitalis_purpurea`; `Digitale_pourpre` is a redirect).
- INPN: `https://inpn.mnhn.fr/espece/cd_nom/{cd_nom}` → 301 to `https://inpn.mnhn.fr/explorer/especes/{slug}/{cd_nom}`.
- Tela: `https://www.tela-botanica.org/bdtfx-nn-{nn}` → 302 to `…/eflore/?referentiel=bdtfx&module=fiche&action=fiche&num_nom={nn}`.
- POWO: `https://powo.science.kew.org/taxon/urn:lsid:ipni.org:names:{ipni}`; iNat `https://www.inaturalist.org/taxa/{id}`; EPPO `https://gd.eppo.int/taxon/{CODE}`.

### Key limits (2026-09-15)

- **GBIF**: no key, no fixed rate (429 under load), set User-Agent. Tiles free.
- **Wikimedia** (new 2026 limits): 200 req/min with a compliant User-Agent, **10 req/min without one**; ≤3 concurrent.
- **Pl@ntNet API**: free 500 identifications/day; taxonomy routes (`/v2/species`, `/v2/projects/{p}/species/align`) exist but "Images requires Pro plan"; quota cost of species routes not stated. Terms forbid copying Pl@ntNet content without authorisation → use the CC BY-SA GBIF dataset instead.
- **POWO JSON API**: Cloudflare-blocked for all non-browser clients (403 "Just a moment") since ~2025-11; use GBIF/WCVP or the WCVP dump (`sftp.kew.org/pub/data-repositories/WCVP/wcvp.zip`). IPNI API still open.
- **TaxRef official API** (`taxref.mnhn.fr/api/*`): all paths 301/302 to the web UI today (MNHN incident 2025-09); **`odata-inpn.mnhn.fr` works** (HAL+JSON, CORS `*`, no key, no docs — 401 on `/v3/api-docs`).
- **Tela**: no key, no documented limit.
- **iNat**: works; limits (~60 req/min, 10k/day) **UNVERIFIED**.
- **EPPO v2**: `X-Api-Key` from data.eppo.int dashboard; 2000 req / 10 s per IP; account cost UNVERIFIED.

### Top 6 links

1. GBIF API reference — https://techdocs.gbif.org/en/openapi/ (maps spec: https://techdocs.gbif.org/openapi/v2-maps.json)
2. Pl@ntNet observations on GBIF (CC BY-SA images with organ tag) — https://www.gbif.org/dataset/7a3679ef-5582-4aaa-81f0-8c2545cafc81
3. Tela eFlore API (Baseflor) — https://api.tela-botanica.org/service:eflore:0.1/baseflor/informations/bdtfx.nn:22437
4. INPN open data API (undocumented) — https://odata-inpn.mnhn.fr/taxa/94959
5. Wikidata hub — https://www.wikidata.org/w/api.php?action=query&list=search&srsearch=haswbstatement:P846=5414995&format=json
6. Wikimedia rate limits (2026) — https://www.mediawiki.org/wiki/Wikimedia_APIs/Rate_limits

---

## 1. GBIF API v1 / v2

**Base**: `https://api.gbif.org/v1/` (species, occurrence), `https://api.gbif.org/v2/` (map, species/match v2). **Auth**: none for reads. **Rate limits** (techdocs, fetched 2026-09-15): "Rapid or numerous queries to search APIs may be rate limited, depending on our server load. If this happens, you will receive an HTTP 429 error." and "If you are integrating the GBIF API into a website or app, we highly recommend you set the HTTP User-Agent to a URL or email address." No rate-limit headers are returned (`cache-control: public, max-age=3601` on species). **Licence**: backbone CC0; each checklist/occurrence dataset carries its own licence in `dataset/{key}.license`.

### 1.1 `species/suggest`
`GET /v1/species/suggest?q=Digitalis%20purp&rank=SPECIES&datasetKey=d7dddbf4-2cf0-4f39-9b2a-bb099caae36c&limit=3` → array; first item:
```json
{"key":5414995,"nameKey":3529842,"kingdom":"Plantae","phylum":"Tracheophyta","order":"Lamiales","family":"Plantaginaceae","genus":"Digitalis","species":"Digitalis purpurea","kingdomKey":6,"familyKey":2420,"genusKey":3172032,"speciesKey":5414995,"nubKey":5414995,"scientificName":"Digitalis purpurea L.","canonicalName":"Digitalis purpurea","rank":"SPECIES","status":"ACCEPTED","synonym":false,"class":"Magnoliopsida"}
```
Filters that work: `rank`, `datasetKey` (backbone), `highertaxonKey=6` (Plantae). **`suggest` does not match vernacular names** (`q=digitale pourpre` → `[]`). Use `species/search`:
`GET /v1/species/search?q=digitale%20pourpre&datasetKey=d7dddbf4-…&highertaxonKey=6&qField=VERNACULAR&limit=3` → count 3: 10263161 (hybrid), 5708907 (subsp.), **5414995** with `vernacularNames` embedded ("Digitale pourpre, Gantelée, Gant de Notre-Dame" etc.).

### 1.2 `species/match` (v1) and v2
`GET /v1/species/match?name=Digitalis%20purpurea&kingdom=Plantae` →
```json
{"usageKey":5414995,"scientificName":"Digitalis purpurea L.","canonicalName":"Digitalis purpurea","rank":"SPECIES","status":"ACCEPTED","confidence":100,"matchType":"EXACT","kingdom":"Plantae","family":"Plantaginaceae","genus":"Digitalis","speciesKey":5414995,...}
```
v2 uses `scientificName=` (not `name=`; with `name=` it silently matched *Plantae*): `GET /v2/species/match?scientificName=Digitalis%20purpurea&kingdom=Plantae` → `{"usage":{"key":"5414995","name":"Digitalis purpurea L.",…},"classification":[…7 ranks…],"diagnostics":{"matchType":"EXACT","confidence":100}}`. Pl@ntNet names carry the author ("Digitalis purpurea L."); both endpoints parse that fine.

### 1.3 `species/{key}`
`GET /v1/species/5414995` → `{"key":5414995,"nubKey":5414995,"taxonID":"gbif:5414995","family":"Plantaginaceae","familyKey":2420,"datasetKey":"d7dddbf4-…","scientificName":"Digitalis purpurea L.","canonicalName":"Digitalis purpurea","vernacularName":"Foxglove","authorship":"L.","rank":"SPECIES","taxonomicStatus":"ACCEPTED","publishedIn":"Sp. Pl.: 621 (1753)","numDescendants":6,"lastInterpreted":"2023-08-22T23:03:04.238+00:00",…}`

### 1.4 `species/{key}/vernacularNames`
`GET /v1/species/5414995/vernacularNames?limit=200` → 186 rows, 46 language codes (ISO 639-3: `fra`, `deu`, `eng`, `ita`…). Each row: `{vernacularName, language, source, sourceTaxonKey, …}`. Samples:
- fra: "Digitale pourpre" (Flora Helvetica 224055404; IUCN LR France 320344682; Info Flora 224778029; Belgian Species List), "Digitale pourpre, Digitale, Digitale pourprée" and "Digitale pourpre, Gantelée, Gant de Notre-Dame" (**TAXREF**, sourceTaxonKey 221892086 — comma-joined lists, must be split), "Digitale à fleurs blanches" (Catalogue of Life — a variety name, noise).
- deu: "Roter Fingerhut" (8 sources). eng: "Common Foxglove", "Foxglove", "Purple Foxglove". ita: "Digitale rossa" (CoL, Flora Helvetica, Info Flora).
- Arnica fra: "Arnica des montagnes" (IUCN FR, CoL, TAXREF "Arnica des montagnes, Arnica, Herbe aux prêcheurs"), "Arnica" (Flora Helvetica).
Quality: fine for fr/de/en; it depends on Swiss checklists. Prefer `source` in {TAXREF, Flora Helvetica, Info Flora, IUCN Red List (France)} and split on ", ". TAXREF checklist on GBIF: dataset `0e61f8fe-7d25-4f81-ada7-d970bbb2c6d6`, licence CC BY 4.0, modified 2025-03-14 (v18).

### 1.5 `species/{key}/media`
`GET /v1/species/5414995/media?limit=50` → 25 StillImage rows, **all from "Checklist Dutch Species Register"** (images.naturalis.nl), licences 22× CC BY-NC-ND, 2× CC BY, 1× CC BY-NC. No organ tags. Not usable as the primary image source.

### 1.6 `species/{key}/distributions`
`GET /v1/species/5414995/distributions?limit=300` → 193 rows, 92 from "The World Checklist of Vascular Plants (WCVP)" (sourceTaxonKey 207492341, dataset `f382f0ce-323a-4091-bb9f-add557f3a9a2`, licence **CC BY 4.0**, modified 2026-06-10). Row shape:
```json
{"locality":"Argentina Northeast","locationId":"TDWG:AGE","establishmentMeans":"INTRODUCED","status":null,"source":"The World Checklist of Vascular Plants (WCVP)","sourceTaxonKey":207492341}
```
WCVP rows with `establishmentMeans: null` are the natives: Belgium, Corse, Czechia-Slovakia, France, Germany, Great Britain, Ireland, Morocco, Portugal, Sardegna, Spain, Sweden (TDWG level-3). 80 rows INTRODUCED. Other sources: GRIIS (country-level invasive lists), DAISIE, IUCN Red List France 2018 (`threatStatus: LEAST_CONCERN`), red lists DE/DK/NL/NO/LU. **Caveat**: *Arnica montana* (5405976) only has 1 WCVP row (Colombia) — the backbone/WCVP link is incomplete for some taxa → "partial".

### 1.7 `descriptions` / `speciesProfiles`
`species/5414995/descriptions` (50 rows): VASCAN `habit: herb`; Info Flora / Flora Helvetica German texts: `biology_ecology` "Bluetezeit: 6 - 9 Standort und Verbreitung in der Schweiz: Lichte Waelder, Holzschlaege / kollin-mon…", `description` "Artbeschreibung: 40 - 150 cm hoch…", `conservation` "Status Indigenat: Neophyt…" (Swiss). `speciesProfiles`: Flora do Brasil lifeForm "Erva", GRIIS `habitat: terrestrial` — low value.

### 1.8 Occurrence counts and map tiles
- `GET /v1/occurrence/count?taxonKey=5414995` → `564994`; `&country=FR` → `85189`.
- `GET /v2/map/occurrence/density/0/0/0@1x.png?taxonKey=5414995&style=purpleYellow.point` → 200 image/png (5 289 B). Hex-binned: `…/4/8/5@1x.png?taxonKey=5414995&style=classic.poly&bin=hex&hexPerTile=30&srs=EPSG:3857` → 200 (76 kB). Basemap: `https://tile.gbif.org/3857/omt/{z}/{x}/{y}@1x.png?style=gbif-classic` → 200.
- `GET /v2/map/occurrence/density/capabilities.json?taxonKey=5414995` → `{"minLat":-55,"maxLat":70,"minLng":74,"maxLng":416,"minYear":1600,"maxYear":2026,"total":554486,"generated":"2026-09-15T05:00Z"}`.
- Spec (https://techdocs.gbif.org/openapi/v2-maps.json, Maps API v2): "The mapping API provides tiled web maps primarily intended for display on websites… This service is intended for use with commonly used clients such as OpenLayers or Leaflet". Params: `srs` (EPSG:3857/4326/3575/3031), `bin` hex|square, `hexPerTile`, `squareSize`, `style` (23 raster styles e.g. `classic.point`, `purpleYellow.poly`, `iNaturalist.poly`, `scaled.circles`), `year`, `basisOfRecord`, `country`, one primary key (`taxonKey`|`datasetKey`|…). No key, no tile quota stated. Basemap tiles are OpenMapTiles/OSM-derived → attribute "© OpenStreetMap contributors, © OpenMapTiles, GBIF" (wording UNVERIFIED).

### 1.9 gbif.org identifiers for interception
`https://www.gbif.org/species/{key}` and `https://www.gbif.org/{lang}/species/{key}` (`/fr/species/5414995`); occurrences `https://www.gbif.org/occurrence/{gbifID}`. `{key}` is the backbone `usageKey` used by every endpoint above.

---

## 2. Pl@ntNet

### 2.1 Official API (`https://my-api.plantnet.org`, docs `https://my.plantnet.org/doc/…`)
- Auth: `api-key` query param, key from `https://my.plantnet.org/settings/api-key` (account required).
- Free plan (pricing page, 2026-09-15): "€0 … 500 identifications/day … 50,000+ identifiable species … 50+ languages". Terms of use: "Pl@ntNet API is paying for commercial usage beyond 500 identification requests per day", "the usage of Pl@ntNet API is limited to 20 simultaneous requests per client". Pro: €1,000/year + €0.005/identification.
- **Taxonomy routes** (`/doc/api/taxonomy`): `GET /v2/projects` (`id,title,description,speciesCount`; "unlimited in usage" per quota page), `GET /v2/species` and `GET /v2/projects/{project}/species` (params `lang,type,pageSize,page,prefix,images`; returns `id, commonNames, scientificNameWithoutAuthor, scientificNameAuthorship, gbifId, powoId, iucnCategory, genus, family, images`) — **"Images feature requires Pro plan"**; `GET /v2/projects/{project}/species/align` (`name, authorship, synonyms, lang`) returns `searchedName, matchingName, acceptedName, isSynonym, family, genus, gbif.id, iucn.id, eol.id, grin.id, powo.id`. Whether `/v2/species` and `/align` consume the daily quota is not stated ("most routes … are subject to quota"). `GET /v2/quota/daily` → `{"day":"2025-02-04","quota":{"identify":{"count":3362,"total":5000,"remaining":1638},"dwc":{…}}}`.
- Terms: "No element of the Pl@ntNet application shall be copied, reproduced, modified, republished, downloaded… without the written and prior authorization from Pl@ntNet." → do **not** scrape identify.plantnet.org or reuse API images; the species-name/GBIF-id alignment is the only useful free route, and it is optional given GBIF match.

### 2.2 Legal data route: GBIF datasets
- **Pl@ntNet observations** `7a3679ef-5582-4aaa-81f0-8c2545cafc81`, licence **CC BY 4.0** (dataset), images CC BY-SA per record, modified 2025-10-20, v1.9 (DOI 10.15468/gtebaa). "The observations in this collection are the ones for which the authors agree to share the associated pictures under a creative common licence and for which the species name is considered as valid."
- `GET /v1/occurrence/search?datasetKey=7a3679ef-…&taxonKey=5414995&mediaType=StillImage&limit=2` → `count: 2713`. Record:
```json
{"key":5110295086,"occurrenceID":"o-1025531052","license":"http://creativecommons.org/licenses/by/4.0/legalcode","country":"Germany","eventDate":"2025-01-12T14:46:07Z","references":"https://identify.plantnet.org/k-middle-europe/observations/1025531052",
 "media":[{"type":"StillImage","format":"image/jpeg","identifier":"https://bs.plantnet.org/image/o/b1d46b31e711e4acd2c9dbf2cda5365e1458b589","title":"Digitalis purpurea L.: leaf","license":"Iris Selcho (cc-by-sa)","rightsHolder":"Iris Selcho","creator":"Iris Selcho"}],
 "extensions":{"http://rs.tdwg.org/ac/terms/Multimedia":[{"subjectPart":"leaf","tag":"leaf","UsageTerms":"cc-by-sa","Credit":"Iris Selcho (cc-by-sa)","accessURI":"https://bs.plantnet.org/image/o/b1d4…","associatedObservationReference":"https://identify.plantnet.org/k-middle-europe/observations/1025531052"}]}}
```
The **organ is in `media[].title` ("…: leaf") and in the Audubon Core `subjectPart`/`tag`** (values seen: leaf; Pl@ntNet organs are leaf/flower/fruit/bark/habit/other). No server-side organ filter → page a few results (limit 50) and bucket by organ client-side. Image sizes: `bs.plantnet.org/image/{o|m|s}/{sha1}` → 218 kB / 115 kB / 8 kB (all 200).
- "Pl@ntNet automatically identified occurrences" `14d5676a-2c54-4f94-9023-1e8dcd822aa0` (CC BY 4.0) had 0 image records for this taxon.

### 2.3 URL formats
- Species page: `https://identify.plantnet.org/fr/k-world-flora/species/Digitalis%20purpurea%20L./data`. Observed: `…/k-world-flora/species/…/data` without lang → **302** to `/fr/k-world-flora/species/…/data`; page HTML references `api.plantnet.org/v1/`, `bs.plantnet.org/v1/image`, `geo.plantnet.org/api/`. Page content itself could not be read (429 Too Many Requests from both the local IP and the WebFetch proxy) — organ tabs/outbound links on the page **UNVERIFIED**.
- Observation page: `https://identify.plantnet.org/{project}/observations/{id}` (from GBIF `references`); anonymous fetch 302 → `/sign_in`.
- Internal endpoints `api.plantnet.org/v2|v3/species` answer 400/404 without the app's auth; do not use.
- Share-sheet payload from the Android app: **UNVERIFIED** (docs.plantnet.org tutorial only describes in-community sharing). Register intent filters for host `identify.plantnet.org` with path patterns `/.*/species/.*` and `/.*/observations/.*`, plus `www.gbif.org/species/*`, `*.wikipedia.org/wiki/*`, `inpn.mnhn.fr/espece/cd_nom/*`, `tela-botanica.org/bdtfx-nn-*`, and treat a plain-text share by extracting the first URL or a "Genus species Author" pattern.

---

## 3. Wikipedia / Wikidata

### 3.1 REST summary
`GET https://fr.wikipedia.org/api/rest_v1/page/summary/Digitale_pourpre` (redirect followed) →
```json
{"title":"Digitalis purpurea","description":"plante extrêmement toxique dont est extraite la digitaline","extract":"Digitalis purpurea, la Digitale pourpre ou Grande Digitale, est une espèce de plantes à fleurs de la famille des Scrophulariaceae … C'est une plante herbacée originaire de l'ouest et du sud-ouest de l'Europe ainsi que du Maroc. C'est une grande digitale bisannuelle ou vivace… La plante est extrêmement toxique. Elle est appelée parfois Doigtier, Gant-de-Notre-Dame, Gant-de-bergère, Gantelée, Gantière ou Gantillier.","thumbnail":{"source":"https://thumb.wikimedia.org/…/330px-Digitalis_purpurea_Koehler_drawing.jpg","width":330,"height":411},"originalimage":{…},"wikibase_item":"Q157555","lang":"fr","timestamp":"2026-03-30T10:26:11Z","content_urls":{"desktop":{"page":"https://fr.wikipedia.org/wiki/Digitalis_purpurea"}}}
```
en: "Digitalis purpurea, the foxglove or common foxglove, is a toxic species of flowering plant…". Arnica fr: title "Arnica des montagnes", description "espèce de plantes". Headers: `cache-control: s-maxage=1209600, max-age=300`, `access-control-allow-origin: *`.

### 3.2 Wikidata hub
- Lookup without SPARQL: `GET https://www.wikidata.org/w/api.php?action=query&list=search&srsearch=haswbstatement:P846=5414995&format=json` → `{"query":{"searchinfo":{"totalhits":1},"search":[{"title":"Q157555",…}]}}`.
- `GET …?action=wbgetentities&ids=Q157555&props=claims|sitelinks|labels&languages=fr|en|de|it` → claims: P846 `5414995`; P5037 `urn:lsid:ipni.org:names:802077-1`; P3186 `94959`; P3105 `22437`; P3031 `DIKPU`; P961 `802077-1`; P3151 `53983`; P1843 (taxon common name, monolingual): en Foxglove, de Roter Fingerhut, es Dedalera común, ca… (no fr in first 8); P18 images; P935/P373 Commons gallery/category "Digitalis purpurea"; sitelinks frwiki "Digitalis purpurea", enwiki "Digitalis purpurea", dewiki "Roter Fingerhut", itwiki "Digitalis purpurea", commonswiki, specieswiki. `props=sitelinks/urls&sitefilter=frwiki|enwiki|dewiki|itwiki` returns full URLs.
- SPARQL equivalent (`https://query.wikidata.org/sparql`, `Accept: application/sparql-results+json`) returned the same in one query; Arnica: Q207848 → POWO 30090722-2, TaxRef 83874, Tela 6648 (note: Tela API says accepted nn is **6646**; Wikidata's 6648 is a different name record — verify Tela ids via `bdtfx/noms` before use), EPPO ARXMO, iNat 56229.
- **Coverage (SPARQL 2026-09-15)**: items with Tela id: 33,732 → with TaxRef 10,532; POWO 32,305; GBIF 31,324; iNat 16,486. Items with TaxRef id: 201,090 → GBIF 197,975; POWO 27,725; Tela 10,345. So GBIF↔POWO↔Tela via Wikidata is good for plants; **TaxRef via Wikidata is poor (≈31%)** → get `cd_nom` from Tela (`bdtfx/taxons/{nn}.cd_nom`) or `odata-inpn /taxa?scientificNameFragment=`.
- Rate limits (https://www.mediawiki.org/wiki/Wikimedia_APIs/Rate_limits, "new in 2026"): "Unidentified — Requests with no identifying characteristics other than IP address: **10** req/min"; "User-Agent only — Unauthenticated bot requests with a compliant User-Agent header: **200** req/min"; "limit the number of concurrent requests to 3 or fewer"; "respect the Retry-After header". User-Agent must include contact info, e.g. `Herbier/1.0 (https://…; email)`.

### 3.3 Toxicity extraction — what is realistic
- `action=parse&page=Digitalis_purpurea&prop=sections&redirects=1` (fr) → sections: Étymologie et noms vernaculaires, Caractéristiques botaniques, Appareil végétatif, Appareil floral, Taxonomie, …, Distribution et habitat, Propriétés médicinales, Galerie, Culture… → **no "Toxicité" section**; toxicity lives in the intro and the Wikidata description. en has section 10 "Toxicity". Arnica fr has "Contre-indications et toxicité" (level 3, index 26).
- `action=query&prop=extracts&explaintext=1&exsectionformat=wiki&redirects=1` returns plain text with `== Heading ==` markers (8 714 chars for fr Digitalis) — cheap to scan.
- Realistic algorithm: (1) show REST `description` + first sentence(s) of `extract` matching /toxi|vénén|poison|danger/i; (2) scan section titles for /toxi|vénén|poison|contre-indication|danger/i in fr then en, fetch that section via `action=parse&page=…&section={index}&prop=wikitext|text` and show the first paragraph; (3) else "non renseigné". Mark as heuristic in the UI. Licence CC BY-SA 4.0 with link to the article.

---

## 4. POWO / Kew

- `GET https://powo.science.kew.org/api/2/search?q=Digitalis%20purpurea` and `/api/2/taxon/urn:lsid:ipni.org:names:802077-1?fields=distribution` → **403, Cloudflare "Just a moment…" challenge** with curl UA, Chrome UA and `python-requests` UA alike (2026-09-15). The taxon HTML page is also challenged. `robots.txt` (Cloudflare managed) disallows a list of AI crawlers.
- pykew issue #12 "API stopped working" (opened 2025-11-20): endpoints first moved from plantsoftheworldonline.org to powo.science.kew.org, then comment 2026-07-22: "Now the requests are blocked by Cloudflare bot protection. Is there any other way?" (no maintainer answer). → **Treat the POWO JSON API as unavailable**; keep only the outbound link.
- **IPNI API still open**: `GET https://www.ipni.org/api/1/search?q=Digitalis%20purpurea` → `{"totalResults":16,…,"results":[{"name":"Digitalis purpurea","authors":"L.","rank":"spec.","url":"/n/802077-1","family":"Scrophulariaceae","inPowo":true,…}]}` (beta.ipni.org timed out). Gives the IPNI id → POWO link.
- **Offline alternative**: `https://sftp.kew.org/pub/data-repositories/WCVP/` lists `wcvp.zip`, `wcvp_dwca.zip`, `Archive/` (200, 2026-09-15). Kew's terms-of-use page returned 403 to non-browser fetches; the WCVP checklist as published on GBIF is **CC BY 4.0** (verified via GBIF dataset metadata). Kew site wording UNVERIFIED.
- Practical source for native/introduced: GBIF distributions filtered to WCVP (section 1.6).

---

## 5. INPN / TaxRef

### 5.1 Official TaxRef API — down / relocated
`https://taxref.mnhn.fr/api/taxa/94959` → **302 → https://inpn.mnhn.fr/** (also with `Accept: application/json`, browser UA, `.json`, `?format=json`); `/api/v3/api-docs`, `/api/v2/api-docs`, `/api/swagger-ui.html`, `/api/v1/...` → 301 → `https://taxref.mnhn.fr/taxref-web`. The TAXREF-Web "Documentation de l'API" page (`/taxref-web/api/doc`) still embeds Swagger UI pointing at `https://taxref.mnhn.fr/api/v2/api-docs`, which itself 301s. Web search results mention a September 2025 intrusion at MNHN with services progressively restored; TAXREF v18 (2025-01-09) remains downloadable at `https://inpn.mnhn.fr/telechargement/referentielEspece/taxref/18.0/menu` (200) and on data.gouv.fr. Legal page (`/taxref-web/mentions`): "Le site taxref.mnhn.fr ainsi que les données diffusées via l'API-TAXREF sont gérés et édités par PatriNat … La diffusion des données est définie par les mentions légales du site de l'INPN" (INPN legal page is a JS SPA — text UNVERIFIED). TAXREF checklist on GBIF: CC BY 4.0.

### 5.2 Working alternative: `https://odata-inpn.mnhn.fr` (HAL+JSON, undocumented)
Backs the new INPN species pages. No key; CORS `access-control-allow-origin: *`; `cache-control: max-age=14400`; `/v3/api-docs`, `/swagger-ui` → 401; `/about` → `{"taxrefVersion":18,"habrefVersion":7}`. Root lists templated links (`taxa{?childrenOfTaxrefId,taxrefIds,nameFragment,vernacularFrNameFragment,scientificNameFragment,ranks,domain,protected,threatened,biogeographicStatuses,hasPhoto,page,size,sort}`, `taxa/names`, `taxa/protections/{articles,decrees,articles/entries}`, `taxa/redLists/entries`, `photos/taxa{?taxrefId}`, `habitats{?taxrefId}`, `areas`, `datasets`).
- `GET /taxa/94959` →
```json
{"taxrefId":94959,"names":{"binomial":"Digitalis purpurea","scientific":"Digitalis purpurea L., 1753","vernacular":{"fr":["Digitale pourpre","Gantelée","Gant de Notre-Dame"],"en":["Foxglove"]}},"rank":"SPECIES","domain":"CONTINENTAL","statuses":["RED_LIST","REGULATED","ZNIEFF_DETERMINANT"],"hasDescription":false,"_links":{"taxonomy":…,"protectionEntries":{"href":"…/taxa/protections/articles/entries?taxrefId=94959"},"redListEntries":{"href":"…/taxa/redLists/entries?taxrefId=94959"},"photos":…,"synonyms":{"href":"…/taxa/names/94959/synonyms"},"medias":…}}
```
- Search: `GET /taxa?nameFragment=Digitalis%20purpurea&size=5` → 3 taxa (762153 subsp., **94959**, 1020840 hybrid) with vernaculars and status flags. (`scientificNames=`/`scientificName=` are ignored → returns everything; use `nameFragment` or `scientificNameFragment`.)
- Protection: `GET /taxa/protections/articles/entries?taxrefId=83874` (Arnica) → many entries each linking `protectionDecree` (`/taxa/protections/decrees/648`) and `protectionArticle` (`/taxa/protections/articles/27`); Digitalis has 1 entry (decree 728, article 190 — a regional regulation, hence `REGULATED`). Follow the links for names/scope.
- Red lists: `GET /taxa/redLists/entries?taxrefId=94959` → `[{"category":"LC","categoryDescription":"Préoccupation mineure","evaluationYear":2014,"taxonRankEval":"SPECIES","_links":{"redList":"…/taxa/redLists/2"}}, {"category":"LC","trend":"STABLE",…"redLists/1059"}, …]` (national + regional lists; resolve list names via `/taxa/redLists/{id}`).
- Photos: `GET /photos/taxa?taxrefId=94959` → `{"copyright":"P. Rouveyrol","licence":"CC BY-NC-SA","_links":{"image":"…/photos/images/1/117811.jpg","thumbnail":…}}` (NC licence — link only).
- `GET /taxa/94959/medias` → `{"inpnTaxonPage":"https://inpn.mnhn.fr/espece/cd_nom/94959"}`. `/description` 404 for this taxon. Biogeographic status per territory (indigène/introduite) is only available as a *filter* (`biogeographicStatuses`) on `/taxa`, not as a field → use Tela `statut_origine` for the FR status chip, or probe `/taxa?taxrefIds=94959&biogeographicStatuses=P` (untested).
- Terms/rate limits: none published; Cloudflare-fronted. Because it is undocumented, wrap it behind a feature flag and cache aggressively.

### 5.3 INPN URL format
`https://inpn.mnhn.fr/espece/cd_nom/94959` → 301 → `https://inpn.mnhn.fr/explorer/especes/digitalis_purpurea/94959` (title "Digitalis purpurea - INPN"). Intercept both; `cd_nom` is the last path segment in both.

### 5.4 Best French vernacular source
TAXREF names (via GBIF `vernacularNames` source "TAXREF", or `odata-inpn names.vernacular.fr` already split into a list) are the reference set; Tela `nvjfl` adds regional/synonymous names (8 fr names for Digitalis incl. "Grande Digitale", "Doigtier", "Gant-de-bergère") with a `conseil_emploi` flag ("Recommandé ou typique").

---

## 6. Tela Botanica (eFlore API `https://api.tela-botanica.org/service:eflore:0.1/…`)

No key, no auth, JSON, all 200 on 2026-09-15. Licence: site legal page — "Toutes les images de plantes sont issues des données des telabotanistes et sont sous licence CC BY-SA (2.0). Certaines photographies … CC BY-SA 4.0" and "Sauf mention contraire, tout le contenu du site Tela Botanica est mis à disposition sous un contrat Creative Commons BY-SA (4.0) ou (2.0) selon les données." Baseflor metadata: citation "Julve, Ph., 1998 ff. - Baseflor. Index botanique, écologique et chorologique de la flore de France. Version : 19 mars 2012" (API data version 2012_03_19; a June-2024 dump is on the Tela downloads page, reported as ODbL/CC BY-SA — UNVERIFIED). `robots.txt` asks `Crawl-delay: 5`/`15` for the website; the API host has no robots.

- Name lookup: `GET bdtfx/noms?masque=Digitalis%20purpurea&retour.format=min` → `{"entete":{"total":"1"},"resultat":{"22437":{"nom_sci":"Digitalis purpurea","nom_sci_complet":"Digitalis purpurea L. [1753, Sp. Pl., 2 : 621]","retenu":"true"}}}`; Arnica → nn **6646**.
- Taxon: `GET bdtfx/taxons/22437` → includes `famille: Plantaginaceae`, `nom_fr: Gantelée`, `nom_fr_norm: Digitale pourpre au sens large`, `presence.libelle: Présent`, **`statut_origine.libelle: "Natif (=indigène)"`, `statut_introduction.libelle: "Non introduit"`**, `presence_Ga`/`presence_Co` (France/Corse), **`cd_nom: "94959"`** (TaxRef), `num_taxonomique: 5324` (nt), `2n: 56`, `flore_coste_num: 2707`, `maj_modif: 10/12/2023`.
- **Baseflor**: `GET baseflor/informations/bdtfx.nn:22437` →
```json
{"nom_sci":"Digitalis purpurea L.","chorologie":"méditerranéen-atlantique","inflorescence":"racème simple","sexualite":"hermaphrodite","pollinisation":"entomogame","fruit":"capsule","dissemination":"épizoochore","couleur_fleur":"rose","floraison":"5-9","type_ligneux":"","hauteur_veg_max":"","form_vegetale":"hémicryptophytaie","carac_ecolo":"mégaphorbiaies pionnières de clairières acidophiles planitiaires-collinéennes","ind_phytosocio":"Epilobion angustifolii Soó 1933 em. Tüxen 1950","type_bio.code":"Hbis","type_bio.libelle":"Hémicryptophytes (>= 1m) bisannuels","ve_lumiere.libelle":"hémihéliophiles (10 000 lux)","ve_temperature.libelle":"planitiaires thermophiles … (T≈12°C)","ve_continentalite.libelle":"océaniques (AT≈17°C)","ve_humidite_edaph.libelle":"mésohydriques (jamais inondé…)","ve_reaction_sol.libelle":"acidophiles (4,5<pH<5,0)","ve_nutriments_sol.libelle":"méso-eutrophiles (≈750 µg N/l)","ve_salinite.libelle":"ne supportant pas le sel","ve_texture_sol.libelle":"sable fin","ve_mat_org_sol.libelle":"mull acide","vi_lumiere":"7","vi_reaction_sol":"5","vi_nutriments_sol":"3",…}
```
`hauteur_veg_max` is empty here (populated for some taxa). `baseflor/aide` reports services `informations` and `meta-donnees` UP, `ontologies` and `graphiques` DOWN (yet `baseflor/ontologies/TB:Hbis` answered: "Hémicryptophytes (>= 1m) bisannuels", complements "hémicryptophytaie (magno- et parvo-)").
- **Coste description** (French, 1900s flora, public domain text): `GET coste/textes?masque.nn=22437` → "2707. – Digitalis purpurea L. – Digitale pourprée. – Plante bisannuelle ou vivace de 50 cm à 1 m. 50, tomenteuse-blanchâtre… Lieux incultes et champs en friche des terrains siliceux… = Mai-septembre." → source for "Herbacée bisannuelle, 50–150 cm" and habitat prose.
- **Vernaculars**: `GET nvjfl/noms-vernaculaires?masque.nt=5324&masque.lg=fra` → 8 names; `masque.lg=deu` → "Roter Fingerhut"; each name record has `conseil_emploi` and `genre`.
- **Images by organ**: `GET service:del:0.1/images?masque.nn=22437&navigation.limite=1&masque.tag=fleur` → `entete.total` 106 (feuille 46, fruit 16, port 45, ecorce 2, graine 1); result rows: `{"id_image":"2319183","binaire.href":"https://api.tela-botanica.org/img:002319183XL.jpg","mots_cles_texte":…,"observation":{"determination.ns":"Digitalis purpurea L.","auteur.nom":"Tony Le Huu","date_observation":"2019-05-27","zone_geo":"14130 Saint-André-d'Hébertot, France",…}}` (author email is exposed — do not display). Untagged pool: `eflore:0.1/cel/images?masque.nn=22437` → 506 images. Size suffixes verified: `CRS` (38 kB), `S` 51 kB, `M` 102 kB, `L` 169 kB, `XL` 261 kB, `X2L` 387 kB (`https://api.tela-botanica.org/img:{9-digit id}{SIZE}.jpg`).
- Protection statuses: `sptb/statuts?masque.nn=22437` returns a large per-zone aggregate (ZNIEFF déterminante Oise, etc.) — usable but odata-inpn is cleaner. `chorodep` (departmental presence) returned null for this taxon.
- Species page URL: `https://www.tela-botanica.org/bdtfx-nn-22437` → 302 → `https://www.tela-botanica.org/eflore/?referentiel=bdtfx&module=fiche&action=fiche&num_nom=22437&onglet=synthese`.
- Stability: the API is a 2012-era PHP service with no SLA and some services marked DOWN; cache everything and degrade gracefully. Alternatives if it breaks: the Baseflor spreadsheet dump (Tela downloads page) bundled offline; Info Flora texts via GBIF descriptions (German, Swiss); FloraVeg.EU has no public API (checked homepage, none advertised).

---

## 7. Others

- **iNaturalist** (`https://api.inaturalist.org/v1`, no key): `taxa?q=Digitalis%20purpurea&locale=fr&rank=species` → `{"id":53983,"preferred_common_name":"digitale pourpre","observations_count":110352,"default_photo":{"medium_url":"https://inaturalist-open-data.s3.amazonaws.com/photos/179728943/medium.jpeg","license_code":"cc-by-nc","attribution":"(c) z7nikon, some rights reserved (CC BY-NC), uploaded by z7nikon"}}`; `taxa/53983?locale=fr` → 12 `taxon_photos` (licences cc-by-nc, cc-by-nc-nd, or null = all rights reserved; `original_dimensions`), `conservation_statuses`; `taxa/autocomplete?q=digitale%20pourpre&locale=fr` works. Organ-ish images: `observations?taxon_id=53983&photo_license=cc-by,cc0,cc-by-sa&term_id=12&term_value_id=13&quality_grade=research` (controlled term 12 "Flowers and Fruits": 13 Flowers, 14 Fruits or Seeds, 15 Flower Buds; 36 "Leaves") → 7 458 results with `photos[].license_code` (cc0 seen). No rate-limit headers; the "API recommended practices" page is Cloudflare-gated → the usual ~60 req/min, 10 000 req/day figures are **UNVERIFIED**.
- **EPPO** (`https://api.eppo.int/gd/v2`, OpenAPI 2.0.4 of 2026-07-04 at `https://api.eppo.int/gd/v2/eppo_api_gd_v2.yml`): "An API key is required… generate your token from the dashboard at https://data.eppo.int" (header `X-Api-Key`; account creation cost UNVERIFIED, historically free). "Rate Limiting (Effective 2026-05-22): Maximum 2000 requests per IP address within a 10-second sliding window". Endpoints: `/tools/name2codes?name=`, `/tools/search`, `/taxons/taxon/{EPPOCODE}/{overview,names,taxonomy,categorization,distribution,photos,…}`. Without key: `{"error":"API key is missing"}` (401). Legacy `data.eppo.int/api/rest/1.0/taxon/DIKPU/names` → 403 without token. Data licence UNVERIFIED. Value for Herbier: low (EPPO code only for a link).
- **Wikimedia Commons**: `commons.wikimedia.org/w/api.php?action=query&generator=categorymembers&gcmtitle=Category:Digitalis%20purpurea&gcmtype=file&prop=imageinfo&iiprop=url|extmetadata&iiurlwidth=400` → thumbs + `LicenseShortName` (CC BY-SA 3.0/4.0, CC0) + `Artist`; Wikidata P18 file → same imageinfo call. Good fallback for a hero image; no organ tags.
- **Trefle** (`trefle.io`): alive, "still in beta", 399,174 species; API requires a token (`/api/v1/plants/search` → 401); licence/limits not checked (UNVERIFIED). **Perenual**: key required, tiered plans, `species-list?key=` (not verified beyond docs page; low botanical quality). **Open Tree of Life** `tnrs/match_names` works but adds nothing. **FloraVeg.EU**: no API.
- Images-by-organ, legally: Pl@ntNet-via-GBIF (CC BY-SA, `subjectPart`), Tela DEL tags (CC BY-SA), iNat annotations (filter `photo_license`).

---

## 8. Reference pipeline, caching and licences

1. **Resolve** → `gbifKey` (species/match or link parse). Store `scientificName`, `canonicalName`, `family`, `rank`, `status`.
2. **Ids** → Wikidata (`haswbstatement:P846`) → `{qid, ipni, taxref?, tela?, eppo?, inat?, sitelinks}`; then Tela `bdtfx/noms?masque=canonicalName` → `{telaNn, telaNt, cd_nom}` (authoritative for Tela/TaxRef); optional IPNI search if P5037 missing.
3. **Fetch** (parallel, each independently cacheable, each with `source`, `licence`, `fetchedAt`, `sourceUrl`):
   - GBIF vernaculars (filter languages fra/deu/eng/ita; prefer TAXREF / Flora Helvetica / Info Flora / IUCN FR; split comma lists; dedupe case-insensitively).
   - GBIF distributions → WCVP native/introduced TDWG lists; occurrence count (world, FR); map tile URLs (not cached bodies).
   - Tela Baseflor (flowering, life form, ecology chips), Tela taxon (statut_origine), Coste text (height regex `(\d+)\s*cm à (\d+) m`), nvjfl names.
   - odata-inpn taxon (+protection entries → decree/article names, red-list entries → list names).
   - Wikipedia REST summary fr (fallback en/de/it via sitelinks) + toxicity heuristic.
   - Images: GBIF occurrence search on Pl@ntNet dataset (limit 50) bucketed by organ; fallback Tela DEL per tag; fallback Commons/Wikidata P18. Store URL + attribution + licence; never re-host.
4. **Refresh** when >90 days or on user demand; on any 4xx/5xx keep the stale block and show its date.
5. **Licences for display in a personal app**: GBIF backbone CC0; TAXREF/WCVP/Pl@ntNet datasets CC BY 4.0 (show "Source: …" line); Tela data/images CC BY-SA (attribute author + "CC BY-SA"; share-alike only bites if you redistribute derived datasets); Wikipedia text CC BY-SA 4.0 (link to article); Pl@ntNet photos CC BY-SA per photo (`Credit` field); INPN photos CC BY-NC-SA (fine for non-commercial personal use, still attribute); iNat photos mostly CC BY-NC (attribute) or all-rights-reserved (skip `license_code: null`). Do not scrape identify.plantnet.org or POWO pages (terms / Cloudflare).

### Field availability recap
available: vernaculars fr/de/en (it partial), family, life form, flowering, ecology chips, FR native status, protection, red list, images by organ, distribution map, all outbound links. partial: native/introduced range (WCVP mapping gaps), height (text parse), toxicity (heuristic). not available: structured altitude range.
