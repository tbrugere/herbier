(* Map_filter, Map_sheet *)

module Map_filter = Herbier_ui_model.Map_filter
module Map_sheet = Herbier_ui_model.Map_sheet
module Plant_id = Herbier_domain.Ids.Plant_id
module Ids = Herbier_domain.Ids
module Places = Herbier_domain.Places
module Photo = Herbier_domain.Photo

let utc = Fixtures.utc
let obs = Fixtures.map_obs

let cluster_of members : Places.cluster =
  {centroid = {lat = 0.; lon = 0.}; members}

let map_filter_place_name () =
  let str = Alcotest.(option string) in
  Alcotest.check str "Named gives its label" (Some "Jardin")
    (Map_filter.place_name (cluster_of [obs ~label:"Jardin" ()]));
  Alcotest.check str "Derived (no Named) gives the derived label"
    (Some "Près de Y")
    (Map_filter.place_name (cluster_of [obs ~derived:"Près de Y" ()]));
  Alcotest.check str "Coordinates gives None" None
    (Map_filter.place_name (cluster_of [obs ~pos:(48.1, 7.2) ()]));
  Alcotest.check str "no label, no position gives None" None
    (Map_filter.place_name (cluster_of [obs ()]))

let map_filter_false_whatever_the_query () =
  let p = Plant_id.fresh () in
  let o = obs ~plant:p () in
  let c = cluster_of [o] in
  let filter (_ : Herbier_domain.Observation.t) = false in
  List.iter
    (fun (name, query) ->
      Alcotest.(check bool) name false (Map_filter.keep ~filter query c o))
    [
      ("Everything, filter false", Map_filter.Everything);
      ( "Matching accepting everything, filter false",
        Map_filter.Matching
          {plants = [p]; place = (fun (_ : Places.cluster) -> true)} );
    ]

let map_filter_everything_is_filter () =
  let o1 = obs ~plant:(Plant_id.fresh ()) () and o2 = obs () in
  let c = cluster_of [o1; o2] in
  List.iter
    (fun (name, filter) ->
      Alcotest.(check bool)
        (name ^ ": o1") (filter o1)
        (Map_filter.keep ~filter Map_filter.Everything c o1);
      Alcotest.(check bool)
        (name ^ ": o2") (filter o2)
        (Map_filter.keep ~filter Map_filter.Everything c o2))
    [
      ("always true", fun (_ : Herbier_domain.Observation.t) -> true);
      ("always false", fun (_ : Herbier_domain.Observation.t) -> false);
    ]

let map_filter_matching_by_plant () =
  let p = Plant_id.fresh () and q = Plant_id.fresh () in
  let of_p = obs ~plant:p ()
  and of_q = obs ~plant:q ()
  and unidentified = obs () in
  let c = cluster_of [of_p; of_q; unidentified] in
  let query =
    Map_filter.Matching
      {plants = [p]; place = (fun (_ : Places.cluster) -> false)}
  in
  let filter (_ : Herbier_domain.Observation.t) = true in
  Alcotest.(check bool)
    "an observation of the matching plant passes" true
    (Map_filter.keep ~filter query c of_p);
  Alcotest.(check bool)
    "an observation of another plant does not" false
    (Map_filter.keep ~filter query c of_q);
  Alcotest.(check bool)
    "an unidentified observation does not pass through plants" false
    (Map_filter.keep ~filter query c unidentified)

let map_filter_matching_by_place_only () =
  let identified = obs ~plant:(Plant_id.fresh ()) () in
  let unidentified = obs () in
  let c = cluster_of [identified; unidentified] in
  let query =
    Map_filter.Matching
      {plants = []; place = (fun (_ : Places.cluster) -> true)}
  in
  Alcotest.(check bool)
    "an identified observation passes through place" true
    (Map_filter.keep ~filter:(fun _ -> true) query c identified);
  Alcotest.(check bool)
    "an unidentified observation passes through place too" true
    (Map_filter.keep ~filter:(fun _ -> true) query c unidentified);
  Alcotest.(check bool)
    "filter still gates it" false
    (Map_filter.keep ~filter:(fun _ -> false) query c identified)

let map_filter_place_matched_once_per_cluster () =
  let members = List.init 5 (fun _ -> obs ()) in
  let c = cluster_of members in
  let calls = ref 0 in
  let query =
    Map_filter.Matching
      {
        plants = [];
        place =
          (fun (_ : Places.cluster) ->
            incr calls;
            true);
      }
  in
  let keep = Map_filter.keep ~filter:(fun _ -> true) query c in
  Alcotest.(check (list bool))
    "every member passes through place"
    [true; true; true; true; true]
    (List.map keep members);
  Alcotest.(check int) "place is called once for the cluster" 1 !calls

