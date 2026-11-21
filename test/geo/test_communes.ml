module Communes = Herbier_geo.Communes
module Geocode = Herbier_geo.Geocode
module Near = Herbier_geo.Near
module Places = Herbier_domain.Places
module Code = Communes.Code
module Fixture = Herbier_test_support.Fixture
module Text = Herbier_test_support.Text

let code s =
  match Code.of_string s with
  | Some c -> c
  | None -> failwith (s ^ " is not a département code")

let codes = List.map Code.to_string

(* ---------- fixture plumbing (same as test_geocode.ml) ---------- *)

let json_fixture name =
  match Geocode.json_of_string (Fixture.read name) with
  | Ok j -> j
  | Error e -> failwith (name ^ ": " ^ Geocode.error_to_string e)

let departements_json =
  lazy (json_fixture "geoplateforme_wfs_departements.json")

let communes_90_json = lazy (json_fixture "geoplateforme_wfs_communes_90.json")

(* Lot (46): the Figeac and Pélégri points of M5.83 (test_geocode.ml). *)
let communes_46_json = lazy (json_fixture "geoplateforme_wfs_communes_46.json")
let communes_99_json = lazy (json_fixture "geoplateforme_wfs_communes_99.json")

(* Mayotte (976): the overseas proof — the WFS serves 971-974 and 976 with
   the same request as a metropolitan département. *)
let communes_976_json =
  lazy (json_fixture "geoplateforme_wfs_communes_976.json")

(* ---------- points (measured by ray casting on the raw payload) ---------- *)

let belfort : Places.point = {lat = 47.6380; lon = 6.8628}
let giromagny : Places.point = {lat = 47.7420; lon = 6.8280}
let eloie : Places.point = {lat = 47.6872; lon = 6.8714}
let landes : Places.point = {lat = 44.25; lon = -0.85}
let schlucht : Places.point = {lat = 48.0633; lon = 7.0081}

(* Mamoudzou (976): inside its polygon, checked by ray casting on the raw
   payload (bbox lon <= 45.300, so a point east of it is open sea). *)
let mamoudzou : Places.point = {lat = -12.7806; lon = 45.2279}
let mayotte_open_sea : Places.point = {lat = -12.80; lon = 45.60}

(* test_geocode.ml's points: inside Figeac, and Pélégri (Lissac-et-Mouret). *)
let figeac : Places.point = {lat = 44.602; lon = 2.03}
let pelegri : Places.point = {lat = 44.6300; lon = 1.9835}

(* ---------- testables ---------- *)

let departement_json (d : Communes.departement) =
  `Assoc [("code", `String (Code.to_string d.code)); ("name", `String d.name)]

let departement =
  Alcotest.testable
    (fun f d ->
      Format.pp_print_string f (Yojson.Safe.to_string (departement_json d)))
    Communes.equal_departement

let departements_l = Alcotest.list departement

let error =
  Alcotest.testable
    (fun f e -> Format.pp_print_string f (Geocode.error_to_string e))
    Geocode.equal_error

let departements_result = Alcotest.result departements_l error

let pack =
  Alcotest.testable
    (fun f p -> Format.pp_print_string f (Communes.to_string p))
    Communes.equal_pack

let pack_result = Alcotest.result pack error

(* ---------- Code ---------- *)

let valid_code code = Option.is_some (Code.of_string code)

let valid_code_tests =
  [
    ( "true for metropolitan codes, Corse and an overseas department",
      `Quick,
      fun () ->
        List.iter
          (fun code ->
            Alcotest.(check bool)
              (Printf.sprintf "of_string %S" code)
              true (valid_code code);
            Alcotest.(check string)
              (Printf.sprintf "to_string (of_string %S)" code)
              code
              (Code.to_string (Option.get (Code.of_string code))))
          ["01"; "68"; "95"; "2A"; "2B"; "971"; "976"] );
    ( "false for the empty string, wrong length, wrong case and a quote",
      `Quick,
      fun () ->
        List.iter
          (fun code ->
            Alcotest.(check bool)
              (Printf.sprintf "of_string %S" code)
              false (valid_code code))
          [
            "";
            "1";
            "001";
            "2a";
            "2C";
            "96x";
            "68'";
            "68' or '1'='1'";
            "00";
            "20";
            "96";
            "99";
            "970";
            "977";
            "9a";
            "'";
            "9'";
          ] );
  ]

(* ---------- request URLs ---------- *)

let force_communes_request departement =
  Communes.communes_request ~departement:(code departement)

let url_tests =
  [
    ( "departements_request: exact URL, endpoint drops the query",
      `Quick,
      fun () ->
        Alcotest.(check string)
          "url"
          "https://data.geopf.fr/wfs/ows?SERVICE=WFS&VERSION=2.0.0&REQUEST=GetFeature&OUTPUTFORMAT=application%2Fjson&TYPENAMES=ADMINEXPRESS-COG-CARTO.LATEST%3Adepartement&PROPERTYNAME=code_insee%2Cnom_officiel&SORTBY=code_insee&COUNT=5000"
          Communes.departements_request.url;
        Alcotest.(check string)
          "endpoint" "geoplateforme https://data.geopf.fr/wfs/ows"
          (Geocode.request_endpoint Communes.departements_request) );
    ( "communes_request ~departement:\"90\": exact URL, endpoint drops the query",
      `Quick,
      fun () ->
        let r = force_communes_request "90" in
        Alcotest.(check string)
          "url"
          "https://data.geopf.fr/wfs/ows?SERVICE=WFS&VERSION=2.0.0&REQUEST=GetFeature&OUTPUTFORMAT=application%2Fjson&TYPENAMES=ADMINEXPRESS-COG-CARTO.LATEST%3Acommune&PROPERTYNAME=code_insee%2Cnom_officiel%2Cgeometrie&SORTBY=code_insee&COUNT=5000&CQL_FILTER=code_insee_du_departement%3D%2790%27"
          r.url;
        Alcotest.(check string)
          "endpoint" "geoplateforme https://data.geopf.fr/wfs/ows"
          (Geocode.request_endpoint r) );
  ]

(* The unknown-code fixture (geoplateforme_wfs_communes_99.json) cannot be
   built by {!Communes.communes_request} ("99" is not a code): its script line
   is the "90" request's URL with only the quoted code changed. *)
let communes_99_recorded_url () =
  let url = (force_communes_request "90").url in
  let code_90 = "%2790%27" in
  let n = String.length url and k = String.length code_90 in
  match n >= k && String.equal (String.sub url (n - k) k) code_90 with
  | true -> String.sub url 0 (n - k) ^ "%2799%27"
  | false ->
      Alcotest.failf "the 90 request does not end with %s: %s" code_90 url

let fixture_script_tests =
  [
    ( "the recording script fetches the unknown-code fixture at the 90 \
       request's URL with the code 99",
      `Quick,
      fun () ->
        let script_path = "../../scripts/record-geo-fixtures.sh" in
        match
          try Some (In_channel.with_open_bin script_path In_channel.input_all)
          with Sys_error _ -> None
        with
        | None ->
            Alcotest.fail
              "scripts/record-geo-fixtures.sh is missing: cannot check the \
               fixture URL against it"
        | Some script ->
            let line =
              Printf.sprintf
                "fetch geoplateforme_wfs_communes_99.json geoplateforme \"%s\""
                (communes_99_recorded_url ())
            in
            Alcotest.(check bool)
              "fetch line present" true
              (Text.contains ~sub:line script) );
    ( "the recording script fetches the 976 (Mayotte) fixture at \
       communes_request ~departement:976's exact URL",
      `Quick,
      fun () ->
        let script_path = "../../scripts/record-geo-fixtures.sh" in
        match
          try Some (In_channel.with_open_bin script_path In_channel.input_all)
          with Sys_error _ -> None
        with
        | None ->
            Alcotest.fail
              "scripts/record-geo-fixtures.sh is missing: cannot check the \
               fixture URL against it"
        | Some script ->
            let line =
              Printf.sprintf
                "fetch geoplateforme_wfs_communes_976.json geoplateforme \"%s\""
                (force_communes_request "976").url
            in
            Alcotest.(check bool)
              "fetch line present" true
              (Text.contains ~sub:line script) );
    ( "the recording script fetches the 46 (Lot) fixture at communes_request \
       ~departement:46's exact URL",
      `Quick,
      fun () ->
        let script_path = "../../scripts/record-geo-fixtures.sh" in
        match
          try Some (In_channel.with_open_bin script_path In_channel.input_all)
          with Sys_error _ -> None
        with
        | None ->
            Alcotest.fail
              "scripts/record-geo-fixtures.sh is missing: cannot check the \
               fixture URL against it"
        | Some script ->
            let line =
              Printf.sprintf
                "fetch geoplateforme_wfs_communes_46.json geoplateforme \"%s\""
                (force_communes_request "46").url
            in
            Alcotest.(check bool)
              "fetch line present" true
              (Text.contains ~sub:line script) );
  ]

