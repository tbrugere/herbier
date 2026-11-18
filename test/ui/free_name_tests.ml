(* Herbier_ui_model.Free_name (4g's reference block of a free-name
   plant, 6k): labels, the observation sent, the Identifier button's gate and
   line, and what a chosen proposal writes (link). Pure; no DOM, no network.
   Proposals are decoded from the recorded
   plantnet_identify_one_auto_200.json fixture, reused by identify_choice_tests
   and to_identify_tests. *)

module Free_name = Herbier_ui_model.Free_name
module Identify = Herbier_ui_model.Identify
module Choice = Identify.Choice
module Is = Herbier_ui_model.Identify_settings
module Plant_link = Herbier_ui_model.Plant_link
module Plantnet = Herbier_identify.Plantnet
module Gbif = Herbier_refs.Sources.Gbif
module Plant = Herbier_domain.Plant
module Plant_id = Herbier_domain.Ids.Plant_id
module Observation = Herbier_domain.Observation
module Observation_id = Herbier_domain.Ids.Observation_id
module Photo = Herbier_domain.Photo
module Photo_id = Herbier_domain.Ids.Photo_id
module Fixture = Herbier_test_support.Fixture
module Support_text = Herbier_test_support.Text

let utc = Fixtures.utc

(* ---------- testables ---------- *)

let link_t = Alcotest.testable Free_name.pp_link Free_name.equal_link

let pp_sent fmt (s : Free_name.sent) =
  Format.fprintf fmt "{observation = %s; photos = [%s]}"
    (Observation_id.to_string s.observation.id)
    (String.concat "; "
       (List.map (fun (p : Photo.t) -> Photo_id.to_string p.id) s.photos))

let sent_t = Alcotest.testable pp_sent Free_name.equal_sent
let sent_opt_t = Alcotest.option sent_t

let observation_id_t =
  Alcotest.testable
    (fun fmt id -> Format.pp_print_string fmt (Observation_id.to_string id))
    Observation_id.equal

let photo_id_strings ps =
  List.map (fun (p : Photo.t) -> Photo_id.to_string p.id) ps

(* ---------- helpers ---------- *)

let ready_key () =
  match Is.Key.of_input "abcdefgh" with
  | Some k -> k
  | None -> Alcotest.fail "Key.of_input \"abcdefgh\" should be a key"

let mk_obs ?(id = Observation_id.fresh ()) ?(deleted_at = None) at :
    Observation.t =
  {
    id;
    plant_id = None;
    at;
    position = None;
    place_label = None;
    place_derived = None;
    note = None;
    created_at = at;
    updated_at = at;
    deleted_at;
  }

let mk_photo ?(id = Photo_id.fresh ()) ?(deleted_at = None) ~observation_id
    taken_at : Photo.t =
  {
    id;
    observation_id;
    taken_at;
    width = 1;
    height = 1;
    sha256 = "";
    preview_path = "";
    preview_bucket_key = None;
    original_target = Photo.Original_target.App_only;
    drive_file_id = None;
    upload_state = Photo.Upload_state.Uploaded;
    created_at = taken_at;
    updated_at = taken_at;
    deleted_at;
  }

(* The fixture's first proposal: Hibiscus rosa-sinensis L., gbif 3152559,
   common names "Rose de Chine", "Hibiscus", "Hibiscus rose de Chine". *)
let decode name =
  match Plantnet.decode_answer (Fixture.read name) with
  | Ok a -> a
  | Error e -> Alcotest.failf "decode %s: %s" name (Plantnet.error_to_string e)

let answer = lazy (decode "plantnet_identify_one_auto_200.json")

let nth n =
  match List.nth_opt (Lazy.force answer).proposals n with
  | Some p -> p
  | None ->
      Alcotest.failf "plantnet_identify_one_auto_200.json has no proposal %d" n

let p0 = lazy (nth 0)

let plantnet_taxon_of p =
  match Choice.plantnet_taxon p with
  | Some t -> t
  | None -> Alcotest.fail "plantnet_taxon: expected Some"

