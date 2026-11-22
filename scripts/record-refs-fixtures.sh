#!/usr/bin/env bash
# Record the reference-source payloads of test/fixtures/ (gbif_*, wikidata_*,
# wikipedia_*, tela_*, inpn_*, plantuse_*) from the live APIs. Each fetch line is exactly
# the file, the Request.source and the Request.url of the request description
# it records (test/refs checks it), except the lines preceded by a
# "# not built by a request function:" comment. A fetch_absent line records
# the body of a 404 (the file name ends in _404.txt): the source answering
# that it has no such page.
#
#   scripts/record-refs-fixtures.sh [--force]
#
# An existing file is kept unless --force: fixtures are recorded once, never
# edited. Needs curl >= 7.76 (--fail-with-body).
set -euo pipefail
root="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
out="$root/test/fixtures"
force=0
case "$#:${1:-}" in
  0:) ;;
  1:--force) force=1 ;;
  *) echo "usage: $0 [--force]" >&2; exit 2 ;;
esac
UA="Herbier/fixtures (https://github.com/tbrugere/herbier)"

fetch() {
  local file="$1" source="$2" url="$3"
  local path="$out/$file"
  if [ -e "$path" ] && [ "$force" = 0 ]; then
    echo "skip $file"
    return 0
  fi
  local args=(-sS --fail-with-body --compressed -A "$UA")
  case "$source" in
    wikidata) args+=(-H "Api-User-Agent: $UA") ;;
    wikipedia) args+=(-L -H "Api-User-Agent: $UA") ;;
    gbif | tela | taxref | plantuse) ;;
    *) echo "unknown source $source" >&2; return 1 ;;
  esac
  curl "${args[@]}" -o "$path.tmp" "$url" || { rm -f "$path.tmp"; return 1; }
  mv "$path.tmp" "$path"
  echo "recorded $file"
}

fetch_absent() {
  local file="$1" source="$2" url="$3"
  local path="$out/$file"
  if [ -e "$path" ] && [ "$force" = 0 ]; then
    echo "skip $file"
    return 0
  fi
  case "$source" in
    tela | taxref) ;;
    *) echo "unknown source $source" >&2; return 1 ;;
  esac
  local code
  code="$(curl -sS --compressed -A "$UA" -o "$path.tmp" -w '%{http_code}' "$url")" \
    || { rm -f "$path.tmp"; return 1; }
  if [ "$code" != 404 ]; then
    echo "$file: expected 404, got $code" >&2
    rm -f "$path.tmp"
    return 1
  fi
  mv "$path.tmp" "$path"
  echo "recorded $file (404)"
}

fetch gbif_species_5414995.json gbif "https://api.gbif.org/v1/species/5414995"
fetch gbif_species_5405976.json gbif "https://api.gbif.org/v1/species/5405976"
fetch gbif_species_5334357.json gbif "https://api.gbif.org/v1/species/5334357"
fetch gbif_species_7971454.json gbif "https://api.gbif.org/v1/species/7971454"
fetch gbif_species_5708907.json gbif "https://api.gbif.org/v1/species/5708907"
fetch gbif_species_3152559.json gbif "https://api.gbif.org/v1/species/3152559"

fetch gbif_match_digitalis_purpurea_l.json gbif "https://api.gbif.org/v1/species/match?name=Digitalis%20purpurea%20L.&kingdom=Plantae"
fetch gbif_match_digitalis_purpurae.json gbif "https://api.gbif.org/v1/species/match?name=Digitalis%20purpurae&kingdom=Plantae"
fetch gbif_match_fallopia_japonica.json gbif "https://api.gbif.org/v1/species/match?name=Fallopia%20japonica&kingdom=Plantae"
fetch gbif_match_xyzzy_foo.json gbif "https://api.gbif.org/v1/species/match?name=Xyzzy%20foo&kingdom=Plantae"
fetch gbif_match_hibiscus_rosa_sinensis_l.json gbif "https://api.gbif.org/v1/species/match?name=Hibiscus%20rosa-sinensis%20L.&kingdom=Plantae"
fetch gbif_match_hibiscus_spp.json gbif "https://api.gbif.org/v1/species/match?name=Hibiscus%20spp.&kingdom=Plantae"
# not built by a request function: no kingdom, the only way to get matchType
# NONE live.
fetch gbif_match_none_zzzzqqq.json gbif "https://api.gbif.org/v1/species/match?name=zzzzqqq"

