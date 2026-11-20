#!/usr/bin/env bash
# Record the geocoding payloads of test/fixtures/ (photon_*, geoplateforme_*)
# from the live APIs. Each fetch line is exactly the file, the
# Geocode.provider_to_string and the Geocode.request url of the request it
# records (test/geo checks it).
#
#   scripts/record-geo-fixtures.sh [--force]
#
# An existing file is kept unless --force: fixtures are recorded once, never
# edited. Both APIs answer bursts with empty bodies, so fetches are spaced.
# Needs curl >= 7.76 (--fail-with-body).
set -euo pipefail
root="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
out="$root/test/fixtures"
# Same identification as record-refs-fixtures.sh.
UA="Herbier/fixtures (https://github.com/tbrugere/herbier)"
# An interrupted curl leaves its .tmp.
trap 'rm -f "$out"/photon_*.tmp "$out"/geoplateforme_*.tmp' EXIT
force=0
case "$#:${1:-}" in
  0:) ;;
  1:--force) force=1 ;;
  *) echo "usage: $0 [--force]" >&2; exit 2 ;;
esac

fetch() {
  local file="$1" provider="$2" url="$3"
  local path="$out/$file"
  if [ -e "$path" ] && [ "$force" = 0 ]; then
    echo "skip $file"
    return 0
  fi
  case "$provider" in
    photon | geoplateforme) ;;
    *) echo "unknown provider $provider" >&2; return 1 ;;
  esac
  sleep 1.2
  curl -sS --fail-with-body --compressed -A "$UA" -o "$path.tmp" "$url" \
    || { rm -f "$path.tmp"; return 1; }
  if [ ! -s "$path.tmp" ]; then
    rm -f "$path.tmp"
    echo "empty body for $file (rate limited?)" >&2
    return 1
  fi
  mv "$path.tmp" "$path"
  echo "recorded $file"
}

# Col de la Schlucht (Vosges): a lieu-dit within 500 m.
fetch photon_reverse_schlucht.json photon "https://photon.komoot.io/reverse?lat=48.06330&lon=7.00810&lang=fr&limit=1&layer=city&layer=district&layer=locality"
fetch geoplateforme_lieu_dit_schlucht.json geoplateforme "https://data.geopf.fr/geocodage/reverse?index=poi&lon=7.00810&lat=48.06330&limit=1&category=lieu-dit%20habit%C3%A9%2Clieu-dit%20non%20habit%C3%A9&searchgeom=%7B%22type%22%3A%22Circle%22%2C%22coordinates%22%3A%5B7.00810%2C48.06330%5D%2C%22radius%22%3A500%7D"

# Landes forest: no lieu-dit within 500 m, a commune.
fetch geoplateforme_lieu_dit_landes.json geoplateforme "https://data.geopf.fr/geocodage/reverse?index=poi&lon=-0.85000&lat=44.25000&limit=1&category=lieu-dit%20habit%C3%A9%2Clieu-dit%20non%20habit%C3%A9&searchgeom=%7B%22type%22%3A%22Circle%22%2C%22coordinates%22%3A%5B-0.85000%2C44.25000%5D%2C%22radius%22%3A500%7D"
fetch geoplateforme_commune_landes.json geoplateforme "https://data.geopf.fr/geocodage/reverse?index=poi&lon=-0.85000&lat=44.25000&limit=1&category=commune&searchgeom=%7B%22type%22%3A%22Point%22%2C%22coordinates%22%3A%5B-0.85000%2C44.25000%5D%7D"

# Lausanne: inside the France box, outside France.
fetch photon_reverse_lausanne.json photon "https://photon.komoot.io/reverse?lat=46.51970&lon=6.63230&lang=fr&limit=1&layer=city&layer=district&layer=locality"
fetch geoplateforme_lieu_dit_lausanne.json geoplateforme "https://data.geopf.fr/geocodage/reverse?index=poi&lon=6.63230&lat=46.51970&limit=1&category=lieu-dit%20habit%C3%A9%2Clieu-dit%20non%20habit%C3%A9&searchgeom=%7B%22type%22%3A%22Circle%22%2C%22coordinates%22%3A%5B6.63230%2C46.51970%5D%2C%22radius%22%3A500%7D"
fetch geoplateforme_commune_lausanne.json geoplateforme "https://data.geopf.fr/geocodage/reverse?index=poi&lon=6.63230&lat=46.51970&limit=1&category=commune&searchgeom=%7B%22type%22%3A%22Point%22%2C%22coordinates%22%3A%5B6.63230%2C46.51970%5D%7D"