(* The departements and 90 fetch lines are cross-checked in
   test_geocode.ml's recorded requests. *)

(* ---------- departements ---------- *)

let departements_tests =
  [
    ( "101 entries, first is Ain, contains 2A/2B/976, sorted by code",
      `Quick,
      fun () ->
        match Communes.departements (Lazy.force departements_json) with
        | Error e ->
            Alcotest.failf "expected Ok, got %s" (Geocode.error_to_string e)
        | Ok ds ->
            Alcotest.(check int) "count" 101 (List.length ds);
            (match ds with
            | first :: _ ->
                Alcotest.(check departement)
                  "first"
                  {code = code "01"; name = "Ain"}
                  first
            | [] -> Alcotest.fail "expected at least one department");
            List.iter
              (fun c ->
                Alcotest.(check bool)
                  (Printf.sprintf "contains %s" c)
                  true
                  (List.exists
                     (fun (d : Communes.departement) ->
                       String.equal (Code.to_string d.code) c)
                     ds))
              ["2A"; "2B"; "976"];
            let ds_codes =
              List.map (fun (d : Communes.departement) -> d.code) ds
            in
            Alcotest.(check (list string))
              "sorted by code"
              (List.sort String.compare (codes ds_codes))
              (codes ds_codes) );
    ( "features not an array is Unexpected",
      `Quick,
      fun () ->
        Alcotest.(check departements_result)
          "no features field"
          (Error (Geocode.Unexpected {path = "/features"; expected = "array"}))
          (Communes.departements (`Assoc [])) );
    ( "an invalid code is skipped, a duplicate code keeps the first",
      `Quick,
      fun () ->
        let feature code name =
          `Assoc
            [
              ("type", `String "Feature");
              ("geometry", `Null);
              ( "properties",
                `Assoc
                  [("code_insee", `String code); ("nom_officiel", `String name)]
              );
            ]
        in
        let j =
          match Lazy.force departements_json with
          | `Assoc kvs ->
              `Assoc
                (List.map
                   (fun (k, v) ->
                     match (k, v) with
                     | "features", `List fs ->
                         ( k,
                           `List
                             (fs
                             @ [
                                 feature "68' or '1'='1" "Injection";
                                 feature "01" "Doublon";
                               ]) )
                     | _ -> (k, v))
                   kvs)
          | other -> other
        in
        match Communes.departements j with
        | Error e ->
            Alcotest.failf "expected Ok, got %s" (Geocode.error_to_string e)
        | Ok ds ->
            Alcotest.(check int) "still 101" 101 (List.length ds);
            Alcotest.(check (option string))
              "01 keeps its first name" (Some "Ain")
              (List.find_map
                 (fun (d : Communes.departement) ->
                   match Code.to_string d.code with
                   | "01" -> Some d.name
                   | _ -> None)
                 ds) );
  ]

(* ---------- available ---------- *)

