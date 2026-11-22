# Plant toxicity sources for Herbier (per organ) — 2026-11-22

Status: postponed by the user (2026-11-22); the 4f « Toxicité » row stays the Wikipedia sentence.

Question: is there a source of plant toxicity, ideally per organ (berries,
leaves, roots, seeds, sap...), to humans and possibly animals, usable by a
personal Android app (WebView at https://localhost) for mostly wild French /
European flora? Today the species page's « Toxicité » row is the first
sentence of the Wikipedia summary that mentions toxicity
(`app/refs/projection.ml`, `toxicity`).

Test taxa: Digitalis purpurea, Taxus baccata, Arum maculatum, Sambucus nigra
(berries edible cooked, rest toxic), Urtica dioica (not toxic), Aconitum
napellus, Convallaria majalis.

Everything below marked "verified" was fetched with curl (or WebFetch when
curl was blocked) on 2026-11-22. "Not verified" means I could not reach or
read it; nothing here is invented.

## TL;DR

- **Best structured, open, per-organ source: Agroscope TPPT (Toxic Plants –
  Phytotoxin database).** 844 Swiss / Central-European species, a
  `Toxic_plant_part` field, a human and an animal severity scale, 1586
  linked phytotoxins (with PubChem CIDs). SQLite/XLSX download, 1.2 MB.
  Licence on opendata.swiss: `terms_by` ("open use, must provide the
  source", commercial use allowed). Static since 2018, so it is an offline
  bundle, not an API. Covers all 7 test taxa.
- **Best French-language per-organ complement: fr.wikipedia « Liste de
  plantes toxiques »**, one wikitable of ~185 rows with columns *Substances
  toxiques / Organes toxiques / Principaux symptômes / Espèces sensibles*.
  CC BY-SA 4.0, MediaWiki API with `origin=*` (CORS-open). Covers 6/6 toxic
  test taxa, and its organ column is the only one that gets Sambucus right
  ("fruits immatures").
- No source has a clean, machine-readable, per-organ *and* per-preparation
  model (e.g. "elder berries: edible cooked, toxic raw"). Wikidata has no
  toxicity modelling at all beyond a 30-item "poisonous plant" class.
- The richest per-organ prose (PFAF "Known Hazards", Toxiplante, CliniTox,
  BfR, INCHEM PIMs) is copyrighted: link-out only, no bundling.
- Recommendation: bundle TPPT (matched to GBIF keys offline) as the
  structured layer; overlay the fr.wikipedia list's organ text when present;
  keep the Wikipedia-article sentence as a last fallback; add PFAF /
  Toxiplante as outbound links. Details in "Recommendation".

## Comparison table

| Source | Coverage | Per organ | Severity | Compounds | Access | CORS | Licence | Match key | Status |
|---|---|---|---|---|---|---|---|---|---|
| **Agroscope TPPT** | 844 spp., CH / Central Europe (incl. garden + agri plants) | yes, short EN field (84 distinct values) | human + animal scale (weak/toxic/strong/very strong, allergenic, phototoxic...) | 1586, with CAS, InChIKey, PubChem CID | bulk SQLite / XLSX | n/a (bundle) | opendata.swiss `terms_by`: open use, cite source | Latin name + author (GBIF match works) | static, v2018, metadata touched 2025 |
| **fr.wikipedia « Liste de plantes toxiques »** | ~185 rows, France-oriented | yes, FR column « Organes toxiques » | no scale | yes (FR text, wikilinks) | MediaWiki API (wikitext) | yes (`origin=*`) | CC BY-SA 4.0 | Latin name | living, editable |
| de.wikipedia « Liste giftiger Pflanzen » | ~66 rows (many at genus level) | yes « Giftige Teile » | yes « Einstufung » (GIZ Bonn) | yes | MediaWiki API | yes | CC BY-SA 4.0 | Latin name | living |
| en.wikipedia « List of poisonous plants » | ~150 rows | in free-text Description only | no | in text | MediaWiki API | yes | CC BY-SA 4.0 | Latin name | living |
| fr.wikipedia species articles (current fallback) | per article | prose | no | prose | REST / API | yes | CC BY-SA 4.0 | sitelink via Wikidata | 4/6 toxic test taxa have a toxicity section |
| Wikidata | all taxa | **no** model | no | `P703 found in taxon` (LOTUS, hundreds per taxon, no toxicity) | SPARQL | yes | CC0 | QID / P846 GBIF | "poisonous plant" class has 30 members |
| PFAF « Known Hazards » | ~7000+ spp., temperate | yes, EN prose | implicit in prose | sometimes | HTML scraping only | no ACAO header | **© Ken Fern / PFAF, all rights reserved** (images CC BY-NC-ND) | Latin name URL | maintained |
| Toxiplante.fr | 148 monographs, FR | yes, FR prose | prose | yes (detailed) | HTML only | not checked | **reproduction forbidden** (mentions légales) | page slug | hobby site, pharmacists |
| CliniTox / giftpflanzen.ch (UZH Vetpharm) | ~220 plants, CH | yes, DE prose | +/++/+++ | yes | HTML only | not checked | copyrighted (university site) | page id | old but online |
| BfR « Risiko Pflanze » (DE) | ~50 plants | « Giftige Teile » for some | +/++/+++ | coarse | PDF brochure | n/a | publication, no open licence | German names | 2010 brochure |
| INCHEM PIMs (WHO/IPCS) | ~34 plant monographs | yes (§3.2 "Parties toxiques") | prose | yes | HTML | not checked | WHO copyright | Latin name | frozen (1990s) |
| Arrêté du 4 sept. 2020 (FR) | 59 taxa in 4 lists (ingestion 20) | **no** (only name + vernacular) | category only | no | Légifrance (403 to curl; PISTE API needs OAuth) | n/a | official text, free reuse | Latin name | in force |
| ANSES fiches / avis / CAP-TV reports | ~tens of plants | yes (PDF), not verified | yes in 2022-SA-0042 (28 plants ranked) | — | PDF, bot-challenge (CrowdSec) | n/a | no open licence stated (not verified) | — | current |
| GRIN Taxonomy (USDA) | world | no | flag "Vertebrate poisons: mammals" + refs | no | HTML (JS-free) | not checked | US gov, public domain | GRIN id / name | maintained |
| ASPCA | ~1000 spp., US pets | no | toxic / non-toxic per dog/cat/horse | "toxic principles" | HTML | not checked | © ASPCA | common name slug | maintained |
| Cornell Poisonous Plants | ~100 spp., livestock, NE US | partial prose | prose | prose | HTML | not checked | © Cornell | Latin name | old |
| KNApSAcK | metabolites per species | no | no | yes (172 for Taxus baccata) | HTML | not checked | no open licence | Latin name | maintained |
| Pl@ntUse (PlantNet) | wiki pages | prose in description, no section | no | no | MediaWiki API | yes (`origin=*`) | not found in siteinfo (not verified) | page title | maintained |
| Tela Botanica Baseflor / eFlore | French flora | **no toxicity field** in Baseflor | — | — | REST | ACAO only tela-botanica.org | CC BY-SA | BDTFX nn | maintained |
| FDA PLANTOX | — | — | — | — | **404, decommissioned Jan 2022** | — | — | — | dead |
| Canadian Poisonous Plants IS (CBIF) | ~260 names in LOD mirror | no | no | no | linkdata.org TSV (names only) | — | the "CC0" there belongs to an unrelated table | Latin name | **decommissioned 2021** |
| CNITV (VetAgro Sup) | Vtox case DB | — | — | — | **no public database** (paid phone service) | — | — | — | — |

## Evidence per source

### 1. Agroscope TPPT (verified, downloaded)

Page: https://www.agroscope.admin.ch/en/toxic-plants-phytotoxin-tppt-database
Downloads: `https://www.agroscope.admin.ch/dam/en/sd-web/NBRXfMO1Wj9m/tppt-db.zip`
(SQLite, 1.19 MB zipped, 3.6 MB `tppt-db.db`) and `.../ty8Qf1mgVGOk/tppt-xls.xlsx`.
Paper: Günthardt et al. 2018, J. Agric. Food Chem., doi:10.1021/acs.jafc.8b01639.

Licence, from the opendata.swiss CKAN API (needs a browser User-Agent):

```
curl -A 'Mozilla/5.0 ... Chrome/130' \
  'https://opendata.swiss/api/3/action/package_show?id=giftpflanzen-phytotoxin-datenbank'
ZIP | rights: https://opendata.swiss/terms-of-use#terms_by | .../tppt-db.zip
XLS | rights: https://opendata.swiss/terms-of-use#terms_by | .../tppt-xls.xlsx
issued 2018-06-25, modified 2025-10-23
```

`terms_by` = "Open use. Must provide the source. Use for commercial purposes
permitted" (opendata.swiss standard). Equivalent in practice to CC BY.

Main table `Toxic_plant_species(Plant_number, Latin_plant_name,
German_plant_name, English_plant_name, Plant_genus, Plant_family,
Global_spatial_distribution, Swiss_frequency, ..., Toxic_plant_part,
Human_toxicity, Animal_toxicity, Invasive_foreign, Garden_plant,
Agricultural_plant)`; plus `Phytotoxins` (CAS, InChIKey, SMILES, PubChem
CID), `Phytotoxin_toxic_plant_species_relationships`, `Toxicity_data`
(LD50 per test animal / route), `Bibliography`.

```
sqlite3 tppt-db.db "select Latin_plant_name, Toxic_plant_part, Human_toxicity, Animal_toxicity
  from Toxic_plant_species where Latin_plant_name like 'Taxus baccata%' or ..."
Taxus baccata L.       | Whole plant without aril (red seed coat)                   | strong toxic      | very strong toxic
Aconitum napellus aggr.| Whole plant, highest concentrations in root, seed          | very strong toxic | very strong toxic
Urtica dioica L.       | Leaf                                                       | allergenic, skin-irritating |
Digitalis purpurea L.  | Whole plant                                                | very strong toxic | very strong toxic
Sambucus nigra L.      | Whole plant                                                | weak toxic        | toxic
Arum maculatum L.      | Leaf (or whole plant)                                      | very strong toxic | strong toxic
Convallaria majalis L. | Whole plant, highest concentrationt in flower, fruit       | very strong toxic | very strong toxic
```

Value sets: `Human_toxicity` = very strong toxic (43), strong toxic (72),
toxic (314), weak toxic (149), toxic (unknown strength) (50), nontoxic (38),
allergenic (49), phototoxic (35), skin-irritating (42), carcinogenic (11),
liver toxic (5), ... `Animal_toxicity` adds per-species qualifiers
("very strong toxic (cat)", "toxic (horse)"...). `Toxic_plant_part` top
values: Whole plant 286, Aerial part (or whole plant) 71, empty 61, Aerial
part 46, Fruit, leaf (or whole plant) 32, Whole plant, highest
concentrations in seed 29, Latex, seed (or whole plant) 23, ... (84
distinct strings: a small closed vocabulary, easy to map to French).

Compounds, e.g. Sambucus nigra: Prunasin; Sambunigrin; Zierin; Holocalin.
Taxus baccata: Taxine B, Taxine A, Taxol, baccatins... (22).

Coverage spot-check beyond the test taxa: present — Nerium oleander,
Ecballium elaterium, Ricinus communis (Seed), Bryonia dioica, Datura
stramonium, Colchicum autumnale, Solanum dulcamara, Ilex aquifolium, Viscum
album, Atropa bella-donna, Paris quadrifolia, Euonymus europaeus. Absent —
Coriaria myrtifolia, Daphne gnidium, Thapsia garganica, **Oenanthe crocata**
(Atlantic / Mediterranean species: the Swiss scope shows).

Quality caveats: Sambucus nigra is "Whole plant / weak toxic", no hint that
ripe cooked berries and flowers are eaten; Hedera helix human toxicity is
only "allergenic" (berries ignored). The per-organ field is coarse
("Whole plant" for 1/3 of rows). Data frozen in 2018.

Matching: Latin names carry authors and sometimes "aggr." (10), "spp." /
"sp." (22), infraspecific (31). GBIF `species/match` resolves them:
`Taxus baccata L.` → 5284517 EXACT; `Aconitum napellus aggr.` → 3033665
(HIGHERRANK, same key Wikidata gives); `Sambucus nigra L.` → 2888728 EXACT.
So an offline GBIF-key table is cheap to build.

### 2. fr.wikipedia « Liste de plantes toxiques » (verified)

```
curl -G https://fr.wikipedia.org/w/api.php --data-urlencode action=parse \
  --data-urlencode 'page=Liste de plantes toxiques' --data-urlencode prop=wikitext \
  --data-urlencode format=json --data-urlencode 'origin=*'
→ header: Nom scientifique || Nom vernaculaire || Famille || Substances toxiques
  || Organes toxiques || Principaux symptômes || Espèces sensibles
  || Nombre d'appels aux centres anti-poison
→ 185 rows with ≥ 5 cells; response has access-control-allow-origin: *
```

Rows for the test taxa (refs stripped):

```
Aconitum napellus  | aconitine, atisine, véatchine | plante entière, racines           | homme, mammifères
Arum maculatum     | aroïne, arodine, aronine, triglochinine, oxalate de Ca | plante entière, baies | homme (enfants), bovins
Convallaria majalis| convallatoxoside, convallamaroside ... | plante entière, baies    | volailles, chien
Digitalis purpurea | digitaline (glycoside cardiotonique) | plante entière             |
Sambucus nigra     | hétérosides cyanogènes, flavonoïdes | fruits immatures            | enfants
Taxus baccata      | taxine, taxicatoside              | plante entière (sauf l'arille)    | bovins, chevaux
Urtica dioica      | absent (correct: not toxic)
```

CC BY-SA 4.0: showing the text in-app with attribution and a link is fine;
redistributing an extracted table means the extract is CC BY-SA too
(irrelevant for a private app, but cite it). Parsing a wikitable is
fragile (merged cells, refs, wikilinks); parse at build time, not live.

de.wikipedia « Liste giftiger Pflanzen » (verified): headers
*Wissenschaftlicher Name | Trivialname | Einstufung (GIZ Bonn) | Giftige
Teile | Wichtigste Wirkstoffe | Folgen der Vergiftung | Bild*, ~66 rows,
often at genus level (e.g. `Taxus baccata | Eiben | giftig – sehr giftig |
Kern der Beere, Blattwerk, Rinde, Holz, Wurzel | Taxin`). Sambucus absent.
en.wikipedia « List of poisonous plants » (verified): ~150 rows, organ info
only inside a free-text "Description" (`Taxus baccata ... Nearly all parts
contain toxic taxanes (except the red, fleshy ... aril)`).

### 3. fr.wikipedia species articles (current fallback; verified)

`action=parse&prop=sections` on each article:

| Taxon | fr article | Toxicity section |
|---|---|---|
| Digitalis purpurea | Digitalis purpurea | none (only « Propriétés médicinales ») |
| Taxus baccata | If commun | « Toxicité » (§8) |
| Arum maculatum | Arum maculatum | none (« Composition ») |
| Sambucus nigra | Sambucus nigra | « Toxicité potentielle » (§6), « Risques d'intoxication » (§26) |
| Urtica dioica | Grande ortie | none (correct) |
| Aconitum napellus | Aconit napel | « Composition et toxicité » (§11) |
| Convallaria majalis | Muguet de mai | « Toxicité » (§13) |

4 of 6 toxic taxa have a dedicated section, with good per-organ prose, e.g.
If commun: « Toutes les parties de l'arbre, sauf l'arille rouge entourant la
graine, sont très toxiques car elles contiennent des alcaloïdes (taxine) »;
Sambucus nigra: « Ses fleurs et ses baies cuites sont comestibles, mais
toutes les autres parties de la plante contiennent de l'oxalate de calcium
et sont donc toxiques ». Section titles vary, so a heading regex
(`toxic|intoxication|risques`) is needed; content is unstructured.

### 4. Wikidata (verified, SPARQL)

QIDs (P225 + P846): Sambucus nigra Q22701 (GBIF 2888728), Convallaria
majalis Q101711 (7459480), Urtica dioica Q155909 (5361816), Digitalis
purpurea Q157555 (5414995), Aconitum napellus Q159218 (3033665), Taxus
baccata Q179729 (5284517), Arum maculatum Q836366 (5330580).

- All item-valued claims of the 7 items: the only toxicity signals are
  `subclass of: poisonous plant` (Digitalis only) and `award received:
  Poisonous Plant of the Year` (Giftpflanze des Jahres; Convallaria,
  Digitalis, Aconitum, Taxus). Nothing on Arum or Sambucus.
- Class `poisonous plant` (Q21028485): 30 instances/subclasses in total.
- Properties with "tox"/"poison" in their label: only DSSTox / LiverTox
  ids (chemicals). `P2597` is "Gram staining", `P129` is "physically
  interacts with" (used for proteins/drugs, not plant parts).
- `this taxon is source of` (P1672) gives part items (elderberry,
  elderflower, elder tree bark, nettle leaf/root...) but they carry
  uses (crude drug, edible flower, purgative), no toxicity.
- `P703 found in taxon` (LOTUS import): 121 compounds for Sambucus nigra,
  231 for Taxus, 140 for Digitalis, 34 for Urtica — no organ, no toxicity,
  so not a toxicity signal (nettle has 34 too).

Verdict: no per-organ toxicity model exists in Wikidata; CC0 but empty.

### 5. PFAF — Plants For A Future (verified)

`curl -L 'https://pfaf.org/user/Plant.aspx?LatinName=Sambucus+nigra'`, the
« Known Hazards » paragraph:

- Sambucus nigra: "The leaves and stems are poisonous[9, 76]. The fruit of
  many species ... has been known to cause stomach upsets ... destroyed when
  the fruit is cooked[65, 76]."
- Taxus baccata: "All parts of the plant, except the flesh of the fruit,
  are highly poisonous, having a paralyzing affect on the heart ..."
- Urtica dioica: "The leaves of the plants have stinging hairs ... cooked
  leaves are perfectly safe ... older leaves develop gritty particles called
  cystoliths ..."
- Digitalis purpurea: "All parts of the plant are highly poisonous ..."
- Arum maculatum: "The plant contains calcium oxylate crystals ..."
- Aconitum napellus: "The whole plant is highly toxic, acting especially on
  the nerve centres ..."
- Convallaria majalis: "All parts of the plant are poisonous[7, 10, 19].
  However, the toxic principle is very poorly absorbed ..."

Best per-organ, per-preparation prose of all sources (7/7, Urtica included
with the right nuance). But: no API, no `Access-Control-Allow-Origin`
header, and the copyright page (`cmspage.aspx?pageid=136`) says "The
information on this site is copyrighted by Ken Fern/Plants for a Future
(1995-2026)"; only images are CC BY-NC-ND 3.0. PFAF sells its database.
Usable as an outbound link (« Voir les risques sur PFAF »); bundling or
scraping its text would need their permission.

### 6. Toxiplante.fr (verified)

148 monographs by pharmacists (C. & S. Hammer), French, per-organ and
compound detail. E.g. `monographies/arum_tachete.html`: « La plante est
hautement toxique, surtout fraîche » + oxalate/raphide chemistry;
`sureau_noir.html`: « Les fruits avant maturité sont faiblement toxiques
... Les baies sont comestibles à maturité complète ». Pages exist for if,
muguet, aconit, digitale, sureau noir/hièble/rouge, arum. Mentions légales:
« La reproduction ou représentation, intégrale ou partielle, des pages, des
données ... » is forbidden. HTML only. → link-out only.

### 7. Swiss / German vet and poison-centre sources

- CliniTox / giftpflanzen.ch (Univ. Zürich, Vetpharm) — verified:
  `vetpharm.uzh.ch/GIFTDB/PFLANZEN/0039_bot.htm` (Taxus): « Giftpflanze:
  sehr stark giftig +++ »; the `_tox` page lists toxic parts and per-animal
  effects. ~220 plants (440 bot/tox links on the index), German, copyright
  of the university. Link-out only.
- BfR « Risiko Pflanze – Einschätzung und Hinweise » (verified, PDF text
  extracted): ~50 plants, +/++/+++ scale, e.g. « +++ Eibe ... Giftige
  Teile: Nadeln und zerbissener Samen, der rote süßlich schmeckende
  Samenmantel ist ungiftig »; « ++ Aronstab », « ++ Maiglöckchen »,
  « ++ Fingerhut », « +++ Eisenhut »; no Holunder, no Brennnessel. A
  brochure, no open licence.
- GIZ Bonn (Giftzentrale Bonn, ~200 plants): only seen through search
  results, **not verified** directly.

### 8. French official sources

- Arrêté du 4 septembre 2020 (information before sale of plants harmful to
  health), JORFTEXT000042325453. curl gets 403; WebFetch summary: 4 lists,
  59 taxa (ingestion 20, respiratory allergy 23, skin/mucosa 10,
  phytophotodermatosis 6), columns = scientific name + vernacular name only,
  **no toxic-part column**. Taxus baccata, Digitalis purpurea and genus
  Aconitum are in the ingestion list; Sambucus, Arum, Convallaria, Urtica
  are not. Official text, free reuse, but too small and organ-less.
- ANSES « Fiches d'information — Plantes toxiques » (2021, ingestion and
  contact), avis 2021-SA-0032, report 2022-SA-0042 (CAP-TV calls 2021-24, 28
  plants ranked by severity), VigilAnses n°26 (2025): all PDFs behind a
  CrowdSec bot challenge; **not verified** (content known only from search
  snippets). Not a dataset; useful as a human reference.
- CNITV (VetAgro Sup, Lyon): verified site; its Vtox database (300 000
  cases) is internal, consulted by phone (paid). No public plant database.

### 9. Other candidates

- **INCHEM PIMs** (WHO/IPCS, verified): ~34 plant monographs, structured
  sections incl. « 3.2 Parties toxiques de la plante » (e.g. PIM 045F Arum
  maculatum, PIM 007 Aconitum napellus). Old (1990s), few European wild
  species, WHO copyright. Link-out at most.
- **GRIN Taxonomy** (USDA, verified, `taxonomydetail?id=80070`): "Economic
  Uses: Vertebrate poisons — mammals" with references (Kingsbury 1964,
  Cooper & Johnson 1998 "Poisonous plants and fungi in Britain", AMA
  handbook). A binary flag, no organ. US public domain. HTML only.