(* ============================================================ *)
(* labels *)
(* ============================================================ *)

let label_tests () =
  Alcotest.(check string) "identify_label" "Identifier" Free_name.identify_label;
  Alcotest.(check string)
    "search_label" "Chercher un nom" Free_name.search_label

(* ============================================================ *)
(* sent: which observation, which photos *)
(* ============================================================ *)

let sent_empty_tests () =
  Alcotest.(check sent_opt_t)
    "no observations, no photos -> None" None
    (Free_name.sent ~observations:[] ~photos:[]);
  let o = mk_obs (utc 2026 1 1 0 0) in
  Alcotest.(check sent_opt_t)
    "an observation without any photo -> None" None
    (Free_name.sent ~observations:[o] ~photos:[])

let sent_picks_the_one_with_photos () =
  let older = mk_obs (utc 2026 1 1 0 0) in
  let newer_without_photo = mk_obs (utc 2026 2 1 0 0) in
  let p1 = mk_photo ~observation_id:older.id (utc 2026 1 1 1 0) in
  let p2 = mk_photo ~observation_id:older.id (utc 2026 1 1 2 0) in
  match
    Free_name.sent ~observations:[older; newer_without_photo] ~photos:[p1; p2]
  with
  | Some s ->
      Alcotest.(check observation_id_t)
        "the older observation, the only one with photos" older.id
        s.observation.id;
      Alcotest.(check (list string))
        "both its photos"
        [Photo_id.to_string p1.id; Photo_id.to_string p2.id]
        (photo_id_strings s.photos)
  | None -> Alcotest.fail "expected Some"

let sent_newest_with_photos_wins_whatever_order () =
  let older = mk_obs (utc 2026 1 1 0 0) in
  let newer = mk_obs (utc 2026 3 1 0 0) in
  let po = mk_photo ~observation_id:older.id (utc 2026 1 1 1 0) in
  let pn = mk_photo ~observation_id:newer.id (utc 2026 3 1 1 0) in
  List.iter
    (fun (label, observations, photos) ->
      Alcotest.(check sent_opt_t)
        (label ^ ": the newer observation wins, with its photo only")
        (Some Free_name.{observation = newer; photos = [pn]})
        (Free_name.sent ~observations ~photos))
    [
      ("in order", [older; newer], [po; pn]);
      ("observations reversed", [newer; older], [po; pn]);
      ("photos reversed", [older; newer], [pn; po]);
      ("both reversed", [newer; older], [pn; po]);
    ]

let sent_skips_soft_deleted () =
  let deleted =
    mk_obs ~deleted_at:(Some (utc 2026 5 1 0 0)) (utc 2026 4 1 0 0)
  in
  let live = mk_obs (utc 2026 1 1 0 0) in
  let pd = mk_photo ~observation_id:deleted.id (utc 2026 4 1 1 0) in
  let pl = mk_photo ~observation_id:live.id (utc 2026 1 1 1 0) in
  Alcotest.(check sent_opt_t)
    "the live observation and its photo, not the newer soft-deleted one"
    (Some Free_name.{observation = live; photos = [pl]})
    (Free_name.sent ~observations:[deleted; live] ~photos:[pd; pl]);
  Alcotest.(check sent_opt_t)
    "only a soft-deleted observation has photos -> None" None
    (Free_name.sent ~observations:[deleted] ~photos:[pd])

let sent_skips_soft_deleted_photos () =
  let obs = mk_obs (utc 2026 1 1 0 0) in
  let gone =
    mk_photo
      ~deleted_at:(Some (utc 2026 1 2 0 0))
      ~observation_id:obs.id (utc 2026 1 1 1 0)
  in
  let kept = mk_photo ~observation_id:obs.id (utc 2026 1 1 2 0) in
  Alcotest.(check sent_opt_t)
    "a soft-deleted photo is not sent"
    (Some Free_name.{observation = obs; photos = [kept]})
    (Free_name.sent ~observations:[obs] ~photos:[gone; kept]);
  Alcotest.(check sent_opt_t)
    "an observation whose only photo is soft-deleted -> None" None
    (Free_name.sent ~observations:[obs] ~photos:[gone])