let available_tests =
  [
    ( "drops exactly the downloaded codes, order kept",
      `Quick,
      fun () ->
        let ain : Communes.departement = {code = code "01"; name = "Ain"} in
        let corse : Communes.departement =
          {code = code "2A"; name = "Corse-du-Sud"}
        in
        let belfort_d : Communes.departement =
          {code = code "90"; name = "Territoire de Belfort"}
        in
        Alcotest.(check departements_l)
          "90 and 2A dropped" [ain]
          (Communes.available
             ~downloaded:[code "90"; code "2A"]
             [ain; corse; belfort_d]) );
  ]

(* ---------- pack_of_payload ---------- *)

let on_grid x = Float.abs ((x *. 1e5) -. Float.round (x *. 1e5)) < 1e-6

let pack_vertex_count (p : Communes.pack) =
  List.fold_left
    (fun acc (c : Communes.commune) ->
      List.fold_left
        (fun acc polygon ->
          List.fold_left (fun acc ring -> acc + Array.length ring) acc polygon)
        acc c.polygons)
    0 p.communes

let force_pack_of_payload ~departement j =
  match Communes.pack_of_payload ~departement:(code departement) j with
  | Ok p -> p
  | Error e ->
      Alcotest.failf "pack_of_payload ~departement:%S: %s" departement
        (Geocode.error_to_string e)

let pack_90 =
  lazy (force_pack_of_payload ~departement:"90" (Lazy.force communes_90_json))

let pack_of_payload_ok () =
  let p = Lazy.force pack_90 in
  Alcotest.(check string) "departement" "90" (Code.to_string p.departement);
  Alcotest.(check int) "communes count" 101 (List.length p.communes);
  (match p.communes with
  | first :: _ ->
      Alcotest.(check string) "first insee" "90001" first.insee;
      Alcotest.(check string) "first name" "Andelnans" first.name
  | [] -> Alcotest.fail "expected at least one commune");
  Alcotest.(check (list string))
    "sorted by insee"
    (List.sort String.compare
       (List.map (fun (c : Communes.commune) -> c.insee) p.communes))
    (List.map (fun (c : Communes.commune) -> c.insee) p.communes);
  List.iter
    (fun (c : Communes.commune) ->
      List.iter
        (fun polygon ->
          List.iter
            (fun ring ->
              Alcotest.(check bool)
                (Printf.sprintf "%s: ring has >= 3 vertices" c.insee)
                true
                (Array.length ring >= 3);
              (match Array.length ring > 0 with
              | true ->
                  Alcotest.(check bool)
                    (Printf.sprintf "%s: ring is not closed" c.insee)
                    false
                    (fst ring.(0) = fst ring.(Array.length ring - 1)
                    && snd ring.(0) = snd ring.(Array.length ring - 1))
              | false -> ());
              Array.iter
                (fun (lon, lat) ->
                  Alcotest.(check bool)
                    (Printf.sprintf "%s: lon on the 1e-5 grid" c.insee)
                    true (on_grid lon);
                  Alcotest.(check bool)
                    (Printf.sprintf "%s: lat on the 1e-5 grid" c.insee)
                    true (on_grid lat))
                ring)
            polygon)
        c.polygons)
    p.communes;
  let total = pack_vertex_count p in
  Alcotest.(check bool)
    "fewer vertices than the raw payload (11294)" true (total < 11294);
  Alcotest.(check bool) "at least one vertex" true (total > 0)

(* Mayotte (976): the WFS serves an overseas département exactly like a
   metropolitan one. *)
let pack_46 =
  lazy (force_pack_of_payload ~departement:"46" (Lazy.force communes_46_json))

let pack_976 =
  lazy (force_pack_of_payload ~departement:"976" (Lazy.force communes_976_json))

let pack_of_payload_976_ok () =
  let p = Lazy.force pack_976 in
  Alcotest.(check string) "departement" "976" (Code.to_string p.departement);
  Alcotest.(check int) "communes count" 17 (List.length p.communes);
  List.iter
    (fun (c : Communes.commune) ->
      Alcotest.(check bool)
        (Printf.sprintf "%s: name non-blank" c.insee)
        true
        (String.length (String.trim c.name) > 0))
    p.communes;
  Alcotest.(check pack_result)
    "round trip: of_string (to_string p) = Ok p" (Ok p)
    (Communes.of_string (Communes.to_string p))

let pack_of_payload_truncated () =
  let j =
    match Lazy.force communes_90_json with
    | `Assoc kvs ->
        `Assoc
          (List.map
             (fun (k, v) ->
               match k with "numberMatched" -> (k, `Int 102) | _ -> (k, v))
             kvs)
    | other -> other
  in
  Alcotest.(check pack_result)
    "numberMatched greater than features is Unexpected"
    (Error
       (Geocode.Unexpected
          {path = "/numberMatched"; expected = "all features in one page"}))
    (Communes.pack_of_payload ~departement:(code "90") j)

let pack_of_payload_empty () =
  Alcotest.(check pack_result)
    "an empty collection is Unexpected"
    (Error
       (Geocode.Unexpected
          {path = "/features"; expected = "at least one commune"}))
    (Communes.pack_of_payload ~departement:(code "90")
       (Lazy.force communes_99_json))

let pack_of_payload_not_an_array () =
  Alcotest.(check pack_result)
    "no features field"
    (Error (Geocode.Unexpected {path = "/features"; expected = "array"}))
    (Communes.pack_of_payload ~departement:(code "90") (`Assoc []))

(* The recorded 90 payload with the first feature's geometry type replaced:
   that commune is skipped, the 100 others kept. *)
let pack_of_payload_skips_a_bad_feature () =
  let break_geometry = function
    | `Assoc fkvs ->
        `Assoc
          (List.map
             (fun (k, v) ->
               match (k, v) with
               | "geometry", `Assoc gkvs ->
                   ( k,
                     `Assoc
                       (List.map
                          (fun (gk, gv) ->
                            match gk with
                            | "type" -> (gk, `String "LineString")
                            | _ -> (gk, gv))
                          gkvs) )
               | _ -> (k, v))
             fkvs)
    | other -> other
  in
  let j =
    match Lazy.force communes_90_json with
    | `Assoc kvs ->
        `Assoc
          (List.map
             (fun (k, v) ->
               match (k, v) with
               | "features", `List (first :: rest) ->
                   (k, `List (break_geometry first :: rest))
               | _ -> (k, v))
             kvs)
    | other -> other
  in
  match Communes.pack_of_payload ~departement:(code "90") j with
  | Error e -> Alcotest.failf "expected Ok, got %s" (Geocode.error_to_string e)
  | Ok p ->
      Alcotest.(check int) "100 communes" 100 (List.length p.communes);
      Alcotest.(check bool)
        "Andelnans (90001) skipped" false
        (List.exists
           (fun (c : Communes.commune) -> String.equal c.insee "90001")
           p.communes)

(* ---------- synthetic payloads ---------- *)