fetch gbif_suggest_digitalis_purp.json gbif "https://api.gbif.org/v1/species/suggest?q=Digitalis%20purp&datasetKey=d7dddbf4-2cf0-4f39-9b2a-bb099caae36c&rank=SPECIES&highertaxonKey=6&limit=10"
fetch gbif_vernacular_search_digitale_pourpre.json gbif "https://api.gbif.org/v1/species/search?q=digitale%20pourpre&datasetKey=d7dddbf4-2cf0-4f39-9b2a-bb099caae36c&highertaxonKey=6&qField=VERNACULAR&limit=20"

fetch gbif_vernacular_names_5414995.json gbif "https://api.gbif.org/v1/species/5414995/vernacularNames?limit=1000"
fetch gbif_vernacular_names_5405976.json gbif "https://api.gbif.org/v1/species/5405976/vernacularNames?limit=1000"
fetch gbif_distributions_5414995.json gbif "https://api.gbif.org/v1/species/5414995/distributions?limit=1000"
fetch gbif_distributions_5405976.json gbif "https://api.gbif.org/v1/species/5405976/distributions?limit=1000"
fetch gbif_occurrence_count_5414995.json gbif "https://api.gbif.org/v1/occurrence/count?taxonKey=5414995"
fetch gbif_occurrence_count_5405976.json gbif "https://api.gbif.org/v1/occurrence/count?taxonKey=5405976"
fetch gbif_plantnet_media_5414995.json gbif "https://api.gbif.org/v1/occurrence/search?datasetKey=7a3679ef-5582-4aaa-81f0-8c2545cafc81&taxonKey=5414995&mediaType=StillImage&limit=50"
fetch gbif_plantnet_media_5405976.json gbif "https://api.gbif.org/v1/occurrence/search?datasetKey=7a3679ef-5582-4aaa-81f0-8c2545cafc81&taxonKey=5405976&mediaType=StillImage&limit=50"
fetch gbif_species_2889173.json gbif "https://api.gbif.org/v1/species/2889173"
fetch gbif_suggest_digitale_pourpre.json gbif "https://api.gbif.org/v1/species/suggest?q=digitale%20pourpre&datasetKey=d7dddbf4-2cf0-4f39-9b2a-bb099caae36c&rank=SPECIES&highertaxonKey=6&limit=10"
fetch gbif_vernacular_search_digitalis_purp.json gbif "https://api.gbif.org/v1/species/search?q=Digitalis%20purp&datasetKey=d7dddbf4-2cf0-4f39-9b2a-bb099caae36c&highertaxonKey=6&qField=VERNACULAR&limit=20"
fetch gbif_plantnet_media_1.json gbif "https://api.gbif.org/v1/occurrence/search?datasetKey=7a3679ef-5582-4aaa-81f0-8c2545cafc81&taxonKey=1&mediaType=StillImage&limit=50"

