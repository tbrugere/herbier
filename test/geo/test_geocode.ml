module Places = Herbier_domain.Places

(* ---------- fixture plumbing ---------- *)

let read_fixture name =
  In_channel.with_open_bin
    (Filename.concat "../fixtures" name)
    In_channel.input_all

let json_fixture name =
  match Geocode.json_of_string (read_fixture name) with
  | Ok j -> j
  | Error e -> failwith (name ^ ": " ^ Geocode.error_to_string e)

(* ---------- points ---------- *)

let schlucht : Places.point = {lat = 48.0633; lon = 7.0081}
let lausanne : Places.point = {lat = 46.5197; lon = 6.6323}
let kew : Places.point = {lat = 51.4787; lon = -0.2956}
let atlantic : Places.point = {lat = 46.2; lon = -5.0}
let landes : Places.point = {lat = 44.25; lon = -0.85}

(* ---------- testables ---------- *)

let error =
  Alcotest.testable
    (fun f e -> Format.pp_print_string f (Geocode.error_to_string e))
    Geocode.equal_error

let point_json (p : Places.point) =
  `Assoc [("lat", `Float p.lat); ("lon", `Float p.lon)]

let place_json (p : Geocode.place) =
  `Assoc
    [
      ("name", `String p.name);
      ("context", match p.context with None -> `Null | Some s -> `String s);
      ("point", point_json p.point);
    ]

let place =
  Alcotest.testable
    (fun f p -> Format.pp_print_string f (Yojson.Safe.to_string (place_json p)))
    Geocode.equal_place

let places = Alcotest.list place
let name_opt_result = Alcotest.result (Alcotest.option Alcotest.string) error

(* ---------- recorded requests: file, and the request that fetched it ---------- *)

let force_communes_request departement =
  match Communes.Code.of_string departement with
  | Some departement -> Communes.communes_request ~departement
  | None -> Alcotest.failf "%S is not a département code" departement

let recorded_requests =
  [
    ("photon_reverse_schlucht.json", Geocode.photon_reverse schlucht);
    ("photon_reverse_lausanne.json", Geocode.photon_reverse lausanne);
    ("photon_reverse_kew.json", Geocode.photon_reverse kew);
    ("photon_reverse_atlantic.json", Geocode.photon_reverse atlantic);
    ( "geoplateforme_lieu_dit_schlucht.json",
      Geocode.geoplateforme_lieu_dit schlucht );
    ("geoplateforme_lieu_dit_landes.json", Geocode.geoplateforme_lieu_dit landes);
    ("geoplateforme_commune_landes.json", Geocode.geoplateforme_commune landes);
    ( "geoplateforme_lieu_dit_lausanne.json",
      Geocode.geoplateforme_lieu_dit lausanne );
    ( "geoplateforme_commune_lausanne.json",
      Geocode.geoplateforme_commune lausanne );
    ( "geoplateforme_lieu_dit_atlantic.json",
      Geocode.geoplateforme_lieu_dit atlantic );
    ( "geoplateforme_commune_atlantic.json",
      Geocode.geoplateforme_commune atlantic );
    ( "photon_search_col_de_la_schlucht.json",
      Geocode.photon_search "col de la schlucht" );
    ( "photon_search_schlucht_near.json",
      Geocode.photon_search ~near:schlucht ~limit:3 "schlucht" );
    ("photon_search_zzzzqqq.json", Geocode.photon_search "zzzzqqq");
    ("geoplateforme_wfs_departements.json", Communes.departements_request);
    ("geoplateforme_wfs_communes_90.json", force_communes_request "90");
    (* geoplateforme_wfs_communes_99.json (the unknown-code fixture) is
       checked in test_communes.ml: "99" is not a département code, so
       [communes_request] cannot build its request. *)
  ]

(* ---------- request URLs ---------- *)

let url_tests =
  [
    ( "encode: space, comma, quote and an accented letter",
      `Quick,
      fun () ->
        Alcotest.(check string) "space" "%20" (Geocode.encode " ");
        Alcotest.(check string) "comma" "%2C" (Geocode.encode ",");
        Alcotest.(check string) "quote" "%22" (Geocode.encode "\"");
        Alcotest.(check string) "e accent aigu" "%C3%A9" (Geocode.encode "é") );
    ( "coordinate: five decimals, negative kept",
      `Quick,
      fun () ->
        Alcotest.(check string)
          "positive" "48.06330"
          (Geocode.coordinate 48.0633);
        Alcotest.(check string)
          "negative" "-5.00000"
          (Geocode.coordinate (-5.0));
        Alcotest.(check string)
          "negative, non-integer" "-0.85000"
          (Geocode.coordinate (-0.85));
        Alcotest.(check string)
          "digits past the fifth are dropped" "48.06335"
          (Geocode.coordinate 48.0633512);
        Alcotest.(check string)
          "negative, rounded" "-0.12346"
          (Geocode.coordinate (-0.123456789)) );
    ( "photon_reverse: exact URL at each fixture point",
      `Quick,
      fun () ->
        let check what point expected =
          Alcotest.(check string)
            what expected (Geocode.photon_reverse point).url
        in
        check "schlucht" schlucht
          "https://photon.komoot.io/reverse?lat=48.06330&lon=7.00810&lang=fr&limit=1&layer=city&layer=district&layer=locality";
        check "lausanne" lausanne
          "https://photon.komoot.io/reverse?lat=46.51970&lon=6.63230&lang=fr&limit=1&layer=city&layer=district&layer=locality";
        check "kew" kew
          "https://photon.komoot.io/reverse?lat=51.47870&lon=-0.29560&lang=fr&limit=1&layer=city&layer=district&layer=locality";
        check "atlantic" atlantic
          "https://photon.komoot.io/reverse?lat=46.20000&lon=-5.00000&lang=fr&limit=1&layer=city&layer=district&layer=locality"
    );
    ( "photon_reverse: provider is Photon",
      `Quick,
      fun () ->
        Alcotest.(check string)
          "provider" "photon"
          (Geocode.provider_to_string (Geocode.photon_reverse schlucht).provider)
    );
    ( "geoplateforme_lieu_dit: exact URL, category and searchgeom encoded"
      ^ " as a Circle of radius 500",
      `Quick,
      fun () ->
        let check what point expected =
          Alcotest.(check string)
            what expected (Geocode.geoplateforme_lieu_dit point).url
        in
        check "schlucht" schlucht
          "https://data.geopf.fr/geocodage/reverse?index=poi&lon=7.00810&lat=48.06330&limit=1&category=lieu-dit%20habit%C3%A9%2Clieu-dit%20non%20habit%C3%A9&searchgeom=%7B%22type%22%3A%22Circle%22%2C%22coordinates%22%3A%5B7.00810%2C48.06330%5D%2C%22radius%22%3A500%7D";
        check "landes" landes
          "https://data.geopf.fr/geocodage/reverse?index=poi&lon=-0.85000&lat=44.25000&limit=1&category=lieu-dit%20habit%C3%A9%2Clieu-dit%20non%20habit%C3%A9&searchgeom=%7B%22type%22%3A%22Circle%22%2C%22coordinates%22%3A%5B-0.85000%2C44.25000%5D%2C%22radius%22%3A500%7D"
    );
    ( "geoplateforme_lieu_dit: provider is Geoplateforme",
      `Quick,
      fun () ->
        Alcotest.(check string)
          "provider" "geoplateforme"
          (Geocode.provider_to_string
             (Geocode.geoplateforme_lieu_dit schlucht).provider) );
    ( "geoplateforme_commune: exact URL, searchgeom encoded as a Point",
      `Quick,
      fun () ->
        Alcotest.(check string)
          "landes"
          "https://data.geopf.fr/geocodage/reverse?index=poi&lon=-0.85000&lat=44.25000&limit=1&category=commune&searchgeom=%7B%22type%22%3A%22Point%22%2C%22coordinates%22%3A%5B-0.85000%2C44.25000%5D%7D"
          (Geocode.geoplateforme_commune landes).url );
    ( "request_to_string is the provider and the whole URL; request_endpoint \
       drops the query",
      `Quick,
      fun () ->
        Alcotest.(check string)
          "to_string"
          "photon https://photon.komoot.io/api?q=lac&lang=fr&limit=8"
          (Geocode.request_to_string (Geocode.photon_search "lac"));
        Alcotest.(check string)
          "endpoint, photon" "photon https://photon.komoot.io/reverse"
          (Geocode.request_endpoint (Geocode.photon_reverse schlucht));
        Alcotest.(check string)
          "endpoint, geoplateforme"
          "geoplateforme https://data.geopf.fr/geocodage/reverse"
          (Geocode.request_endpoint (Geocode.geoplateforme_commune landes)) );
    ( "photon_search: default limit 8, no near",
      `Quick,
      fun () ->
        Alcotest.(check string)
          "url" "https://photon.komoot.io/api?q=lac&lang=fr&limit=8"
          (Geocode.photon_search "lac").url );
    ( "photon_search: near adds lat and lon, limit is given",
      `Quick,
      fun () ->
        Alcotest.(check string)
          "url"
          "https://photon.komoot.io/api?q=schlucht&lang=fr&limit=3&lat=48.06330&lon=7.00810"
          (Geocode.photon_search ~near:schlucht ~limit:3 "schlucht").url );
    ( "photon_search: limit is clamped to [1, 20]",
      `Quick,
      fun () ->
        Alcotest.(check string)
          "0 clamps to 1" "https://photon.komoot.io/api?q=lac&lang=fr&limit=1"
          (Geocode.photon_search ~limit:0 "lac").url;
        Alcotest.(check string)
          "50 clamps to 20"
          "https://photon.komoot.io/api?q=lac&lang=fr&limit=20"
          (Geocode.photon_search ~limit:50 "lac").url );
    ( "photon_search: a query with a space, an accent and an ampersand",
      `Quick,
      fun () ->
        Alcotest.(check string)
          "url"
          "https://photon.komoot.io/api?q=une%20%26%20deux%20%C3%A9t%C3%A9&lang=fr&limit=8"
          (Geocode.photon_search "une & deux été").url );
    ( "photon_search: provider is Photon",
      `Quick,
      fun () ->
        Alcotest.(check string)
          "provider" "photon"
          (Geocode.provider_to_string (Geocode.photon_search "lac").provider) );
    ( "geoplateforme_wfs: keys and values encoded, in order; provider \
       Geoplateforme",
      `Quick,
      fun () ->
        let r = Geocode.geoplateforme_wfs [("A", "b c"); ("K", "x:y,z")] in
        Alcotest.(check string)
          "url" "https://data.geopf.fr/wfs/ows?A=b%20c&K=x%3Ay%2Cz" r.url;
        Alcotest.(check string)
          "provider" "geoplateforme"
          (Geocode.provider_to_string r.provider) );
  ]

(* ---------- the recording script names every fixture URL verbatim ---------- *)

let script_path = "../../scripts/record-geo-fixtures.sh"

let read_script () =
  try Some (In_channel.with_open_bin script_path In_channel.input_all)
  with Sys_error _ -> None

let contains ~needle haystack =
  let n = String.length needle and h = String.length haystack in
  let rec at i =
    match i > h - n with
    | true -> false
    | false -> (
        match String.equal (String.sub haystack i n) needle with
        | true -> true
        | false -> at (i + 1))
  in
  match n with 0 -> true | _ -> at 0

let script_tests =
  [
    ( "every recorded request's fetch line appears in the recording script",
      `Quick,
      fun () ->
        match read_script () with
        | None ->
            Alcotest.fail
              "scripts/record-geo-fixtures.sh is missing: cannot check fixture \
               URLs against it"
        | Some script ->
            List.iter
              (fun (file, (r : Geocode.request)) ->
                let line =
                  Printf.sprintf "fetch %s %s \"%s\"" file
                    (Geocode.provider_to_string r.provider)
                    r.url
                in
                match contains ~needle:line script with
                | true -> ()
                | false ->
                    Alcotest.failf "%s: line %s not found in %s" file line
                      script_path)
              recorded_requests );
    ( "every recorded fixture file exists in test/fixtures/",
      `Quick,
      fun () ->
        List.iter
          (fun (file, _) ->
            match Sys.file_exists (Filename.concat "../fixtures" file) with
            | true -> ()
            | false -> Alcotest.failf "missing fixture test/fixtures/%s" file)
          recorded_requests );
  ]

(* ---------- in_france ---------- *)

let in_france_tests =
  [
    ( "inside the box: Schlucht, Landes, Ajaccio, Brest",
      `Quick,
      fun () ->
        let check what (p : Places.point) =
          Alcotest.(check bool) what true (Geocode.in_france p)
        in
        check "schlucht" schlucht;
        check "landes" landes;
        check "ajaccio" {lat = 41.9192; lon = 8.7386};
        check "brest" {lat = 48.3904; lon = -4.4861} );
    ( "outside the box: Kew, Madrid, Berlin",
      `Quick,
      fun () ->
        let check what (p : Places.point) =
          Alcotest.(check bool) what false (Geocode.in_france p)
        in
        check "kew" kew;
        check "madrid" {lat = 40.4168; lon = -3.7038};
        check "berlin" {lat = 52.52; lon = 13.405} );
    ( "the four corners are inclusive",
      `Quick,
      fun () ->
        let check what (p : Places.point) =
          Alcotest.(check bool) what true (Geocode.in_france p)
        in
        check "south-west" {lat = 41.3; lon = -5.5};
        check "south-east" {lat = 41.3; lon = 9.7};
        check "north-west" {lat = 51.2; lon = -5.5};
        check "north-east" {lat = 51.2; lon = 9.7} );
    ( "just past each edge is outside",
      `Quick,
      fun () ->
        let check what (p : Places.point) =
          Alcotest.(check bool) what false (Geocode.in_france p)
        in
        check "south" {lat = 41.29; lon = 0.};
        check "north" {lat = 51.21; lon = 0.};
        check "west" {lat = 45.; lon = -5.51};
        check "east" {lat = 45.; lon = 9.71} );
    ( "nan is false",
      `Quick,
      fun () ->
        Alcotest.(check bool)
          "nan lat" false
          (Geocode.in_france {lat = Float.nan; lon = 7.});
        Alcotest.(check bool)
          "nan lon" false
          (Geocode.in_france {lat = 48.; lon = Float.nan}) );
  ]

(* ---------- near ---------- *)

let near_tests =
  let check what input expected =
    ( what,
      `Quick,
      fun () ->
        Alcotest.(check (option string)) what expected (Geocode.near input) )
  in
  [
    check "Le X" "Le Valtin" (Some "Près du Valtin");
    check "le X, lower case" "le Rain des Aulx" (Some "Près du Rain des Aulx");
    check "Les X" "Les Rousses" (Some "Près des Rousses");
    check "La X" "La Bresse" (Some "Près de la Bresse");
    check "L'X, straight apostrophe" "L'Isle-sur-la-Sorgue"
      (Some "Près de l’Isle-sur-la-Sorgue");
    check "L’X, curly apostrophe" "L’Isle-sur-la-Sorgue"
      (Some "Près de l’Isle-sur-la-Sorgue");
    check "a name starting with a vowel" "Orbey" (Some "Près d’Orbey");
    check "a name starting with an accented vowel" "Épinal"
      (Some "Près d’Épinal");
    check "a lower-case accented vowel" "île de Ré" (Some "Près d’île de Ré");
    check "Y is a vowel" "Yvoire" (Some "Près d’Yvoire");
    check "no elision before h" "Haguenau" (Some "Près de Haguenau");
    check "Lausanne: article prefix without a following space" "Lausanne"
      (Some "Près de Lausanne");
    check "Lesneven: article prefix without a following space" "Lesneven"
      (Some "Près de Lesneven");
    check "Leffe: article prefix without a following space" "Leffe"
      (Some "Près de Leffe");
    check "Le alone" "Le" (Some "Près de Le");
    check "L' alone" "L'" (Some "Près de L'");
    check "LE HAVRE: case-insensitive article, case of the rest kept" "LE HAVRE"
      (Some "Près du HAVRE");
    check "leading and trailing spaces are trimmed" "  Colmar "
      (Some "Près de Colmar");
    check "empty is None" "" None;
    check "blank is None" "   " None;
  ]

(* ---------- decoders over the fixtures, and error paths ---------- *)

let photon_name_tests =
  [
    ( "Schlucht: a place/locality gives its own name",
      `Quick,
      fun () ->
        Alcotest.(check name_opt_result)
          "name" (Ok (Some "Le Haut Gazon"))
          (Geocode.photon_name (json_fixture "photon_reverse_schlucht.json")) );
    ( "Lausanne: a place/square is not a place value, falls back to city",
      `Quick,
      fun () ->
        Alcotest.(check name_opt_result)
          "name" (Ok (Some "Lausanne"))
          (Geocode.photon_name (json_fixture "photon_reverse_lausanne.json")) );
    ( "Kew: a landuse polygon is not a place value, falls back to district",
      `Quick,
      fun () ->
        Alcotest.(check name_opt_result)
          "name" (Ok (Some "Kew"))
          (Geocode.photon_name (json_fixture "photon_reverse_kew.json")) );
    ( "Atlantic: no feature gives None",
      `Quick,
      fun () ->
        Alcotest.(check name_opt_result)
          "name" (Ok None)
          (Geocode.photon_name (json_fixture "photon_reverse_atlantic.json")) );
    ( "a place feature with a blank name falls back to district, then city;"
      ^ " null or non-string fields count as absent",
      `Quick,
      fun () ->
        let one props =
          `Assoc [("features", `List [`Assoc [("properties", `Assoc props)]])]
        in
        Alcotest.(check name_opt_result)
          "blank name, district" (Ok (Some "Quartier"))
          (Geocode.photon_name
             (one
                [
                  ("osm_key", `String "place");
                  ("osm_value", `String "village");
                  ("name", `String " ");
                  ("district", `String "Quartier");
                  ("city", `String "Ville");
                ]));
        Alcotest.(check name_opt_result)
          "null district, city" (Ok (Some "Ville"))
          (Geocode.photon_name
             (one [("district", `Null); ("city", `String "Ville")]));
        Alcotest.(check name_opt_result)
          "non-string fields only" (Ok None)
          (Geocode.photon_name (one [("district", `Int 3); ("city", `List [])]))
    );
    ( "features not an array is Unexpected",
      `Quick,
      fun () ->
        let expected =
          Error (Geocode.Unexpected {path = "/features"; expected = "array"})
        in
        Alcotest.(check name_opt_result)
          "no features field" expected
          (Geocode.photon_name (`Assoc []));
        Alcotest.(check name_opt_result)
          "features is not an array" expected
          (Geocode.photon_name (`Assoc [("features", `Int 3)])) );
  ]

let geoplateforme_name_tests =
  [
    ( "Schlucht lieu-dit: toponym",
      `Quick,
      fun () ->
        Alcotest.(check name_opt_result)
          "name" (Ok (Some "le Rain des Aulx"))
          (Geocode.geoplateforme_name
             (json_fixture "geoplateforme_lieu_dit_schlucht.json")) );
    ( "Landes commune: toponym",
      `Quick,
      fun () ->
        Alcotest.(check name_opt_result)
          "name" (Ok (Some "Commensacq"))
          (Geocode.geoplateforme_name
             (json_fixture "geoplateforme_commune_landes.json")) );
    ( "no feature gives None",
      `Quick,
      fun () ->
        Alcotest.(check name_opt_result)
          "name" (Ok None)
          (Geocode.geoplateforme_name
             (json_fixture "geoplateforme_lieu_dit_landes.json")) );
    ( "a blank toponym with a name array falls back to its first non-blank"
      ^ " entry",
      `Quick,
      fun () ->
        let j =
          `Assoc
            [
              ( "features",
                `List
                  [
                    `Assoc
                      [
                        ( "properties",
                          `Assoc
                            [
                              ("toponym", `String "  ");
                              ("name", `List [`String ""; `String "Vrai nom"]);
                            ] );
                      ];
                  ] );
            ]
        in
        Alcotest.(check name_opt_result)
          "name" (Ok (Some "Vrai nom"))
          (Geocode.geoplateforme_name j) );
    ( "a name that is not an array, or holds no string, gives None",
      `Quick,
      fun () ->
        let one name =
          `Assoc
            [
              ( "features",
                `List [`Assoc [("properties", `Assoc [("name", name)])]] );
            ]
        in
        Alcotest.(check name_opt_result)
          "a string" (Ok None)
          (Geocode.geoplateforme_name (one (`String "x")));
        Alcotest.(check name_opt_result)
          "an array of numbers" (Ok None)
          (Geocode.geoplateforme_name (one (`List [`Int 1]))) );
    ( "a toponym over 200 bytes counts as absent",
      `Quick,
      fun () ->
        let one toponym =
          `Assoc
            [
              ( "features",
                `List
                  [
                    `Assoc
                      [("properties", `Assoc [("toponym", `String toponym)])];
                  ] );
            ]
        in
        Alcotest.(check name_opt_result)
          "200 bytes kept"
          (Ok (Some (String.make 200 'a')))
          (Geocode.geoplateforme_name (one (String.make 200 'a')));
        Alcotest.(check name_opt_result)
          "201 bytes dropped" (Ok None)
          (Geocode.geoplateforme_name (one (String.make 201 'a'))) );
    ( "features not an array is Unexpected",
      `Quick,
      fun () ->
        let expected =
          Error (Geocode.Unexpected {path = "/features"; expected = "array"})
        in
        Alcotest.(check name_opt_result)
          "no features field" expected
          (Geocode.geoplateforme_name (`Assoc []));
        Alcotest.(check name_opt_result)
          "features is not an array" expected
          (Geocode.geoplateforme_name (`Assoc [("features", `Int 3)])) );
  ]

let photon_places_tests =
  [
    ( "col de la schlucht: the first place, its context and its point",
      `Quick,
      fun () ->
        match
          Geocode.photon_places
            (json_fixture "photon_search_col_de_la_schlucht.json")
        with
        | Error e ->
            Alcotest.failf "expected Ok, got %s" (Geocode.error_to_string e)
        | Ok [] -> Alcotest.fail "expected at least one place"
        | Ok (first :: _) ->
            Alcotest.(check string) "name" "Col de la Schlucht" first.name;
            Alcotest.(check (option string))
              "context" (Some "Le Valtin, Vosges, France") first.context;
            Alcotest.check (Alcotest.float 1e-9) "lat" 48.0641653
              first.point.lat;
            Alcotest.check (Alcotest.float 1e-9) "lon" 7.0226628 first.point.lon
    );
    ( "schlucht near the pass: three places, the first with its context",
      `Quick,
      fun () ->
        match
          Geocode.photon_places
            (json_fixture "photon_search_schlucht_near.json")
        with
        | Error e ->
            Alcotest.failf "expected Ok, got %s" (Geocode.error_to_string e)
        | Ok places -> (
            Alcotest.(check int) "count" 3 (List.length places);
            match places with
            | [] -> Alcotest.fail "expected at least one place"
            | first :: _ ->
                Alcotest.(check string) "name" "Schlucht" first.name;
                Alcotest.(check (option string))
                  "context" (Some "Xonrupt-Longemer, Vosges, France")
                  first.context) );
    ( "zzzzqqq: no feature gives []",
      `Quick,
      fun () ->
        Alcotest.(check (result places error))
          "places" (Ok [])
          (Geocode.photon_places (json_fixture "photon_search_zzzzqqq.json")) );
    ( "a feature with a blank or oversized name, or missing, non-finite or"
      ^ " non-number coordinates, is skipped, never an error",
      `Quick,
      fun () ->
        let feature ?(name = `String "Nom")
            ?(coords = `List [`Float 1.; `Float 2.]) () =
          `Assoc
            [
              ("properties", `Assoc [("name", name)]);
              ("geometry", `Assoc [("coordinates", coords)]);
            ]
        in
        let j =
          `Assoc
            [
              ( "features",
                `List
                  [
                    feature ~name:(`String "  ") ();
                    feature ~coords:`Null ();
                    feature ~name:(`String (String.make 201 'a')) ();
                    feature ~coords:(`List [`Float 1.]) ();
                    feature
                      ~coords:(`List [`Float Float.infinity; `Float 2.])
                      ();
                    feature ~coords:(`List [`Float 1.; `Float Float.nan]) ();
                    feature ~coords:(`List [`String "1"; `Float 2.]) ();
                    feature ();
                  ] );
            ]
        in
        Alcotest.(check (result places error))
          "only the valid feature survives"
          (Ok [{name = "Nom"; context = None; point = {lat = 2.; lon = 1.}}])
          (Geocode.photon_places j) );
    ( "integer coordinates are accepted; context drops blanks, the name and"
      ^ " repeats",
      `Quick,
      fun () ->
        let j =
          `Assoc
            [
              ( "features",
                `List
                  [
                    `Assoc
                      [
                        ( "properties",
                          `Assoc
                            [
                              ("name", `String "Gérardmer");
                              ("city", `String "Gérardmer");
                              ("county", `String "Vosges");
                              ("country", `String "Vosges");
                            ] );
                        ( "geometry",
                          `Assoc [("coordinates", `List [`Int 6; `Int 48])] );
                      ];
                    `Assoc
                      [
                        ( "properties",
                          `Assoc
                            [
                              ("name", `String "Seul");
                              ("city", `String "  ");
                              ("county", `Null);
                            ] );
                        ( "geometry",
                          `Assoc
                            [("coordinates", `List [`Float 6.5; `Float 48.5])]
                        );
                      ];
                  ] );
            ]
        in
        Alcotest.(check (result places error))
          "places"
          (Ok
             [
               {
                 name = "Gérardmer";
                 context = Some "Vosges";
                 point = {lat = 48.; lon = 6.};
               };
               {name = "Seul"; context = None; point = {lat = 48.5; lon = 6.5}};
             ])
          (Geocode.photon_places j) );
    ( "features not an array is Unexpected",
      `Quick,
      fun () ->
        let expected =
          Error (Geocode.Unexpected {path = "/features"; expected = "array"})
        in
        Alcotest.(check (result places error))
          "no features field" expected
          (Geocode.photon_places (`Assoc []));
        Alcotest.(check (result places error))
          "features is not an array" expected
          (Geocode.photon_places (`Assoc [("features", `Int 3)])) );
  ]

let json_of_string_tests =
  [
    ( "non-JSON text is Not_json",
      `Quick,
      fun () ->
        match Geocode.json_of_string "<html></html>" with
        | Error (Geocode.Not_json _) -> ()
        | Error (Geocode.Unexpected _) ->
            Alcotest.fail "expected Not_json, got Unexpected"
        | Ok _ -> Alcotest.fail "expected Error, got Ok" );
  ]

(* ---------- the reverse_ign / reverse_photon programs, against the
   recorded fixtures ---------- *)

(* The result and every request the program issued. With
   [answer_from_fixtures], each is answered by looking up its exact URL among
   {!recorded_requests}, built by the request functions rather than a second
   copy of the strings: an unknown URL fails the test rather than being
   guessed at. *)
let run_program ~answer program =
  let rec step acc = function
    | Geocode.Done result -> (result, List.rev acc)
    | Geocode.Get (req, k) -> step (req :: acc) (k (answer req))
  in
  step [] program

let request_line (r : Geocode.request) =
  Geocode.provider_to_string r.provider ^ " " ^ r.url

let answer_from_fixtures (req : Geocode.request) =
  match
    List.find_opt
      (fun (_, (r : Geocode.request)) -> String.equal r.url req.url)
      recorded_requests
  with
  | Some (file, _) -> json_fixture file
  | None -> Alcotest.failf "no recorded fixture matches url %s" req.url

let reverse_ign_tests =
  [
    ( "Schlucht: found at the lieu-dit step, no other request made",
      `Quick,
      fun () ->
        let result, reqs =
          run_program ~answer:answer_from_fixtures
            (Geocode.reverse_ign schlucht)
        in
        Alcotest.(check name_opt_result)
          "result" (Ok (Some "Près du Rain des Aulx")) result;
        Alcotest.(check (list string))
          "requests"
          [request_line (Geocode.geoplateforme_lieu_dit schlucht)]
          (List.map request_line reqs) );
    ( "Landes: lieu-dit empty, found at the commune step",
      `Quick,
      fun () ->
        let result, reqs =
          run_program ~answer:answer_from_fixtures (Geocode.reverse_ign landes)
        in
        Alcotest.(check name_opt_result)
          "result" (Ok (Some "Près de Commensacq")) result;
        Alcotest.(check (list string))
          "requests"
          [
            request_line (Geocode.geoplateforme_lieu_dit landes);
            request_line (Geocode.geoplateforme_commune landes);
          ]
          (List.map request_line reqs) );
    ( "Lausanne: in the coarse box, lieu-dit and commune both empty",
      `Quick,
      fun () ->
        let result, reqs =
          run_program ~answer:answer_from_fixtures
            (Geocode.reverse_ign lausanne)
        in
        Alcotest.(check name_opt_result) "result" (Ok None) result;
        Alcotest.(check (list string))
          "requests, no Photon"
          [
            request_line (Geocode.geoplateforme_lieu_dit lausanne);
            request_line (Geocode.geoplateforme_commune lausanne);
          ]
          (List.map request_line reqs) );
    ( "Atlantic: in the box, lieu-dit and commune both empty",
      `Quick,
      fun () ->
        let result, reqs =
          run_program ~answer:answer_from_fixtures
            (Geocode.reverse_ign atlantic)
        in
        Alcotest.(check name_opt_result) "result" (Ok None) result;
        Alcotest.(check (list string))
          "requests, no Photon"
          [
            request_line (Geocode.geoplateforme_lieu_dit atlantic);
            request_line (Geocode.geoplateforme_commune atlantic);
          ]
          (List.map request_line reqs) );
    ( "Kew: outside the box, no request at all",
      `Quick,
      fun () ->
        let result, reqs =
          run_program ~answer:answer_from_fixtures (Geocode.reverse_ign kew)
        in
        Alcotest.(check name_opt_result) "result" (Ok None) result;
        Alcotest.(check int) "no request" 0 (List.length reqs) );
    ( "a payload rejected at the lieu-dit step stops with no further request",
      `Quick,
      fun () ->
        let result, reqs =
          run_program
            ~answer:(fun _ -> `Assoc [("features", `Int 3)])
            (Geocode.reverse_ign schlucht)
        in
        Alcotest.(check name_opt_result)
          "result"
          (Error (Geocode.Unexpected {path = "/features"; expected = "array"}))
          result;
        Alcotest.(check int) "exactly one request was made" 1 (List.length reqs)
    );
    ( "a payload rejected at the commune step is an error, two requests",
      `Quick,
      fun () ->
        let lieu_dit = Geocode.geoplateforme_lieu_dit landes in
        let result, reqs =
          run_program
            ~answer:(fun (req : Geocode.request) ->
              match Geocode.equal_request req lieu_dit with
              | true -> answer_from_fixtures req
              | false -> `Assoc [("features", `Int 3)])
            (Geocode.reverse_ign landes)
        in
        Alcotest.(check name_opt_result)
          "result"
          (Error (Geocode.Unexpected {path = "/features"; expected = "array"}))
          result;
        Alcotest.(check (list string))
          "requests"
          [
            request_line lieu_dit;
            request_line (Geocode.geoplateforme_commune landes);
          ]
          (List.map request_line reqs) );
  ]

let reverse_photon_tests =
  [
    ( "Kew: one request, found",
      `Quick,
      fun () ->
        let result, reqs =
          run_program ~answer:answer_from_fixtures (Geocode.reverse_photon kew)
        in
        Alcotest.(check name_opt_result)
          "result" (Ok (Some "Près de Kew")) result;
        Alcotest.(check (list string))
          "requests"
          [request_line (Geocode.photon_reverse kew)]
          (List.map request_line reqs) );
    ( "Lausanne: found, no Géoplateforme request at all",
      `Quick,
      fun () ->
        let result, reqs =
          run_program ~answer:answer_from_fixtures
            (Geocode.reverse_photon lausanne)
        in
        Alcotest.(check name_opt_result)
          "result" (Ok (Some "Près de Lausanne")) result;
        Alcotest.(check (list string))
          "requests"
          [request_line (Geocode.photon_reverse lausanne)]
          (List.map request_line reqs) );
    ( "Atlantic: no feature, one request",
      `Quick,
      fun () ->
        let result, reqs =
          run_program ~answer:answer_from_fixtures
            (Geocode.reverse_photon atlantic)
        in
        Alcotest.(check name_opt_result) "result" (Ok None) result;
        Alcotest.(check int) "one request" 1 (List.length reqs) );
    ( "Schlucht: the expected name is computed from the fixture through the \
       decoder and near, never hand-written",
      `Quick,
      fun () ->
        let expected =
          match
            Geocode.photon_name (json_fixture "photon_reverse_schlucht.json")
          with
          | Error e -> Error e
          | Ok None -> Ok None
          | Ok (Some name) -> Ok (Geocode.near name)
        in
        let result, reqs =
          run_program ~answer:answer_from_fixtures
            (Geocode.reverse_photon schlucht)
        in
        Alcotest.(check name_opt_result) "result" expected result;
        Alcotest.(check (list string))
          "one request, provider Photon"
          [request_line (Geocode.photon_reverse schlucht)]
          (List.map request_line reqs) );
    ( "a bad payload is an error, one request",
      `Quick,
      fun () ->
        let result, reqs =
          run_program
            ~answer:(fun _ -> `Assoc [("features", `Int 3)])
            (Geocode.reverse_photon kew)
        in
        Alcotest.(check name_opt_result)
          "result"
          (Error (Geocode.Unexpected {path = "/features"; expected = "array"}))
          result;
        Alcotest.(check (list string))
          "requests"
          [request_line (Geocode.photon_reverse kew)]
          (List.map request_line reqs) );
  ]

(* ---------- map, or_else ---------- *)

let map_tests =
  [
    ( "map (Done x) = Done (f x)",
      `Quick,
      fun () ->
        match Geocode.map (fun n -> n + 1) (Geocode.Done 41) with
        | Geocode.Done 42 -> ()
        | Geocode.Done n -> Alcotest.failf "expected Done 42, got Done %d" n
        | Geocode.Get _ -> Alcotest.fail "expected Done, got Get" );
    ( "map over a program with requests keeps the same requests, in order, and \
       applies f to the result",
      `Quick,
      fun () ->
        let base = Geocode.reverse_ign landes in
        let mapped = Geocode.map (Result.map Option.is_some) base in
        let base_result, base_reqs =
          run_program ~answer:answer_from_fixtures base
        in
        let mapped_result, mapped_reqs =
          run_program ~answer:answer_from_fixtures mapped
        in
        Alcotest.(check (list string))
          "same requests, same order"
          (List.map request_line base_reqs)
          (List.map request_line mapped_reqs);
        Alcotest.(check (result bool error))
          "mapped result is f applied to the base result"
          (Result.map Option.is_some base_result)
          mapped_result );
  ]

let or_else_tests =
  [
    ( "Done (Ok None): next is run",
      `Quick,
      fun () ->
        let next_called = ref false in
        let next () =
          next_called := true;
          Geocode.Done (Ok (Some "next"))
        in
        match Geocode.or_else (Geocode.Done (Ok None)) next with
        | Geocode.Done (Ok (Some "next")) ->
            Alcotest.(check bool) "next was called" true !next_called
        | Geocode.Done (Ok None) -> Alcotest.fail "next's result was dropped"
        | Geocode.Done (Error _) -> Alcotest.fail "unexpected error"
        | Geocode.Get _ -> Alcotest.fail "unexpected Get"
        | Geocode.Done (Ok (Some s)) ->
            Alcotest.failf "expected \"next\", got %S" s );
    ( "Done (Ok (Some _)): next is never called, no request of next is issued",
      `Quick,
      fun () ->
        let next () : (string option, Geocode.error) result Geocode.program =
          Alcotest.fail "next must not be called"
        in
        match Geocode.or_else (Geocode.Done (Ok (Some "found"))) next with
        | Geocode.Done (Ok (Some "found")) -> ()
        | Geocode.Done (Ok _) -> Alcotest.fail "result changed"
        | Geocode.Done (Error _) -> Alcotest.fail "unexpected error"
        | Geocode.Get _ -> Alcotest.fail "unexpected Get" );
    ( "Done (Error _): next is never called",
      `Quick,
      fun () ->
        let err = Geocode.Unexpected {path = "/x"; expected = "y"} in
        let next () : (string option, Geocode.error) result Geocode.program =
          Alcotest.fail "next must not be called"
        in
        match Geocode.or_else (Geocode.Done (Error err)) next with
        | Geocode.Done (Error e) ->
            Alcotest.(check bool) "same error" true (Geocode.equal_error e err)
        | Geocode.Done (Ok _) -> Alcotest.fail "expected Error"
        | Geocode.Get _ -> Alcotest.fail "unexpected Get" );
  ]

let () =
  Alcotest.run "geocode"
    [
      ("request URLs", url_tests);
      ("record-geo-fixtures.sh", script_tests);
      ("in_france", in_france_tests);
      ("near", near_tests);
      ("photon_name", photon_name_tests);
      ("geoplateforme_name", geoplateforme_name_tests);
      ("photon_places", photon_places_tests);
      ("json_of_string", json_of_string_tests);
      ("reverse_ign", reverse_ign_tests);
      ("reverse_photon", reverse_photon_tests);
      ("map", map_tests);
      ("or_else", or_else_tests);
    ]