let sent_tie_greater_id_wins () =
  let at = utc 2026 1 1 0 0 in
  let a = Observation_id.fresh () and b = Observation_id.fresh () in
  let greater, lesser =
    if Observation_id.compare a b > 0 then (a, b) else (b, a)
  in
  let o_greater = mk_obs ~id:greater at in
  let o_lesser = mk_obs ~id:lesser at in
  let p_greater = mk_photo ~observation_id:greater (utc 2026 1 1 1 0) in
  let p_lesser = mk_photo ~observation_id:lesser (utc 2026 1 1 1 0) in
  match
    Free_name.sent ~observations:[o_lesser; o_greater]
      ~photos:[p_lesser; p_greater]
  with
  | Some s ->
      Alcotest.(check observation_id_t)
        "equal at: the greater observation id wins" greater s.observation.id
  | None -> Alcotest.fail "expected Some"

let sent_orders_photos_and_truncates () =
  let obs = mk_obs (utc 2026 1 1 0 0) in
  let id1 = Photo_id.fresh () and id2 = Photo_id.fresh () in
  let tie_lo, tie_hi =
    if Photo_id.compare id1 id2 < 0 then (id1, id2) else (id2, id1)
  in
  let tied_at = utc 2026 1 1 1 0 in
  let earliest = mk_photo ~observation_id:obs.id (utc 2026 1 1 0 30) in
  let tied_hi = mk_photo ~observation_id:obs.id ~id:tie_hi tied_at in
  let tied_lo = mk_photo ~observation_id:obs.id ~id:tie_lo tied_at in
  let p2 = mk_photo ~observation_id:obs.id (utc 2026 1 1 2 0) in
  let p3 = mk_photo ~observation_id:obs.id (utc 2026 1 1 3 0) in
  let p4 = mk_photo ~observation_id:obs.id (utc 2026 1 1 4 0) in
  let p5 = mk_photo ~observation_id:obs.id (utc 2026 1 1 5 0) in
  let photos = [tied_hi; tied_lo; p2; p3; p4; p5; earliest] in
  let expected =
    List.map Photo_id.to_string [earliest.id; tie_lo; tie_hi; p2.id; p3.id]
  in
  match Free_name.sent ~observations:[obs] ~photos with
  | Some s ->
      Alcotest.(check (list string))
        "ascending by taken_at, ties by id ascending, first 5" expected
        (photo_id_strings s.photos)
  | None -> Alcotest.fail "expected Some"

let sent_keeps_exactly_max_photos () =
  let obs = mk_obs (utc 2026 1 1 0 0) in
  let photos =
    List.init Herbier_identify.Organ.max_photos (fun i ->
        mk_photo ~observation_id:obs.id (utc 2026 1 1 (i + 1) 0))
  in
  Alcotest.(check sent_opt_t)
    "exactly max_photos photos: all kept, in order"
    (Some Free_name.{observation = obs; photos})
    (Free_name.sent ~observations:[obs] ~photos:(List.rev photos))

let sent_ignores_photos_of_other_observations () =
  let obs = mk_obs (utc 2026 1 1 0 0) in
  let other_id = Observation_id.fresh () in
  let known = mk_photo ~observation_id:obs.id (utc 2026 1 1 1 0) in
  let unknown = mk_photo ~observation_id:other_id (utc 2026 1 1 2 0) in
  match Free_name.sent ~observations:[obs] ~photos:[known; unknown] with
  | Some s ->
      Alcotest.(check (list string))
        "only the photo of a listed observation"
        [Photo_id.to_string known.id]
        (photo_id_strings s.photos)
  | None -> Alcotest.fail "expected Some"

(* ============================================================ *)
(* the Identifier button: gate, line, aria *)
(* ============================================================ *)