fetch wikidata_search_p846_5414995.json wikidata "https://www.wikidata.org/w/api.php?action=query&list=search&srsearch=haswbstatement%3A%22P846%3D5414995%22&format=json&origin=%2A"
fetch wikidata_search_p846_5405976.json wikidata "https://www.wikidata.org/w/api.php?action=query&list=search&srsearch=haswbstatement%3A%22P846%3D5405976%22&format=json&origin=%2A"
fetch wikidata_search_p5037_802077-1.json wikidata "https://www.wikidata.org/w/api.php?action=query&list=search&srsearch=haswbstatement%3A%22P5037%3Durn%3Alsid%3Aipni.org%3Anames%3A802077-1%22&format=json&origin=%2A"
fetch wikidata_search_p846_999999999.json wikidata "https://www.wikidata.org/w/api.php?action=query&list=search&srsearch=haswbstatement%3A%22P846%3D999999999%22&format=json&origin=%2A"
fetch wikidata_search_p3151_53983.json wikidata "https://www.wikidata.org/w/api.php?action=query&list=search&srsearch=haswbstatement%3A%22P3151%3D53983%22&format=json&origin=%2A"
fetch wikidata_search_p3186_94959.json wikidata "https://www.wikidata.org/w/api.php?action=query&list=search&srsearch=haswbstatement%3A%22P3186%3D94959%22&format=json&origin=%2A"
fetch wikidata_search_p3105_22437.json wikidata "https://www.wikidata.org/w/api.php?action=query&list=search&srsearch=haswbstatement%3A%22P3105%3D22437%22&format=json&origin=%2A"

fetch wikidata_entity_Q157555.json wikidata "https://www.wikidata.org/w/api.php?action=wbgetentities&ids=Q157555&props=claims%7Csitelinks&sitefilter=frwiki%7Cenwiki%7Cdewiki%7Citwiki&format=json&origin=%2A"
fetch wikidata_entity_Q207848.json wikidata "https://www.wikidata.org/w/api.php?action=wbgetentities&ids=Q207848&props=claims%7Csitelinks&sitefilter=frwiki%7Cenwiki%7Cdewiki%7Citwiki&format=json&origin=%2A"
# not built by a request function: Q0 is not a Qid.t.
fetch wikidata_entity_Q0.json wikidata "https://www.wikidata.org/w/api.php?action=wbgetentities&ids=Q0&props=claims%7Csitelinks&sitefilter=frwiki%7Cenwiki%7Cdewiki%7Citwiki&format=json&origin=%2A"

fetch wikipedia_summary_fr_Digitalis_purpurea.json wikipedia "https://fr.wikipedia.org/api/rest_v1/page/summary/Digitalis_purpurea"
fetch wikipedia_summary_fr_Arnica_montana.json wikipedia "https://fr.wikipedia.org/api/rest_v1/page/summary/Arnica_montana"
fetch wikipedia_summary_en_Digitalis_purpurea.json wikipedia "https://en.wikipedia.org/api/rest_v1/page/summary/Digitalis_purpurea"
fetch wikipedia_summary_fr_Lis.json wikipedia "https://fr.wikipedia.org/api/rest_v1/page/summary/Lis"
fetch wikipedia_summary_fr_Arnica_des_montagnes.json wikipedia "https://fr.wikipedia.org/api/rest_v1/page/summary/Arnica_des_montagnes"