let feature ?(insee = "90001") ?(name = `String "Synthé") geometry =
  `Assoc
    [
      ("type", `String "Feature");
      ( "properties",
        `Assoc [("code_insee", `String insee); ("nom_officiel", name)] );
      ("geometry", geometry);
    ]

let collection features =
  `Assoc [("type", `String "FeatureCollection"); ("features", `List features)]

(* A closed square ring of about 750 x 1100 m near Belfort, its vertices
   through [num]. *)
let square_coords ?(num = fun x -> `Float x) () =
  `List
    (List.map
       (fun (lon, lat) -> `List [num lon; num lat])
       [(6.8, 47.6); (6.81, 47.6); (6.81, 47.61); (6.8, 47.61); (6.8, 47.6)])

let multi ring =
  `Assoc
    [("type", `String "MultiPolygon"); ("coordinates", `List [`List [ring]])]

let good =
  feature ~insee:"90002" ~name:(`String "Bonne") (multi (square_coords ()))

let insees = function
  | Ok (p : Communes.pack) ->
      List.map (fun (c : Communes.commune) -> c.insee) p.communes
  | Error e -> Alcotest.failf "expected Ok, got %s" (Geocode.error_to_string e)

let pack_of_synthetic features =
  Communes.pack_of_payload ~departement:(code "90") (collection features)

let synthetic_payload_tests =
  [
    ( "a Polygon geometry is one polygon of one ring",
      `Quick,
      fun () ->
        match
          pack_of_synthetic
            [
              feature
                (`Assoc
                   [
                     ("type", `String "Polygon");
                     ("coordinates", `List [square_coords ()]);
                   ]);
            ]
        with
        | Ok {communes = [c]; _} ->
            Alcotest.(check int) "one polygon" 1 (List.length c.polygons);
            Alcotest.(check (list int))
              "one ring of 4 vertices" [4]
              (List.map Array.length (List.concat c.polygons))
        | Ok _ -> Alcotest.fail "expected one commune"
        | Error e ->
            Alcotest.failf "expected Ok, got %s" (Geocode.error_to_string e) );
    ( "integer coordinates are accepted",
      `Quick,
      fun () ->
        let ints =
          `List
            (List.map
               (fun (lon, lat) -> `List [`Int lon; `Int lat])
               [(6, 47); (7, 47); (7, 48); (6, 48); (6, 47)])
        in
        Alcotest.(check (list string))
          "kept" ["90001"]
          (insees (pack_of_synthetic [feature (multi ints)])) );
    ( "a non-numeric or non-finite coordinate skips the feature",
      `Quick,
      fun () ->
        List.iter
          (fun bad ->
            let num x =
              match Float.equal x 6.81 with true -> bad | false -> `Float x
            in
            Alcotest.(check (list string))
              "only the good one" ["90002"]
              (insees
                 (pack_of_synthetic
                    [feature (multi (square_coords ~num ())); good])))
          [`String "6.81"; `Float Float.nan; `Float Float.infinity; `Null] );
    ( "a code_insee that is not 5 characters, a blank or a 201-byte name skips \
       the feature",
      `Quick,
      fun () ->
        List.iter
          (fun f ->
            Alcotest.(check (list string))
              "only the good one" ["90002"]
              (insees (pack_of_synthetic [f; good])))
          [
            feature ~insee:"9001" (multi (square_coords ()));
            feature ~name:(`String "  ") (multi (square_coords ()));
            feature
              ~name:(`String (String.make 201 'a'))
              (multi (square_coords ()));
            feature ~name:`Null (multi (square_coords ()));
          ] );
    ( "a name is trimmed; 200 bytes is still a name",
      `Quick,
      fun () ->
        let names features =
          match pack_of_synthetic features with
          | Ok p -> List.map (fun (c : Communes.commune) -> c.name) p.communes
          | Error e ->
              Alcotest.failf "expected Ok, got %s" (Geocode.error_to_string e)
        in
        Alcotest.(check (list string))
          "trimmed" ["Belfort"]
          (names
             [feature ~name:(`String " Belfort ") (multi (square_coords ()))]);
        let long = String.make 200 'a' in
        Alcotest.(check (list string))
          "200 bytes" [long]
          (names [feature ~name:(`String long) (multi (square_coords ()))]) );
    ( "COUNT features or more is Unexpected, whatever numberMatched says",
      `Quick,
      fun () ->
        Alcotest.(check pack_result)
          "5000 features"
          (Error
             (Geocode.Unexpected
                {path = "/features"; expected = "fewer than COUNT features"}))
          (pack_of_synthetic (List.init 5000 (fun _ -> good))) );
    ( "a ring of 100 000 vertices decodes (no recursion per vertex)",
      `Quick,
      fun () ->
        (* A square side of 0.01° holds 1000 grid steps: the 25 000 points per
           side collapse to them once rounded. *)
        let n = 25_000 in
        let side (ax, ay) (bx, by) =
          List.init n (fun i ->
              let t = float_of_int i /. float_of_int n in
              `List
                [
                  `Float (ax +. ((bx -. ax) *. t));
                  `Float (ay +. ((by -. ay) *. t));
                ])
        in
        let a = (6.8, 47.6)
        and b = (6.81, 47.6)
        and c = (6.81, 47.61)
        and d = (6.8, 47.61) in
        let ring =
          `List
            (List.concat [side a b; side b c; side c d; side d a]
            @ [`List [`Float 6.8; `Float 47.6]])
        in
        match pack_of_synthetic [feature (multi ring)] with
        | Ok p ->
            Alcotest.(check (list (list int)))
              "the 4 corners" [[4]]
              (List.concat_map
                 (fun (c : Communes.commune) ->
                   List.map (List.map Array.length) c.polygons)
                 p.communes);
            let big : Communes.pack =
              {
                p with
                communes =
                  List.map
                    (fun (c : Communes.commune) ->
                      {
                        c with
                        polygons =
                          [
                            [
                              (* On the 1e-5 grid, as decoded. *)
                              Array.init 100_000 (fun i ->
                                  ( float_of_int (680_000 + i) /. 1e5,
                                    float_of_int (4_760_000 + (i mod 2)) /. 1e5
                                  ));
                            ];
                          ];
                      })
                    p.communes;
              }
            in
            Alcotest.(check pack_result)
              "a stored ring of 100 000 vertices round-trips" (Ok big)
              (Communes.of_string (Communes.to_string big))
        | Error e ->
            Alcotest.failf "expected Ok, got %s" (Geocode.error_to_string e) );
    ( "departements: a blank or a 201-byte name is skipped, a padded one trimmed",
      `Quick,
      fun () ->
        let dep code name =
          `Assoc
            [
              ("type", `String "Feature");
              ( "properties",
                `Assoc
                  [("code_insee", `String code); ("nom_officiel", `String name)]
              );
            ]
        in
        Alcotest.(check departements_result)
          "only 03"
          (Ok [{code = code "03"; name = "Allier"}])
          (Communes.departements
             (collection
                [
                  dep "01" "   ";
                  dep "02" (String.make 201 'a');
                  dep "03" " Allier ";
                ])) );
  ]

let pack_of_payload_tests =
  [
    ("features not an array is Unexpected", `Quick, pack_of_payload_not_an_array);
    ( "a feature with another geometry type is skipped",
      `Quick,
      pack_of_payload_skips_a_bad_feature );
    ( "90: Ok, 101 communes sorted by insee, first Andelnans; every ring valid \
       and on the grid; fewer vertices than the raw payload",
      `Quick,
      pack_of_payload_ok );
    ( "a tampered numberMatched (truncated page) is Unexpected",
      `Quick,
      pack_of_payload_truncated );
    ( "an empty collection (unknown code) is Unexpected",
      `Quick,
      pack_of_payload_empty );
    ( "976 (Mayotte): Ok, 17 communes, departement = 976, names non-blank, \
       round trip",
      `Quick,
      pack_of_payload_976_ok );
  ]

(* ---------- simplify ---------- *)

let square_ring ~half : Communes.ring =
  [|(-.half, -.half); (half, -.half); (half, half); (-.half, half)|]

(* A side with [n] extra collinear points between two corners. *)
let collinear_side (ax, ay) (bx, by) n =
  List.init n (fun i ->
      let t = float_of_int (i + 1) /. float_of_int (n + 1) in
      (ax +. ((bx -. ax) *. t), ay +. ((by -. ay) *. t)))

let dense_square_ring ~half ~per_side : Communes.ring =
  let c0 = (-.half, -.half)
  and c1 = (half, -.half)
  and c2 = (half, half)
  and c3 = (-.half, half) in
  Array.of_list
    (List.concat
       [
         c0 :: collinear_side c0 c1 per_side;
         c1 :: collinear_side c1 c2 per_side;
         c2 :: collinear_side c2 c3 per_side;
         c3 :: collinear_side c3 c0 per_side;
       ])

let ring = Alcotest.(array (pair (float 0.) (float 0.)))

let simplify_tests =
  [
    ( "a plain square (4 vertices) is unchanged",
      `Quick,
      fun () ->
        let r = square_ring ~half:0.01 in
        Alcotest.check ring "same ring" r (Communes.simplify ~tolerance_m:20. r)
    );
    ( "a 1 km square with 100 collinear points per side reduces to its 4 corners",
      `Quick,
      fun () ->
        (* half = 0.005° about (0, 0): about 1.1 km of latitude per side, the
           collinear points well under tolerance_m from the sides. *)
        let r = dense_square_ring ~half:0.005 ~per_side:100 in
        Alcotest.(check int) "404 input vertices" 404 (Array.length r);
        Alcotest.check ring "the corners, first vertex first"
          (square_ring ~half:0.005)
          (Communes.simplify ~tolerance_m:20. r) );
    ( "an output of fewer than 3 vertices is replaced by the input (a tiny \
       islet)",
      `Quick,
      fun () ->
        (* Sides of about 4 m: Douglas–Peucker alone would keep 2 vertices. *)
        let islet = square_ring ~half:0.00002 in
        Alcotest.check ring "4 vertices" islet
          (Communes.simplify ~tolerance_m:20. islet);
        let pentagon : Communes.ring =
          [|
            (0., 0.);
            (0.00002, 0.);
            (0.00004, 0.00002);
            (0.00002, 0.00004);
            (0., 0.00004);
          |]
        in
        Alcotest.check ring "5 vertices" pentagon
          (Communes.simplify ~tolerance_m:20. pentagon) );
    ( "a ring with fewer than 4 vertices is returned unchanged",
      `Quick,
      fun () ->
        let triangle : Communes.ring = [|(0., 0.); (1., 0.); (0., 1.)|] in
        Alcotest.check ring "same ring" triangle
          (Communes.simplify ~tolerance_m:20. triangle) );
  ]

(* ---------- simplify's tolerance property, checked against the 90 pack's
   raw (un-simplified) rings ---------- *)

let num = function
  | `Int n -> Some (float_of_int n)
  | `Float f -> Some f
  | _ -> None

let point_of_json = function
  | `List [a; b] -> (
      match (num a, num b) with
      | Some lo, Some la -> Some (lo, la)
      | _, _ -> None)
  | _ -> None

let round5 x = Float.round (x *. 1e5) /. 1e5

let dedup_consecutive pts =
  List.rev
    (List.fold_left
       (fun acc p ->
         match acc with prev :: _ when prev = p -> acc | _ -> p :: acc)
       [] pts)

(* The same preprocessing pack_of_payload's docstring describes (closing
   vertex dropped, rounded to 1e-5, consecutive duplicates removed), done
   independently here to get the ring {!Communes.simplify} actually started
   from. *)
let raw_ring_of_json j =
  match j with
  | `List pts ->
      let pts =
        List.filter_map point_of_json pts
        |> List.map (fun (lo, la) -> (round5 lo, round5 la))
      in
      let pts =
        match (pts, List.rev pts) with
        | first :: _ :: _, last :: _ when first = last ->
            List.filteri (fun i _ -> i < List.length pts - 1) pts
        | _ -> pts
      in
      dedup_consecutive pts
  | _ -> []

(* [insee -> its raw rings], one list of rings per polygon (outer then
   holes), straight from the fixture's geometry, independent of
   {!Communes.pack_of_payload}. *)
let raw_rings_by_insee : (string * (float * float) list list list) list =
  match Lazy.force communes_90_json with
  | `Assoc kvs -> (
      match List.assoc_opt "features" kvs with
      | Some (`List feats) ->
          List.filter_map
            (fun feat ->
              match feat with
              | `Assoc fkvs -> (
                  match
                    ( List.assoc_opt "properties" fkvs,
                      List.assoc_opt "geometry" fkvs )
                  with
                  | Some (`Assoc pkvs), Some (`Assoc gkvs) -> (
                      match
                        ( List.assoc_opt "code_insee" pkvs,
                          List.assoc_opt "type" gkvs,
                          List.assoc_opt "coordinates" gkvs )
                      with
                      | ( Some (`String insee),
                          Some (`String gtype),
                          Some (`List coords) ) ->
                          let polygons =
                            match gtype with
                            | "MultiPolygon" ->
                                List.map
                                  (function
                                    | `List rings ->
                                        List.filter_map
                                          (fun r ->
                                            match raw_ring_of_json r with
                                            | [] | [_] | [_; _] -> None
                                            | full -> Some full)
                                          rings
                                    | _ -> [])
                                  coords
                            | "Polygon" ->
                                [
                                  List.filter_map
                                    (fun r ->
                                      match raw_ring_of_json r with
                                      | [] | [_] | [_; _] -> None
                                      | full -> Some full)
                                    coords;
                                ]
                            | _ -> []
                          in
                          Some (insee, polygons)
                      | _ -> None)
                  | _ -> None)
              | _ -> None)
            feats
      | _ -> [])
  | _ -> []

let deg2rad d = d *. Float.pi /. 180.
let k_m_per_deg = Float.pi *. Places.earth_radius_m /. 180.

let project ~lon0 ~lat0 (lon, lat) =
  ( (lon -. lon0) *. Float.cos (deg2rad lat0) *. k_m_per_deg,
    (lat -. lat0) *. k_m_per_deg )

let point_to_segment_dist (px, py) (ax, ay) (bx, by) =
  let abx = bx -. ax and aby = by -. ay in
  let len2 = (abx *. abx) +. (aby *. aby) in
  let proj =
    match len2 < 1e-12 with
    | true -> (ax, ay)
    | false ->
        let t = (((px -. ax) *. abx) +. ((py -. ay) *. aby)) /. len2 in
        let t = Float.max 0. (Float.min 1. t) in
        (ax +. (t *. abx), ay +. (t *. aby))
  in
  let qx, qy = proj in
  Float.sqrt (((px -. qx) *. (px -. qx)) +. ((py -. qy) *. (py -. qy)))

let dist_to_ring ~lon0 ~lat0 (ring : Communes.ring) (lon, lat) =
  let p = project ~lon0 ~lat0 (lon, lat) in
  let pts = Array.map (project ~lon0 ~lat0) ring in
  let n = Array.length pts in
  List.fold_left
    (fun best i ->
      let a = pts.(i) and b = pts.((i + 1) mod n) in
      Float.min best (point_to_segment_dist p a b))
    Float.infinity (List.init n Fun.id)

let rec is_subsequence sub full =
  match (sub, full) with
  | [], _ -> true
  | _ :: _, [] -> false
  | x :: sub', y :: full' -> (
      match x = y with
      | true -> is_subsequence sub' full'
      | false -> is_subsequence sub full')

let simplify_tolerance_on_the_90_pack () =
  let p = Lazy.force pack_90 in
  List.iter
    (fun (c : Communes.commune) ->
      match List.assoc_opt c.insee raw_rings_by_insee with
      | None -> Alcotest.failf "%s: no matching raw feature" c.insee
      | Some raw_polygons ->
          let simplified_rings = List.concat c.polygons in
          let raw_rings = List.concat raw_polygons in
          (* a feature or ring pack_of_payload dropped (too few vertices) is
             not expected on this payload; a mismatch here would mean the
             assumption below (ring i <-> ring i) does not hold. *)
          Alcotest.(check int)
            (c.insee ^ ": same number of rings")
            (List.length raw_rings)
            (List.length simplified_rings);
          List.iter2
            (fun raw simplified ->
              match simplified with
              | [||] -> Alcotest.failf "%s: empty output ring" c.insee
              | _ ->
                  (match raw with
                  | first :: _ ->
                      Alcotest.(check bool)
                        (c.insee ^ ": first vertex kept")
                        true
                        (simplified.(0) = first)
                  | [] -> Alcotest.failf "%s: empty raw ring" c.insee);
                  Alcotest.(check bool)
                    (c.insee
                    ^ ": output vertices are a subsequence of the input")
                    true
                    (is_subsequence (Array.to_list simplified) raw);
                  let lon0, lat0 = simplified.(0) in
                  List.iter
                    (fun raw_pt ->
                      let d = dist_to_ring ~lon0 ~lat0 simplified raw_pt in
                      Alcotest.(check bool)
                        (Printf.sprintf
                           "%s: input vertex within tolerance_m + 1 m of the \
                            output boundary"
                           c.insee)
                        true
                        (d <= Communes.tolerance_m +. 1.))
                    raw)
            raw_rings simplified_rings)
    p.communes

(* ---------- of_string / to_string ---------- *)

let commune_json polygons =
  Printf.sprintf "{\"insee\":\"90001\",\"name\":\"A\",\"polygons\":%s}" polygons

let stored_of ?(departement = "90") ~communes () =
  Printf.sprintf
    "{\"format\":1,\"layer\":\"x\",\"departement\":\"%s\",\"tolerance_m\":20,\"communes\":[%s]}"
    departement communes

let stored ?departement ~polygons () =
  stored_of ?departement ~communes:(commune_json polygons) ()

let of_string_to_string_tests =
  [
    ( "of_string (to_string p) = Ok p, for the 90 pack",
      `Quick,
      fun () ->
        let p = Lazy.force pack_90 in
        Alcotest.(check pack_result)
          "round trip" (Ok p)
          (Communes.of_string (Communes.to_string p)) );
    ( "of_string of non-JSON text is Not_json",
      `Quick,
      fun () ->
        match Communes.of_string "x" with
        | Error (Geocode.Not_json _) -> ()
        | Error (Geocode.Unexpected _) -> Alcotest.fail "expected Not_json"
        | Ok _ -> Alcotest.fail "expected Error" );
    ( "a future format is Unexpected {path = \"/format\"}",
      `Quick,
      fun () ->
        Alcotest.(check pack_result)
          "format 2"
          (Error (Geocode.Unexpected {path = "/format"; expected = "1"}))
          (Communes.of_string
             "{\"format\":2,\"layer\":\"x\",\"departement\":\"90\",\"tolerance_m\":20,\"communes\":[]}")
    );
    ( "a malformed ring is Unexpected at its path",
      `Quick,
      fun () ->
        let bad_ring =
          Error
            (Geocode.Unexpected
               {
                 path = "/communes/0/polygons/0/0";
                 expected = "an even list of at least 6 integers";
               })
        in
        Alcotest.(check pack_result)
          "odd length" bad_ring
          (Communes.of_string (stored ~polygons:"[[[1,2,3]]]" ()));
        Alcotest.(check pack_result)
          "fewer than 6 numbers" bad_ring
          (Communes.of_string (stored ~polygons:"[[[1,2,3,4]]]" ()));
        Alcotest.(check pack_result)
          "second ring of the second polygon of the second commune"
          (Error
             (Geocode.Unexpected
                {
                  path = "/communes/1/polygons/1/1";
                  expected = "an even list of at least 6 integers";
                }))
          (Communes.of_string
             (stored_of
                ~communes:
                  (commune_json "[[[1,2,3,4,5,6]]]"
                  ^ ","
                  ^ commune_json "[[[1,2,3,4,5,6]],[[1,2,3,4,5,6],[1,2]]]")
                ())) );
    ( "an empty communes list is Unexpected (a pack is never empty)",
      `Quick,
      fun () ->
        Alcotest.(check pack_result)
          "empty"
          (Error
             (Geocode.Unexpected
                {path = "/communes"; expected = "a non-empty array"}))
          (Communes.of_string (stored_of ~communes:"" ())) );
    ( "a departement that is not a code is Unexpected",
      `Quick,
      fun () ->
        Alcotest.(check pack_result)
          "AA"
          (Error
             (Geocode.Unexpected
                {path = "/departement"; expected = "a département code"}))
          (Communes.of_string
             (stored ~departement:"AA" ~polygons:"[[[1,2,3,4,5,6]]]" ())) );
  ]

(* ---------- index: find, name, add, remove ---------- *)

let idx_90 = lazy (Communes.add Communes.empty (Lazy.force pack_90))

let index_find_and_name () =
  let idx = Lazy.force idx_90 in
  (match Communes.find idx belfort with
  | Some c -> Alcotest.(check string) "belfort insee" "90010" c.insee
  | None -> Alcotest.fail "expected Belfort to be found");
  (match Communes.find idx giromagny with
  | Some c -> Alcotest.(check string) "giromagny insee" "90052" c.insee
  | None -> Alcotest.fail "expected Giromagny to be found");
  Alcotest.(check (option string))
    "eloie" (Near.inside "Éloie") (Communes.name idx eloie);
  Alcotest.(check (option string))
    "belfort name" (Some "À Belfort")
    (Communes.name idx belfort);
  Alcotest.(check (option string)) "landes" None (Communes.name idx landes);
  Alcotest.(check (option string)) "schlucht" None (Communes.name idx schlucht);
  Alcotest.(check (option string))
    "nan lat" None
    (Communes.name idx {Places.lat = Float.nan; lon = 7.});
  Alcotest.(check (option string))
    "infinite lon" None
    (Communes.name idx {Places.lat = 47.6380; lon = Float.infinity})

let index_remove_and_add_twice () =
  let idx = Lazy.force idx_90 in
  Alcotest.(check (list string))
    "departements_of" ["90"]
    (codes (Communes.departements_of idx));
  let removed = Communes.remove idx (code "90") in
  Alcotest.(check (list string))
    "removed" []
    (codes (Communes.departements_of removed));
  Alcotest.(check (option string))
    "belfort gone" None
    (Communes.name removed belfort);
  let twice = Communes.add idx (Lazy.force pack_90) in
  Alcotest.(check (list string))
    "adding the same department twice" ["90"]
    (codes (Communes.departements_of twice))

let insee_at idx p =
  Option.map (fun (c : Communes.commune) -> c.insee) (Communes.find idx p)

(* A new 90 pack holding Belfort only replaces the old one: Giromagny and
   Éloie are gone (an add that kept or merged the old pack would still find
   them). *)
let index_add_replaces () =
  let p = Lazy.force pack_90 in
  let belfort_only =
    {
      p with
      communes =
        List.filter
          (fun (c : Communes.commune) -> String.equal c.insee "90010")
          p.communes;
    }
  in
  let idx = Communes.add (Lazy.force idx_90) belfort_only in
  Alcotest.(check (list string))
    "one 90 pack" ["90"]
    (codes (Communes.departements_of idx));
  Alcotest.(check (option string))
    "belfort" (Some "90010") (insee_at idx belfort);
  Alcotest.(check (option string))
    "giromagny gone" None (insee_at idx giromagny);
  Alcotest.(check (option string)) "eloie gone" None (insee_at idx eloie)

let index_order_and_absent_remove () =
  let corse : Communes.pack =
    {
      departement = code "2A";
      communes =
        [
          {
            insee = "2A004";
            name = "Ajaccio";
            polygons = [[[|(8.7, 41.9); (8.8, 41.9); (8.8, 42.)|]]];
          };
        ];
    }
  in
  let idx = Communes.add (Lazy.force idx_90) corse in
  Alcotest.(check (list string))
    "sorted" ["2A"; "90"]
    (codes (Communes.departements_of idx));
  Alcotest.(check (list string))
    "an absent code changes nothing" ["90"]
    (codes
       (Communes.departements_of
          (Communes.remove (Lazy.force idx_90) (code "68"))))

(* 976 (Mayotte): an overseas pack is named exactly like a
   metropolitan one; the offline lookup is not limited to a France box. *)
let index_976_name () =
  let idx = Communes.add Communes.empty (Lazy.force pack_976) in
  Alcotest.(check (option string))
    "Mamoudzou" (Some "À Mamoudzou")
    (Communes.name idx mamoudzou);
  Alcotest.(check (option string))
    "open sea east of Mayotte" None
    (Communes.name idx mayotte_open_sea)

(* M8.85: a pack polygon contains the point, so the commune is « À … ». *)
let index_46_name () =
  let idx = Communes.add Communes.empty (Lazy.force pack_46) in
  Alcotest.(check (option string))
    "Figeac" (Some "À Figeac") (Communes.name idx figeac);
  Alcotest.(check (option string))
    "Pélégri" (Some "À Lissac-et-Mouret")
    (Communes.name idx pelegri)

let index_tests =
  [
    ( "name on the 46 pack: À Figeac, À Lissac-et-Mouret (M8.85)",
      `Quick,
      index_46_name );
    ( "find and name on the 90 pack: Belfort, Giromagny, Éloie, outside, nan",
      `Quick,
      index_find_and_name );
    ( "remove drops the department; adding twice keeps one pack",
      `Quick,
      index_remove_and_add_twice );
    ("add replaces the pack of the same département", `Quick, index_add_replaces);
    ( "departements_of is sorted; removing an absent code changes nothing",
      `Quick,
      index_order_and_absent_remove );
    ( "976 (Mayotte): named at Mamoudzou, None at the open sea east of it",
      `Quick,
      index_976_name );
  ]

(* ---------- holes and edges, on synthetic squares ---------- *)

let lat0 = 45.0
let lon0 = 5.0
let m_per_deg_lat = Float.pi *. Places.earth_radius_m /. 180.
let dlat m = m /. m_per_deg_lat
let dlon m = m /. (m_per_deg_lat *. Float.cos (deg2rad lat0))

(* A point [dx] metres east and [dy] metres north of (cx, cy), itself [cx]
   metres east and [cy] metres north of the base point. *)
let pt ~cx ~cy ~dx ~dy : Places.point =
  {lat = lat0 +. dlat (cy +. dy); lon = lon0 +. dlon (cx +. dx)}

let square_lonlat ~cx ~cy ~half : Communes.ring =
  [|
    (lon0 +. dlon (cx -. half), lat0 +. dlat (cy -. half));
    (lon0 +. dlon (cx +. half), lat0 +. dlat (cy -. half));
    (lon0 +. dlon (cx +. half), lat0 +. dlat (cy +. half));
    (lon0 +. dlon (cx -. half), lat0 +. dlat (cy +. half));
  |]

(* "Trou": an outer 1000 m square around (5000, 5000) with a 200 m hole at
   its centre. *)
let trou : Communes.commune =
  {
    insee = "AA001";
    name = "Trou";
    polygons =
      [
        [
          square_lonlat ~cx:5000. ~cy:5000. ~half:500.;
          square_lonlat ~cx:5000. ~cy:5000. ~half:100.;
        ];
      ];
  }

(* Two adjacent 1000 x 1000 m squares sharing the edge x = 10500 (in the
   (cx, cy) = (10000, 0) frame): "Ouest" spans x in [9500, 10500], "Est"
   spans [10500, 11500]. *)
let ouest : Communes.commune =
  {
    insee = "AA002";
    name = "Ouest";
    polygons = [[square_lonlat ~cx:10000. ~cy:0. ~half:500.]];
  }

let est : Communes.commune =
  {
    insee = "AA003";
    name = "Est";
    polygons = [[square_lonlat ~cx:11000. ~cy:0. ~half:500.]];
  }

let synthetic_pack : Communes.pack =
  {departement = code "01"; communes = [trou; ouest; est]}

let synthetic_idx = lazy (Communes.add Communes.empty synthetic_pack)

let holes_and_edges_tests =
  [
    ( "a point in the hole is None (beyond edge_m from both rings)",
      `Quick,
      fun () ->
        let idx = Lazy.force synthetic_idx in
        let centre = pt ~cx:5000. ~cy:5000. ~dx:0. ~dy:0. in
        Alcotest.(check (option string))
          "hole centre" None
          (Communes.find idx centre
          |> Option.map (fun (c : Communes.commune) -> c.insee)) );
    ( "a point between the hole and the outer ring is found",
      `Quick,
      fun () ->
        let idx = Lazy.force synthetic_idx in
        let between = pt ~cx:5000. ~cy:5000. ~dx:300. ~dy:0. in
        Alcotest.(check (option string))
          "between" (Some "AA001")
          (Communes.find idx between
          |> Option.map (fun (c : Communes.commune) -> c.insee)) );
    ( "two adjacent squares: a point inside each resolves to its own",
      `Quick,
      fun () ->
        let idx = Lazy.force synthetic_idx in
        let inside_ouest = pt ~cx:10000. ~cy:0. ~dx:200. ~dy:0. in
        let inside_est = pt ~cx:11000. ~cy:0. ~dx:200. ~dy:0. in
        Alcotest.(check (option string))
          "ouest" (Some "AA002")
          (Communes.find idx inside_ouest
          |> Option.map (fun (c : Communes.commune) -> c.insee));
        Alcotest.(check (option string))
          "est" (Some "AA003")
          (Communes.find idx inside_est
          |> Option.map (fun (c : Communes.commune) -> c.insee)) );
    ( "a vertex shared by both squares resolves to one of them, no exception",
      `Quick,
      fun () ->
        let idx = Lazy.force synthetic_idx in
        let vertex = pt ~cx:10500. ~cy:0. ~dx:0. ~dy:500. in
        match Communes.find idx vertex with
        | Some c when c.insee = "AA002" || c.insee = "AA003" -> ()
        | Some c -> Alcotest.failf "unexpected commune %s" c.insee
        | None -> Alcotest.fail "expected one of the two communes" );
    ( "a point on the shared edge counts for one side only (Est)",
      `Quick,
      fun () ->
        (* Half-open ray casting towards +lon: no crossing for Ouest, one for
           Est. Counted for both, Ouest (first) would win; for neither, the
           nearest at 0 m would be Ouest too. *)
        let idx = Lazy.force synthetic_idx in
        Alcotest.(check (option string))
          "edge midpoint" (Some "AA003")
          (insee_at idx (pt ~cx:10500. ~cy:0. ~dx:0. ~dy:0.)) );
    ( "49 m outside is still named, 51 m is not (edge_m = 50)",
      `Quick,
      fun () ->
        let idx = Lazy.force synthetic_idx in
        Alcotest.(check (option string))
          "49 m" (Some "AA002")
          (insee_at idx (pt ~cx:10000. ~cy:0. ~dx:(-549.) ~dy:0.));
        Alcotest.(check (option string))
          "51 m" None
          (insee_at idx (pt ~cx:10000. ~cy:0. ~dx:(-551.) ~dy:0.)) );
    ( "between two communes outside both, the nearer one wins",
      `Quick,
      fun () ->
        (* Two 1000 m squares 40 m apart: x in [19500, 20500] and
           [20540, 21540]. *)
        let gauche : Communes.commune =
          {
            insee = "AA004";
            name = "Gauche";
            polygons = [[square_lonlat ~cx:20000. ~cy:0. ~half:500.]];
          }
        and droite : Communes.commune =
          {
            insee = "AA005";
            name = "Droite";
            polygons = [[square_lonlat ~cx:21040. ~cy:0. ~half:500.]];
          }
        in
        let idx =
          Communes.add Communes.empty
            {departement = code "02"; communes = [gauche; droite]}
        in
        Alcotest.(check (option string))
          "15 m from Gauche, 25 m from Droite" (Some "AA004")
          (insee_at idx (pt ~cx:20500. ~cy:0. ~dx:15. ~dy:0.));
        Alcotest.(check (option string))
          "25 m from Gauche, 15 m from Droite" (Some "AA005")
          (insee_at idx (pt ~cx:20500. ~cy:0. ~dx:25. ~dy:0.)) );
    ( "30 m outside the outer edge is the nearest commune (within edge_m)",
      `Quick,
      fun () ->
        let idx = Lazy.force synthetic_idx in
        let just_outside = pt ~cx:10000. ~cy:0. ~dx:(-530.) ~dy:0. in
        Alcotest.(check (option string))
          "30 m outside" (Some "AA002")
          (Communes.find idx just_outside
          |> Option.map (fun (c : Communes.commune) -> c.insee)) );
    ( "inside a polygon is « À », within edge_m outside it « Près de » (M8.85)",
      `Quick,
      fun () ->
        let idx = Lazy.force synthetic_idx in
        Alcotest.(check (option string))
          "inside Ouest" (Some "À Ouest")
          (Communes.name idx (pt ~cx:10000. ~cy:0. ~dx:0. ~dy:0.));
        Alcotest.(check (option string))
          "30 m outside Ouest" (Some "Près d’Ouest")
          (Communes.name idx (pt ~cx:10000. ~cy:0. ~dx:(-530.) ~dy:0.)) );
    ( "80 m outside the outer edge is None (beyond edge_m)",
      `Quick,
      fun () ->
        let idx = Lazy.force synthetic_idx in
        let far_outside = pt ~cx:10000. ~cy:0. ~dx:(-580.) ~dy:0. in
        Alcotest.(check (option string))
          "80 m outside" None
          (Communes.find idx far_outside
          |> Option.map (fun (c : Communes.commune) -> c.insee)) );
  ]

let () =
  Alcotest.run "communes"
    [
      ("Code", valid_code_tests);
      ("request URLs", url_tests);
      ("fixture script", fixture_script_tests);
      ("departements", departements_tests);
      ("available", available_tests);
      ("pack_of_payload", pack_of_payload_tests);
      ("synthetic payloads", synthetic_payload_tests);
      ("simplify", simplify_tests);
      ( "simplify's tolerance property",
        [
          ( "every input vertex stays within tolerance_m + 1 m of the 90 \
             pack's output",
            `Quick,
            simplify_tolerance_on_the_90_pack );
        ] );
      ("of_string / to_string", of_string_to_string_tests);
      ("index", index_tests);
      ("holes and edges", holes_and_edges_tests);
    ]