let identify_enabled_tests () =
  let k = ready_key () in
  Alcotest.(check bool)
    "Ready, 1 photo -> true" true
    (Free_name.identify_enabled (Is.Ready k) ~photos:1);
  Alcotest.(check bool)
    "Ready, 0 photo -> false" false
    (Free_name.identify_enabled (Is.Ready k) ~photos:0);
  List.iter
    (fun (name, gate) ->
      Alcotest.(check bool)
        (Printf.sprintf "%s, 1 photo -> false" name)
        false
        (Free_name.identify_enabled gate ~photos:1))
    [("Offline", Is.Offline); ("No_key", Is.No_key); ("Waiting", Is.Waiting)]

let identify_line_tests () =
  let k = ready_key () in
  List.iter
    (fun (name, gate) ->
      Alcotest.(check (option string))
        (Printf.sprintf "%s, 0 photo -> no_photo_line" name)
        (Some Free_name.no_photo_line)
        (Free_name.identify_line gate ~photos:0))
    [
      ("Ready", Is.Ready k);
      ("Waiting", Is.Waiting);
      ("No_key", Is.No_key);
      ("Offline", Is.Offline);
    ];
  Alcotest.(check (option string))
    "No_key, 1 photo -> Identify_settings.no_key_line" (Some Is.no_key_line)
    (Free_name.identify_line Is.No_key ~photos:1);
  List.iter
    (fun (name, gate) ->
      Alcotest.(check (option string))
        (Printf.sprintf "%s, 1 photo -> None" name)
        None
        (Free_name.identify_line gate ~photos:1))
    [("Offline", Is.Offline); ("Ready", Is.Ready k); ("Waiting", Is.Waiting)]

let identify_aria_tests () =
  let k = ready_key () in
  List.iter
    (fun (name, gate, photos, want) ->
      Alcotest.(check string) name want (Free_name.identify_aria gate ~photos))
    [
      ( "no photo wins over No_key",
        Is.No_key,
        0,
        "Identifier avec Pl@ntNet, aucune photo" );
      ( "Offline, 1 photo",
        Is.Offline,
        1,
        "Identifier avec Pl@ntNet, indisponible hors-ligne" );
      ( "No_key, 1 photo",
        Is.No_key,
        1,
        "Identifier avec Pl@ntNet, clé API manquante" );
      ("Ready, 1 photo", Is.Ready k, 1, "Identifier avec Pl@ntNet");
      ("Waiting, 1 photo", Is.Waiting, 1, "Identifier avec Pl@ntNet");
    ]

(* ============================================================ *)
(* link: what « Lier » writes *)
(* ============================================================ *)

let link_resolved_pending_and_unavailable_tests () =
  let p = Lazy.force p0 in
  let resolved_taxon = Fixtures.digitalis_taxon in
  let name = "Rose de Chine" in
  Alcotest.(check link_t)
    "Resolved t -> Link {name = the first French name; taxon = t}"
    (Free_name.Link {name; taxon = resolved_taxon})
    (Free_name.link
       (Choice.resolved (Choice.v p) (Choice.Resolved resolved_taxon)));
  let own_taxon = plantnet_taxon_of p in
  Alcotest.(check link_t)
    "pending (v p) -> Link, Pl@ntNet's own taxon (R12)"
    (Free_name.Link {name; taxon = own_taxon})
    (Free_name.link (Choice.v p));
  Alcotest.(check link_t)
    "Unavailable \"x\" -> the same Link (R12)"
    (Free_name.Link {name; taxon = own_taxon})
    (Free_name.link (Choice.resolved (Choice.v p) (Choice.Unavailable "x")));
  Alcotest.(check link_t)
    "Unknown -> Unknown_to_gbif" Free_name.Unknown_to_gbif
    (Free_name.link (Choice.resolved (Choice.v p) Choice.Unknown))