fetch tela_names_digitalis_purpurea.json tela "https://api.tela-botanica.org/service:eflore:0.1/bdtfx/noms?masque=Digitalis%20purpurea&retour.format=min"
fetch tela_names_arnica_montana.json tela "https://api.tela-botanica.org/service:eflore:0.1/bdtfx/noms?masque=Arnica%20montana&retour.format=min"
fetch tela_names_reynoutria_japonica.json tela "https://api.tela-botanica.org/service:eflore:0.1/bdtfx/noms?masque=Reynoutria%20japonica&retour.format=min"
fetch tela_names_digitalis_purpurea_subsp_purpurea.json tela "https://api.tela-botanica.org/service:eflore:0.1/bdtfx/noms?masque=Digitalis%20purpurea%20subsp.%20purpurea&retour.format=min"
fetch_absent tela_names_victoria_amazonica_404.txt tela "https://api.tela-botanica.org/service:eflore:0.1/bdtfx/noms?masque=Victoria%20amazonica&retour.format=min"
fetch tela_taxon_22437.json tela "https://api.tela-botanica.org/service:eflore:0.1/bdtfx/taxons/22437"
fetch tela_taxon_6646.json tela "https://api.tela-botanica.org/service:eflore:0.1/bdtfx/taxons/6646"
fetch tela_taxon_55763.json tela "https://api.tela-botanica.org/service:eflore:0.1/bdtfx/taxons/55763"
fetch tela_taxon_76533.json tela "https://api.tela-botanica.org/service:eflore:0.1/bdtfx/taxons/76533"
fetch tela_baseflor_22437.json tela "https://api.tela-botanica.org/service:eflore:0.1/baseflor/informations/bdtfx.nn%3A22437"
fetch tela_baseflor_6646.json tela "https://api.tela-botanica.org/service:eflore:0.1/baseflor/informations/bdtfx.nn%3A6646"
fetch tela_baseflor_26478.json tela "https://api.tela-botanica.org/service:eflore:0.1/baseflor/informations/bdtfx.nn%3A26478"
fetch_absent tela_baseflor_31960_404.txt tela "https://api.tela-botanica.org/service:eflore:0.1/baseflor/informations/bdtfx.nn%3A31960"

fetch inpn_name_94959.json taxref "https://odata-inpn.mnhn.fr/taxa/names/94959"
fetch inpn_name_83874.json taxref "https://odata-inpn.mnhn.fr/taxa/names/83874"
fetch inpn_name_97964.json taxref "https://odata-inpn.mnhn.fr/taxa/names/97964"
fetch_absent inpn_name_99999999_404.txt taxref "https://odata-inpn.mnhn.fr/taxa/names/99999999"
fetch inpn_status_94959.json taxref "https://odata-inpn.mnhn.fr/taxa/94959/biogeographicStatuses?locationId=TERFXFR"
fetch inpn_status_83874.json taxref "https://odata-inpn.mnhn.fr/taxa/83874/biogeographicStatuses?locationId=TERFXFR"
fetch inpn_status_117503.json taxref "https://odata-inpn.mnhn.fr/taxa/117503/biogeographicStatuses?locationId=TERFXFR"
fetch inpn_status_97964.json taxref "https://odata-inpn.mnhn.fr/taxa/97964/biogeographicStatuses?locationId=TERFXFR"
fetch inpn_red_list_94959.json taxref "https://odata-inpn.mnhn.fr/taxa/redLists/entries?taxrefId=94959&scopes=NATIONAL&scopeLocationId=TERFXFR"
fetch inpn_red_list_83874.json taxref "https://odata-inpn.mnhn.fr/taxa/redLists/entries?taxrefId=83874&scopes=NATIONAL&scopeLocationId=TERFXFR"
fetch inpn_red_list_117503.json taxref "https://odata-inpn.mnhn.fr/taxa/redLists/entries?taxrefId=117503&scopes=NATIONAL&scopeLocationId=TERFXFR"
fetch inpn_protections_94959.json taxref "https://odata-inpn.mnhn.fr/taxa/protections/articles?taxrefIds=94959&embed=SCOPE_LOCATION&size=100"
fetch inpn_protections_83874.json taxref "https://odata-inpn.mnhn.fr/taxa/protections/articles?taxrefIds=83874&embed=SCOPE_LOCATION&size=100"
fetch inpn_protections_117503.json taxref "https://odata-inpn.mnhn.fr/taxa/protections/articles?taxrefIds=117503&embed=SCOPE_LOCATION&size=100"
fetch inpn_protections_94041.json taxref "https://odata-inpn.mnhn.fr/taxa/protections/articles?taxrefIds=94041&embed=SCOPE_LOCATION&size=100"