let map_filter =
  [
    Alcotest.test_case "place_name" `Quick map_filter_place_name;
    Alcotest.test_case "keep with filter always false" `Quick
      map_filter_false_whatever_the_query;
    Alcotest.test_case "keep Everything is exactly filter" `Quick
      map_filter_everything_is_filter;
    Alcotest.test_case "keep Matching by plants" `Quick
      map_filter_matching_by_plant;
    Alcotest.test_case "keep Matching by place only (plants = [])" `Quick
      map_filter_matching_by_place_only;
    Alcotest.test_case "keep matches the place once per cluster" `Quick
      map_filter_place_matched_once_per_cluster;
  ]

let map_sheet_snaps () =
  let float_list = Alcotest.(list (float 1e-9)) in
  List.iter
    (fun (name, available, top, expected) ->
      Alcotest.check float_list name expected (Map_sheet.snaps ~available ~top))
    [
      ("available 800, top 104", 800., 104., [64.; 360.; 660.]);
      ("available 500, top 104", 500., 104., [64.; 250.; 360.]);
      (* A taller top (safe-area inset) lowers only the highest point. *)
      ("available 800, top 152", 800., 152., [64.; 360.; 612.]);
      ("top nan is 0", 800., Float.nan, [64.; 360.; 764.]);
      ("high = mid + 1, mid not raised", 200., 104., [64.; 100.; 101.]);
      ("available 100: mid raised to 65", 100., 104., [64.; 65.; 66.]);
      ("available 0", 0., 104., [64.; 65.; 66.]);
      ("available negative", -50., 104., [64.; 65.; 66.]);
      ("available nan", Float.nan, 104., [64.; 65.; 66.]);
    ]

let map_sheet_summary () =
  let str = Alcotest.string in
  let p1 = Plant_id.fresh ()
  and p2 = Plant_id.fresh ()
  and p3 = Plant_id.fresh ()
  and p4 = Plant_id.fresh () in
  Alcotest.check str "6 observations, 4 distinct plants"
    "rayon 500 m · 6 observations · 4 plantes"
    (Map_sheet.summary
       [
         obs ~plant:p1 ();
         obs ~plant:p1 ();
         obs ~plant:p2 ();
         obs ~plant:p3 ();
         obs ~plant:p4 ();
         obs ~plant:p4 ();
       ]);
  Alcotest.check str "1 observation, 1 plant"
    "rayon 500 m · 1 observation · 1 plante"
    (Map_sheet.summary [obs ~plant:p1 ()]);
  Alcotest.check str "2 unidentified observations"
    "rayon 500 m · 2 observations"
    (Map_sheet.summary [obs (); obs ()]);
  Alcotest.check str "two observations of the same plant: 1 plante"
    "rayon 500 m · 2 observations · 1 plante"
    (Map_sheet.summary [obs ~plant:p1 (); obs ~plant:p1 ()])

let map_sheet_collapsed () =
  let str = Alcotest.string in
  Alcotest.check str "3 places, 13 observations" "3 lieux · 13 observations"
    (Map_sheet.collapsed ~places:3 ~observations:13);
  Alcotest.check str "1 place, 1 observation" "1 lieu · 1 observation"
    (Map_sheet.collapsed ~places:1 ~observations:1);
  Alcotest.check str "no places" "Aucune observation sur la carte"
    (Map_sheet.collapsed ~places:0 ~observations:0)

let map_sheet_title () =
  let str = Alcotest.string in
  Alcotest.check str "majority place_label" "Col"
    (Map_sheet.title
       (cluster_of
          [obs ~label:"Col" (); obs ~label:"Col" (); obs ~label:"Lac" ()]));
  Alcotest.check str "derived only" "Près de Y"
    (Map_sheet.title (cluster_of [obs ~derived:"Près de Y" ()]));
  let positioned = cluster_of [obs ~pos:(48.1, 7.2) ()] in
  Alcotest.check str "neither label nor derived, but positioned: Lieu inconnu"
    "Lieu inconnu"
    (Map_sheet.title positioned);
  Alcotest.check str "no label and no position falls back to \"Lieu\"" "Lieu"
    (Map_sheet.title (cluster_of [obs ()]))

let map_sheet_rename_value () =
  let str = Alcotest.string in
  Alcotest.check str "Named gives the label" "Jardin"
    (Map_sheet.rename_value (cluster_of [obs ~label:"Jardin" ()]));
  Alcotest.check str "Derived only gives the empty string" ""
    (Map_sheet.rename_value (cluster_of [obs ~derived:"Près de Y" ()]))

let photo_id n =
  match
    Ids.Photo_id.of_string (Printf.sprintf "00000000-0000-4000-8000-%012d" n)
  with
  | Some id -> id
  | None -> Alcotest.failf "Photo_id.of_string of test id %d gave None" n