# Kew: outside the box.
fetch photon_reverse_kew.json photon "https://photon.komoot.io/reverse?lat=51.47870&lon=-0.29560&lang=fr&limit=1&layer=city&layer=district&layer=locality"

# The Atlantic, inside the box: nothing anywhere.
fetch photon_reverse_atlantic.json photon "https://photon.komoot.io/reverse?lat=46.20000&lon=-5.00000&lang=fr&limit=1&layer=city&layer=district&layer=locality"
fetch geoplateforme_lieu_dit_atlantic.json geoplateforme "https://data.geopf.fr/geocodage/reverse?index=poi&lon=-5.00000&lat=46.20000&limit=1&category=lieu-dit%20habit%C3%A9%2Clieu-dit%20non%20habit%C3%A9&searchgeom=%7B%22type%22%3A%22Circle%22%2C%22coordinates%22%3A%5B-5.00000%2C46.20000%5D%2C%22radius%22%3A500%7D"
fetch geoplateforme_commune_atlantic.json geoplateforme "https://data.geopf.fr/geocodage/reverse?index=poi&lon=-5.00000&lat=46.20000&limit=1&category=commune&searchgeom=%7B%22type%22%3A%22Point%22%2C%22coordinates%22%3A%5B-5.00000%2C46.20000%5D%7D"

# Forward search.
fetch photon_search_col_de_la_schlucht.json photon "https://photon.komoot.io/api?q=col%20de%20la%20schlucht&lang=fr&limit=8"
fetch photon_search_schlucht_near.json photon "https://photon.komoot.io/api?q=schlucht&lang=fr&limit=3&lat=48.06330&lon=7.00810"
fetch photon_search_zzzzqqq.json photon "https://photon.komoot.io/api?q=zzzzqqq&lang=fr&limit=8"

# IGN hors-ligne: the département list and the communes of Territoire de Belfort (WFS).
fetch geoplateforme_wfs_departements.json geoplateforme "https://data.geopf.fr/wfs/ows?SERVICE=WFS&VERSION=2.0.0&REQUEST=GetFeature&OUTPUTFORMAT=application%2Fjson&TYPENAMES=ADMINEXPRESS-COG-CARTO.LATEST%3Adepartement&PROPERTYNAME=code_insee%2Cnom_officiel&SORTBY=code_insee&COUNT=5000"
fetch geoplateforme_wfs_communes_90.json geoplateforme "https://data.geopf.fr/wfs/ows?SERVICE=WFS&VERSION=2.0.0&REQUEST=GetFeature&OUTPUTFORMAT=application%2Fjson&TYPENAMES=ADMINEXPRESS-COG-CARTO.LATEST%3Acommune&PROPERTYNAME=code_insee%2Cnom_officiel%2Cgeometrie&SORTBY=code_insee&COUNT=5000&CQL_FILTER=code_insee_du_departement%3D%2790%27"
# An unknown code: an empty collection.
fetch geoplateforme_wfs_communes_99.json geoplateforme "https://data.geopf.fr/wfs/ows?SERVICE=WFS&VERSION=2.0.0&REQUEST=GetFeature&OUTPUTFORMAT=application%2Fjson&TYPENAMES=ADMINEXPRESS-COG-CARTO.LATEST%3Acommune&PROPERTYNAME=code_insee%2Cnom_officiel%2Cgeometrie&SORTBY=code_insee&COUNT=5000&CQL_FILTER=code_insee_du_departement%3D%2799%27"
# Mayotte: an overseas département, served by the same request.
fetch geoplateforme_wfs_communes_976.json geoplateforme "https://data.geopf.fr/wfs/ows?SERVICE=WFS&VERSION=2.0.0&REQUEST=GetFeature&OUTPUTFORMAT=application%2Fjson&TYPENAMES=ADMINEXPRESS-COG-CARTO.LATEST%3Acommune&PROPERTYNAME=code_insee%2Cnom_officiel%2Cgeometrie&SORTBY=code_insee&COUNT=5000&CQL_FILTER=code_insee_du_departement%3D%27976%27"