let link_no_gbif_id_tests () =
  let p = {(Lazy.force p0) with gbif = None} in
  Alcotest.(check link_t)
    "pending, gbif = None -> Gbif_unavailable" Free_name.Gbif_unavailable
    (Free_name.link (Choice.v p));
  Alcotest.(check link_t)
    "Unavailable _, gbif = None -> Gbif_unavailable" Free_name.Gbif_unavailable
    (Free_name.link (Choice.resolved (Choice.v p) (Choice.Unavailable "x")));
  Alcotest.(check link_t)
    "Unknown, gbif = None -> Unknown_to_gbif" Free_name.Unknown_to_gbif
    (Free_name.link (Choice.resolved (Choice.v p) Choice.Unknown));
  let resolved_taxon = Fixtures.digitalis_taxon in
  Alcotest.(check link_t)
    "Resolved t, gbif = None -> Link {name; taxon = t} anyway"
    (Free_name.Link {name = "Rose de Chine"; taxon = resolved_taxon})
    (Free_name.link
       (Choice.resolved (Choice.v p) (Choice.Resolved resolved_taxon)))

let link_no_common_name_tests () =
  let p = {(Lazy.force p0) with common_names = []} in
  let resolved_taxon = Fixtures.digitalis_taxon in
  Alcotest.(check link_t)
    "common_names = [] -> Link {name = the Latin name, no author}"
    (Free_name.Link {name = "Hibiscus rosa-sinensis"; taxon = resolved_taxon})
    (Free_name.link
       (Choice.resolved (Choice.v p) (Choice.Resolved resolved_taxon)))

(* ============================================================ *)
(* problem: the line under the hero *)
(* ============================================================ *)

let problem_tests () =
  Alcotest.(check (option string))
    "Link _ -> None" None
    (Free_name.problem
       (Free_name.Link {name = "x"; taxon = Fixtures.digitalis_taxon}));
  Alcotest.(check (option string))
    "Unknown_to_gbif"
    (Some "GBIF ne connaît pas cette espèce : la fiche garde son nom libre.")
    (Free_name.problem Free_name.Unknown_to_gbif);
  Alcotest.(check (option string))
    "Gbif_unavailable"
    (Some
       "GBIF n'a pas répondu : la fiche n'a pas été liée. Réessayez avec le \
        réseau.")
    (Free_name.problem Free_name.Gbif_unavailable)

(* ============================================================ *)
(* relink keeps the free name as an alias *)
(* ============================================================ *)

let done_criterion_tests () =
  let at = utc 2026 11 16 10 0 in
  let id = Plant_id.fresh () in
  let free = Plant.v ~id ~at "Orchidée du talus" in
  let different_name_proposal =
    {(Lazy.force p0) with common_names = ["Rose de Chine"; "Hibiscus"]}
  in
  (match
     Free_name.link
       (Choice.resolved
          (Choice.v different_name_proposal)
          (Choice.Resolved Fixtures.digitalis_taxon))
   with
  | Free_name.Link {name; taxon} ->
      let linked = Plant_link.apply ~at ~name free taxon in
      Alcotest.(check string)
        "display_name = the new name" name linked.display_name;
      Alcotest.(check (list string))
        "aliases = [the old free name]" ["Orchidée du talus"] linked.aliases;
      Alcotest.(check (option int))
        "gbif_key = Some taxon.key" (Some taxon.key) linked.gbif_key
  | other ->
      Alcotest.failf "expected Link, got %s"
        (Format.asprintf "%a" Free_name.pp_link other));
  (* name equal to the free name (fold ASCII case): no alias added. *)
  let same_name_proposal =
    {(Lazy.force p0) with common_names = ["ORCHIDéE DU TALUS"]}
  in
  match
    Free_name.link
      (Choice.resolved
         (Choice.v same_name_proposal)
         (Choice.Resolved Fixtures.digitalis_taxon))
  with
  | Free_name.Link {name; taxon} ->
      let linked = Plant_link.apply ~at ~name free taxon in
      Alcotest.(check (list string))
        "no alias added when the new name equals the old one (ASCII case \
         folded)"
        [] linked.aliases
  | other ->
      Alcotest.failf "expected Link, got %s"
        (Format.asprintf "%a" Free_name.pp_link other)

(* ============================================================ *)
(* no forbidden wording *)
(* ============================================================ *)