let photo ~id ~observation_id ~taken_at : Photo.t =
  {
    id = photo_id id;
    observation_id;
    taken_at;
    width = 100;
    height = 100;
    sha256 = String.make 64 '0';
    preview_path = "previews/x.jpg";
    preview_bucket_key = None;
    original_target = Photo.Original_target.App_only;
    drive_file_id = None;
    upload_state = Photo.Upload_state.Uploaded;
    created_at = taken_at;
    updated_at = taken_at;
    deleted_at = None;
  }

let map_sheet_photos_by_observation () =
  let o1 = obs () and o2 = obs () in
  let t1 = utc 2026 6 12 9 0 and t2 = utc 2026 6 12 10 0 in
  (* p_a, p_b: same taken_at for o1, so the tie must break by id. *)
  let p_a = photo ~id:2 ~observation_id:o1.id ~taken_at:t2 in
  let p_b = photo ~id:1 ~observation_id:o1.id ~taken_at:t2 in
  let p_early = photo ~id:3 ~observation_id:o1.id ~taken_at:t1 in
  let p_o2 = photo ~id:4 ~observation_id:o2.id ~taken_at:t1 in
  let photo_strs =
    List.map (fun (p : Photo.t) -> Ids.Photo_id.to_string p.id)
  in
  (* Given in [Photos.live] order: taken_at descending. *)
  let index = Map_sheet.photos_by_observation [p_a; p_b; p_early; p_o2] in
  Alcotest.(check (list string))
    "o1's photos ascending by taken_at, tie broken by id"
    (photo_strs [p_early; p_b; p_a])
    (photo_strs (index o1.id));
  Alcotest.(check (list string))
    "o2's single photo" (photo_strs [p_o2])
    (photo_strs (index o2.id));
  Alcotest.(check (list string))
    "an observation with no photo gives []" []
    (photo_strs (index (Ids.Observation_id.fresh ())))

let map_sheet_row_meta () =
  let str = Alcotest.string in
  Alcotest.check str "this year, 2 photos" "12 juin · 2 photos"
    (Map_sheet.row_meta ~this_year:2026 ~date:(2026, 6, 12) ~photos:2);
  Alcotest.check str "this year, 1 photo" "12 juin · 1 photo"
    (Map_sheet.row_meta ~this_year:2026 ~date:(2026, 6, 12) ~photos:1);
  Alcotest.check str "this year, 0 photos" "12 juin"
    (Map_sheet.row_meta ~this_year:2026 ~date:(2026, 6, 12) ~photos:0);
  Alcotest.check str "another year, 1 photo" "3 décembre 2025 · 1 photo"
    (Map_sheet.row_meta ~this_year:2026 ~date:(2025, 12, 3) ~photos:1)

let map_sheet_notices () =
  let str = Alcotest.string in
  List.iter
    (fun (n, expected) ->
      Alcotest.check str expected expected (Map_sheet.notice_text n))
    [
      (Map_sheet.Loading, "Chargement…");
      (Read_failed, "Lecture impossible");
      (Search_failed, "Recherche impossible");
      (Position_unavailable, "Position indisponible");
      (Location_denied, "Localisation non autorisée");
      (Location_off, "Localisation désactivée");
    ];
  Alcotest.check str "missing tokens" "Jetons absents : --map-point, --paper"
    (Map_sheet.broken_text (Missing_tokens ["--map-point"; "--paper"]));
  Alcotest.check str "map unavailable" "Carte indisponible"
    (Map_sheet.broken_text Map_unavailable);
  List.iter
    (fun (code, expected) ->
      Alcotest.check str
        (Option.value code ~default:"no code")
        (Map_sheet.notice_text expected)
        (Map_sheet.notice_text (Map_sheet.position_failure code)))
    [
      (Some "OS-PLUG-GLOC-0003", Map_sheet.Location_denied);
      (Some "OS-PLUG-GLOC-0007", Location_off);
      (Some "OS-PLUG-GLOC-0017", Location_off);
      (Some "OS-PLUG-GLOC-0010", Position_unavailable);
      (Some "UNAVAILABLE", Position_unavailable);
      (None, Position_unavailable);
    ]

let map_sheet =
  [
    Alcotest.test_case "snaps: exact heights" `Quick map_sheet_snaps;
    Alcotest.test_case "notice, broken and position texts" `Quick
      map_sheet_notices;
    Alcotest.test_case "summary" `Quick map_sheet_summary;
    Alcotest.test_case "collapsed" `Quick map_sheet_collapsed;
    Alcotest.test_case "title" `Quick map_sheet_title;
    Alcotest.test_case "rename_value" `Quick map_sheet_rename_value;
    Alcotest.test_case "photos_by_observation" `Quick
      map_sheet_photos_by_observation;
    Alcotest.test_case "row_meta" `Quick map_sheet_row_meta;
  ]