# The « Utilisations » row: Pl@ntUse pages, Wikipedia extracts.
fetch plantuse_page_digitalis_purpurea.json plantuse "https://plantuse.plantnet.org/fr/api.php?action=query&prop=revisions&rvprop=content&rvslots=main&redirects=1&titles=Digitalis%20purpurea&format=json&formatversion=2&origin=%2A"
fetch plantuse_page_arnica_montana.json plantuse "https://plantuse.plantnet.org/fr/api.php?action=query&prop=revisions&rvprop=content&rvslots=main&redirects=1&titles=Arnica%20montana&format=json&formatversion=2&origin=%2A"
fetch plantuse_page_fallopia_japonica.json plantuse "https://plantuse.plantnet.org/fr/api.php?action=query&prop=revisions&rvprop=content&rvslots=main&redirects=1&titles=Fallopia%20japonica&format=json&formatversion=2&origin=%2A"
fetch plantuse_page_urtica_dioica.json plantuse "https://plantuse.plantnet.org/fr/api.php?action=query&prop=revisions&rvprop=content&rvslots=main&redirects=1&titles=Urtica%20dioica&format=json&formatversion=2&origin=%2A"
fetch plantuse_page_quercus_robur.json plantuse "https://plantuse.plantnet.org/fr/api.php?action=query&prop=revisions&rvprop=content&rvslots=main&redirects=1&titles=Quercus%20robur&format=json&formatversion=2&origin=%2A"
fetch plantuse_page_polygonum_cuspidatum.json plantuse "https://plantuse.plantnet.org/fr/api.php?action=query&prop=revisions&rvprop=content&rvslots=main&redirects=1&titles=Polygonum%20cuspidatum&format=json&formatversion=2&origin=%2A"
fetch plantuse_page_digitalis_purpurea_subsp_purpurea.json plantuse "https://plantuse.plantnet.org/fr/api.php?action=query&prop=revisions&rvprop=content&rvslots=main&redirects=1&titles=Digitalis%20purpurea%20subsp.%20purpurea%7CDigitalis%20purpurea&format=json&formatversion=2&origin=%2A"
fetch wikipedia_extract_fr_Digitalis_purpurea.json wikipedia "https://fr.wikipedia.org/w/api.php?action=query&prop=extracts%7Cinfo&inprop=url&explaintext=1&exsectionformat=wiki&redirects=1&titles=Digitalis%20purpurea&format=json&formatversion=2&origin=%2A"
fetch wikipedia_extract_en_Digitalis_purpurea.json wikipedia "https://en.wikipedia.org/w/api.php?action=query&prop=extracts%7Cinfo&inprop=url&explaintext=1&exsectionformat=wiki&redirects=1&titles=Digitalis%20purpurea&format=json&formatversion=2&origin=%2A"
fetch wikipedia_extract_fr_Arnica_des_montagnes.json wikipedia "https://fr.wikipedia.org/w/api.php?action=query&prop=extracts%7Cinfo&inprop=url&explaintext=1&exsectionformat=wiki&redirects=1&titles=Arnica%20des%20montagnes&format=json&formatversion=2&origin=%2A"
fetch wikipedia_extract_en_Arnica_montana.json wikipedia "https://en.wikipedia.org/w/api.php?action=query&prop=extracts%7Cinfo&inprop=url&explaintext=1&exsectionformat=wiki&redirects=1&titles=Arnica%20montana&format=json&formatversion=2&origin=%2A"
fetch wikipedia_extract_en_Urtica_dioica.json wikipedia "https://en.wikipedia.org/w/api.php?action=query&prop=extracts%7Cinfo&inprop=url&explaintext=1&exsectionformat=wiki&redirects=1&titles=Urtica%20dioica&format=json&formatversion=2&origin=%2A"
fetch wikipedia_extract_fr_Xyzzy_foo.json wikipedia "https://fr.wikipedia.org/w/api.php?action=query&prop=extracts%7Cinfo&inprop=url&explaintext=1&exsectionformat=wiki&redirects=1&titles=Xyzzy%20foo&format=json&formatversion=2&origin=%2A"