- **ASPCA** (verified, `/toxic-and-non-toxic-plants/yew`): "Scientific
  Name: Taxus spp. — Toxicity: Toxic to Dogs, Toxic to Cats, Toxic to
  Horses — Toxic Principles: Taxine — Clinical Signs: ...". Pets only,
  genus level, no organ, US, © ASPCA. Elderberry slug 404.
- **Cornell Poisonous Plants** (verified alphalist): ~110 entries,
  livestock; has Convallaria majalis, Digitalis purpurea, Taxus cuspidata;
  no Taxus baccata, Sambucus, Arum, Aconitum napellus. © Cornell.
- **KNApSAcK** (verified): 172 metabolites for Taxus baccata; no organ or
  toxicity, no open licence. PhytoHub (dietary phytochemicals) and LOTUS
  (already in Wikidata as P703) same story: compounds, not toxicity.
- **Pl@ntUse** (verified via MediaWiki API, CORS `*`): no toxicity section
  in Sambucus nigra / Taxus baccata / Arum maculatum pages; toxicity
  appears inside description prose (Taxus: « L'if est un arbre puissamment
  toxique dans toutes ses parties. L'arille seul est comestible »), partly
  quoting PFAF. Licence not exposed by `siprop=rightsinfo` (not verified).
- **Tela Botanica** (verified): Baseflor (`baseflor/informations/bdtfx.nn:67146`)
  has ecology / biology fields only, no toxicity. eFlore fiche tabs are
  JS-loaded, grep found nothing (not conclusive).
- **POWO / Kew** (WCUPS "Poisons" use category): Cloudflare blocked curl,
  **not verified**. Kew MPNS is medicinal names, not toxicity.
- **CABI Compendium**: not checked (time); datasheets are invasive-species
  oriented and rarely give per-organ human toxicity.
- **FDA Poisonous Plant Database (PLANTOX)**: `accessdata.fda.gov/scripts/plantox/`
  returns 404; decommissioned January 2022 (no updates since 2008).
- **Canadian Poisonous Plants Information System**: CBIF decommissioned in
  2021 (AAFC page says "no longer available"). The linkdata.org mirror
  (`rdf1s11i`) holds only a 260-row name list; the CC0 tag on that page is
  on an unrelated histone "Association_matrix" table, so the licence of
  the plant list is unclear.

## Test taxa at a glance

| Taxon | TPPT part / human | fr list « Organes toxiques » | fr article section | PFAF Known Hazards | Wikidata |
|---|---|---|---|---|---|
| Digitalis purpurea | Whole plant / very strong | plante entière | none | all parts highly poisonous | poisonous plant + award |
| Taxus baccata | Whole plant without aril / strong | plante entière (sauf l'arille) | Toxicité | all except fruit flesh | award |
| Arum maculatum | Leaf (or whole plant) / very strong | plante entière, baies | none | calcium oxalate, neutralised by drying/cooking | — |
| Sambucus nigra | Whole plant / weak | fruits immatures | Toxicité potentielle | leaves and stems; fruit OK cooked | — |
| Urtica dioica | Leaf / allergenic, skin-irritating | absent | none | stinging hairs, cooked safe | — |
| Aconitum napellus | Whole plant, most in root, seed / very strong | plante entière, racines | Composition et toxicité | whole plant highly toxic | award |
| Convallaria majalis | Whole plant, most in flower, fruit / very strong | plante entière, baies | Toxicité | all parts, poorly absorbed | award |

## Recommendation

**There is no open, maintained, fine-grained per-organ database.** The best
honest answer is a layered one, all offline except the existing Wikipedia
call:

1. **Structured layer — bundle TPPT** (open, `terms_by`). A build-time
   script (OCaml or a one-off) reads `tppt-db.db`, matches
   `Latin_plant_name` to a GBIF key with `api.gbif.org/v1/species/match`
   (review the ~60 aggr./spp./infraspecific names by hand), maps the 84
   `Toxic_plant_part` strings and the severity values to French, and emits
   a small JSON/SQL seed keyed by GBIF key: `{gbif_key, parts_fr,
   human_level, animal_level, compounds[]}`. ~850 rows, a few tens of KB.
   It can live as a static asset in the app or a Supabase lookup table
   (it is reference data, not personal data, so a repo file is fine).
   Display: « Toxicité : très forte — plante entière, surtout racines et
   graines (source : Agroscope TPPT) ». Animals as a secondary line.
   Genus fallback (TPPT has genus-level rows and the Wikipedia lists too)
   only with an explicit « (genre) » marker.
2. **French organ text — the fr.wikipedia list**, parsed at build time into
   the same table (`organes_fr`, `substances_fr`, `especes_sensibles`).
   It fixes TPPT's worst case (Sambucus: « fruits immatures ») and covers
   French species TPPT lacks (check Oenanthe crocata etc. when parsing).
   CC BY-SA: show attribution « Wikipédia, Liste de plantes toxiques ».
   It can also be fetched live (CORS-open), but parsing a wikitable on the
   device is not worth it.
3. **Keep the current heuristic** (Wikipedia article sentence) as the last
   fallback, but prefer the article's toxicity *section* (heading match
   « toxicit », « intoxication ») over the summary sentence; it is live,
   CORS-open and already wired.
4. **Links, not data**: PFAF « Known Hazards » (best per-preparation
   nuance, English) and Toxiplante (French, 148 plants) as outbound links
   in the refs block. Copyrighted: do not scrape into the app.
5. **Absence ≠ safe**: when no source has the taxon, show nothing (or
   « pas de donnée »), never « non toxique », except where TPPT says
   `nontoxic` (38 rows).

Caveats: TPPT is a 2018 snapshot and Swiss-scoped (Mediterranean and
Atlantic gaps); severity words are the authors' synthesis, not clinical
guidance; per-organ granularity is coarse ("Whole plant" for a third of
rows) and nothing models "edible when cooked". A disclaimer line
(« en cas d'ingestion : centre antipoison ») is advisable.

Not verified (could not reach): ANSES PDFs (CrowdSec), Légifrance annex
text by curl (WebFetch summary only), GIZ Bonn pages, POWO uses (Cloudflare),
CABI, Pl@ntUse licence.
