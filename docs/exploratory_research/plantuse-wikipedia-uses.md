# Herbier — Uses of a species: Pl@ntUse and Wikipedia

Date of research: **2026-11-21** (M4.81, the « Utilisations » row of 4f).
Every request below was made live with `curl` on that date; the answers the
tests read are recorded under `test/fixtures/` (`plantuse_page_*`,
`wikipedia_extract_*`) by `scripts/record-refs-fixtures.sh`. Species: the
spike pair *Digitalis purpurea* and *Arnica montana*, plus *Urtica dioica*,
*Quercus robur*, *Fallopia japonica* and *Polygonum cuspidatum* for the
edge cases.

## Pl@ntUse

**Where.** Pl@ntUse, Pl@ntNet's wiki of plant uses, moved from
`uses.plantnet-project.org` (now a 301 to the new host) to
`plantuse.plantnet.org`. It is a MediaWiki 1.43 with one wiki per language:
`/fr/` is the populated one; `/en/` exists but its species pages are robot
stubs whose « Uses summary » box is empty (Arnica montana, Manihot esculenta,
Urtica dioica checked). `https://plantuse.plantnet.org/w/api.php` is a 307 to
nowhere useful.

**How (the sanctioned interface, no scraping).** The MediaWiki action API at
`https://plantuse.plantnet.org/fr/api.php`. No key, no custom header; with
`origin=*` the answer carries `access-control-allow-origin: *` (seen with
`Origin: https://localhost`, the WebView's origin), so the WebView calls it
directly. There is no `robots.txt` (the path redirects to the main page) and
no terms of use beyond the licence; the API is the machine interface
MediaWiki offers, used at one request per plant fetch.

One request returns the wikitext of a page, follows redirects and normalises
underscores; several titles can be asked at once:

```
https://plantuse.plantnet.org/fr/api.php?action=query&prop=revisions
  &rvprop=content&rvslots=main&redirects=1
  &titles=Digitalis%20purpurea%20subsp.%20purpurea%7CDigitalis%20purpurea
  &format=json&formatversion=2&origin=%2A
```

- An unknown page is `{"title": …, "missing": true}` with HTTP 200, never a
  404 (Fallopia japonica, GBIF's accepted name, has no page).
- `Polygonum cuspidatum` redirects to `Reynoutria japonica` (in
  `query.redirects`).
- `query.pages` is not in request order: the page is picked by title, after
  `normalized` and `redirects`.

**What a species page holds** (template `Page espèce (plante à graines)`):

- The box `{{Encadré |color=lightgreen |titre=Résumé des usages
  |texte=*…\n*…}}`: Pl@ntUse's own short list of uses, one bullet each.
  Digitalis purpurea: « médicinal »; Urtica dioica: « jeunes feuilles
  consommées comme légume ou en soupe », « feuilles utilisées pour emballer des
  aliments », « fibres des tiges textiles », « médicinale »; Quercus robur: 12
  bullets (« bois de feu », « additif alimentaire »…). Arnica montana: no box
  (a robot-created page). These bullets are the "use categories" the 4f row
  shows as chips, as written: the site has no structured category field.
- The `== Usages ==` section: mostly « *Voir les [[… (Cazin 1868)|…]] »
  cross-references to digitised old books, sometimes a French paragraph inside
  a wikitable cell (Urtica dioica), or an English PFAF quote inside
  `{{Citation encadré|texte=…}}` (Quercus robur). The row shows the first two
  sentences of the first French prose paragraph, never the English quotes nor
  the cross-references.
- MediaWiki categories (`prop=categories`) carry uses on some pages only
  (Quercus robur: « Bois de feu », « Tanin », « Médecine humaine, tempéré
  secondaire »…; Digitalis and Urtica: none): not used.

**Licence and credit.** `meta=siteinfo&siprop=rightsinfo` is empty; the page
`PlantUse:À propos` says the site is under « la licence Creative Commons »
without naming the variant or version. The step text names CC BY-SA, the
licence of Pl@ntNet's other open content; the credit shown on 4f is
« Pl@ntUse · CC BY-SA », linking to the quoted page. Gap recorded: the site
itself does not state the version.

## Wikipedia: the « Utilisation(s) » / « Usages » section

**Which interface.** The REST `page/summary` the toxicity row reads has the
lead only, and `page/mobile-sections` is gone. The action API's TextExtracts
gives the whole article as plain text, with `== Title ==` heading lines
(`exsectionformat=wiki`), templates rendered (`{{unité|…}}` → « 0,000 5
mg/kg »), references dropped and one paragraph per line, plus the page
language and URL:

```
https://<lang>.wikipedia.org/w/api.php?action=query&prop=extracts%7Cinfo
  &inprop=url&explaintext=1&exsectionformat=wiki&redirects=1&titles=<T>
  &format=json&formatversion=2&origin=%2A
```

CORS `*` with `origin=*`; the `Api-User-Agent` header goes with it as with
every Wikimedia call. Rejected: `action=parse&prop=wikitext&section=N` (needs
the section index first, and templates such as `{{unité}}`, `{{,}}`,
`{{3e|…}}` would need rendering); parsed HTML (tag stripping, references as
`<sup>`).

**Size.** Arnica des montagnes (fr) is about 63 KB of text, Digitalis
purpurea (en) about 12 KB: the stored payload keeps only the heading lines and
the bodies of the sections whose title matches (`Payload.prune`).

**Section titles seen** (the heuristic matches whole words of the folded
title: fr usage(s), utilisation(s), emploi(s); en use(s), usage):

| article | titles | matched |
|---|---|---|
| fr Digitalis purpurea | « Propriétés médicinales » | none |
| en Digitalis purpurea | « Medicinal use » (level 3, under « Toxicity ») | yes |
| fr Arnica des montagnes | « Usages et propriétés » (own body empty, first sub « Constituants »), « Usages en médecine humaine » (own body empty), « Usages en médecine vétérinaire » (prose), « Autres usages » | « Phytothérapie », under « Usages en médecine humaine » (see below) |
| en Arnica montana | « Use in herbal medicine » | yes |
| fr Grande ortie | « Usages médicinaux » | yes |
| en Urtica dioica | « Relationship to humans » | none |

The paragraph is the first line of at least 40 characters in the matched
section's own body (captions and one-word lines skipped); when it has none, in
its subsections, uses ones first, then the others, a history (« Historique »)
last: Arnica's « Usages et propriétés » leads to « Usages en médecine
humaine », then to its « Phytothérapie » (« En médecine traditionnelle,
l'usage de l'arnica … »). It is a heuristic:
4f marks it « extrait automatique », names the section and the language when
it is not French, and links to the article; licence CC BY-SA.

**Sitelinks** (Wikidata, fixtures `wikidata_entity_*`): Q157555 Digitalis
purpurea: frwiki and enwiki « Digitalis purpurea »; Q207848 Arnica montana:
frwiki « Arnica des montagnes », enwiki « Arnica montana ». The fr article is
asked first; the en one only when the fr one has no matched section.

## Result on the spike species

- Digitalis purpurea: Pl@ntUse chip « médicinal » (its « Usages » section is
  only cross-references); Wikipedia en « Medicinal use » (« Extracted from the
  leaves, this same cardiac glycoside digitoxin is used as a medication for
  heart failure. … »).
- Arnica montana: Pl@ntUse page without box nor prose, so no Pl@ntUse part;
  Wikipedia fr « Phytothérapie » (under « Usages en médecine humaine »).
- Fallopia japonica: no Pl@ntUse page. A species with neither source shows no
  « Utilisations » row.