let no_forbidden_wording_tests () =
  let forbidden = ["cors"; "origin"; "localhost"; "expos"; "api-key"] in
  let check_text label text =
    let lower = String.lowercase_ascii text in
    List.iter
      (fun bad ->
        Alcotest.(check bool)
          (Printf.sprintf "%s: no %S" label bad)
          false
          (Support_text.contains ~sub:bad lower))
      forbidden
  in
  check_text "identify_label" Free_name.identify_label;
  check_text "search_label" Free_name.search_label;
  check_text "no_photo_line" Free_name.no_photo_line;
  check_text "link_failed" Free_name.link_failed;
  check_text "plant_gone" Free_name.plant_gone;
  let k = ready_key () in
  let gates = [Is.Ready k; Is.Waiting; Is.No_key; Is.Offline] in
  List.iter
    (fun g ->
      List.iter
        (fun photos ->
          (match Free_name.identify_line g ~photos with
          | None -> ()
          | Some s -> check_text "identify_line" s);
          check_text "identify_aria" (Free_name.identify_aria g ~photos))
        [0; 1])
    gates;
  List.iter
    (fun l ->
      match Free_name.problem l with
      | None -> ()
      | Some s -> check_text "problem" s)
    [
      Free_name.Link {name = "x"; taxon = Fixtures.digitalis_taxon};
      Free_name.Unknown_to_gbif;
      Free_name.Gbif_unavailable;
    ]

(* ============================================================ *)
(* suite *)
(* ============================================================ *)

let free_name =
  [
    Alcotest.test_case "labels: identify_label, search_label" `Quick label_tests;
    Alcotest.test_case "sent: no observations or no photo -> None" `Quick
      sent_empty_tests;
    Alcotest.test_case "sent: picks the observation that has photos" `Quick
      sent_picks_the_one_with_photos;
    Alcotest.test_case
      "sent: the newest observation with photos wins, whatever the input order"
      `Quick sent_newest_with_photos_wins_whatever_order;
    Alcotest.test_case
      "sent: a soft-deleted observation is skipped, None when it is the only \
       one with photos"
      `Quick sent_skips_soft_deleted;
    Alcotest.test_case "sent: a soft-deleted photo is never sent" `Quick
      sent_skips_soft_deleted_photos;
    Alcotest.test_case "sent: equal at, the greater observation id wins" `Quick
      sent_tie_greater_id_wins;
    Alcotest.test_case "sent: photos ordered by taken_at then id, first 5 of 7"
      `Quick sent_orders_photos_and_truncates;
    Alcotest.test_case "sent: exactly max_photos photos are all kept" `Quick
      sent_keeps_exactly_max_photos;
    Alcotest.test_case
      "sent: a photo of another (or no) observation is never sent" `Quick
      sent_ignores_photos_of_other_observations;
    Alcotest.test_case "identify_enabled: Ready with a photo only" `Quick
      identify_enabled_tests;
    Alcotest.test_case "identify_line: no photo first, then No_key, else None"
      `Quick identify_line_tests;
    Alcotest.test_case
      "identify_aria: no photo first, then Offline, No_key, else the label"
      `Quick identify_aria_tests;
    Alcotest.test_case
      "link: Resolved uses GBIF's taxon; pending and Unavailable use \
       Pl@ntNet's own (R12); Unknown -> Unknown_to_gbif"
      `Quick link_resolved_pending_and_unavailable_tests;
    Alcotest.test_case
      "link: gbif = None -> Gbif_unavailable (pending, Unavailable), \
       Unknown_to_gbif (Unknown), Link still on Resolved"
      `Quick link_no_gbif_id_tests;
    Alcotest.test_case "link: no common name -> Link {name = the Latin name}"
      `Quick link_no_common_name_tests;
    Alcotest.test_case "problem: None for Link, the two exact strings" `Quick
      problem_tests;
    Alcotest.test_case
      "Done criterion: link then Plant_link.apply renames the free-name plant, \
       keeps its old name as an alias, sets gbif_key; no alias when the new \
       name equals the old one"
      `Quick done_criterion_tests;
    Alcotest.test_case
      "no string of Free_name names CORS, an origin, localhost, exposing or \
       api-key"
      `Quick no_forbidden_wording_tests;
  ]
