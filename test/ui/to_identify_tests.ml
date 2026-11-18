(* Herbier_ui_model.To_identify: 6i's button, line and aria, caller, 6j's
   after_layer, and what a chosen proposal saves (Record_plan.of_choice).
   Proposals are decoded from the recorded fixture. *)

module To_identify = Herbier_ui_model.To_identify
module Record_plan = Herbier_ui_model.Record_plan
module Identify = Herbier_ui_model.Identify
module Choice = Identify.Choice
module Caller = Identify.Caller
module Layer = Identify.Layer
module Failure = Identify.Failure
module Text = Identify.Text
module Is = Herbier_ui_model.Identify_settings
module Plantnet = Herbier_identify.Plantnet
module Gbif = Herbier_refs.Sources.Gbif
module Plant = Herbier_domain.Plant
module Plant_id = Herbier_domain.Ids.Plant_id
module Photo = Herbier_domain.Photo
module Photo_id = Herbier_domain.Ids.Photo_id
module Observation_id = Herbier_domain.Ids.Observation_id
module Fixture = Herbier_test_support.Fixture
module Support_text = Herbier_test_support.Text

let utc = Fixtures.utc
let t0 = utc 2026 1 1 0 0

(* ---------- testables ---------- *)

let pp_caller fmt = function
  | Caller.Noter -> Format.pp_print_string fmt "Noter"
  | Caller.Queue (Some {index; total}) ->
      Format.fprintf fmt "Queue (Some {index = %d; total = %d})" index total
  | Caller.Queue None -> Format.pp_print_string fmt "Queue None"
  | Caller.Free_name id ->
      Format.fprintf fmt "Free_name %s" (Plant_id.to_string id)

let caller_t = Alcotest.testable pp_caller Caller.equal
let action_t = Alcotest.testable Caller.pp_action Caller.equal_action
let failure_t = Alcotest.testable Failure.pp Failure.equal

let pp_target fmt = function
  | Record_plan.Existing (p : Plant.t) ->
      Format.fprintf fmt "Existing %s" p.display_name
  | Record_plan.Free n -> Format.fprintf fmt "Free %s" n
  | Record_plan.Linked {name; taxon} ->
      Format.fprintf fmt "Linked {name = %s; taxon = %d}" name taxon.key
  | Record_plan.To_identify -> Format.pp_print_string fmt "To_identify"

let target_t = Alcotest.testable pp_target ( = )

let pp_after fmt = function
  | To_identify.Stay -> Format.pp_print_string fmt "Stay"
  | To_identify.Resolve (p : Plantnet.proposal) ->
      Format.fprintf fmt "Resolve %s" p.name

let after_t = Alcotest.testable pp_after To_identify.equal_after

(* ---------- helpers ---------- *)

let ready_key () =
  match Is.Key.of_input "abcdefgh" with
  | Some k -> k
  | None -> Alcotest.fail "Key.of_input \"abcdefgh\" should be a key"

let plant ?(gbif_key = None) ?(deleted_at = None) ?(aliases = []) name : Plant.t
    =
  {
    Fixtures.base_plant with
    id = Plant_id.fresh ();
    display_name = name;
    aliases;
    gbif_key;
    deleted_at;
  }

let photo taken_at : Photo.t =
  {
    id = Photo_id.fresh ();
    observation_id = Observation_id.fresh ();
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
    deleted_at = None;
  }

let photo_ids l = List.map (fun (p : Photo.t) -> Photo_id.to_string p.id) l

(* The fixture's decoded proposals: P1 = Hibiscus rosa-sinensis L., gbif
   3152559, "Rose de Chine" first; P4 = "Hibiscus spp." (genus-level), gbif
   null, "Hibiscus commun". *)
let decode name =
  match Plantnet.decode_answer (Fixture.read name) with
  | Ok a -> a
  | Error e -> Alcotest.failf "decode %s: %s" name (Plantnet.error_to_string e)

let answer = lazy (decode "plantnet_identify_two_flower_leaf_200.json")

let nth n =
  match List.nth_opt (Lazy.force answer).proposals n with
  | Some p -> p
  | None ->
      Alcotest.failf
        "plantnet_identify_two_flower_leaf_200.json has no proposal %d" n

let p1 = lazy (nth 0)
let p4 = lazy (nth 3)

let plantnet_taxon_of p =
  match Choice.plantnet_taxon p with
  | Some t -> t
  | None -> Alcotest.fail "plantnet_taxon: expected Some"

(* ============================================================ *)
(* 1. sent *)
(* ============================================================ *)

let sent_tests () =
  let ps = List.init 7 (fun i -> photo (utc 2026 6 1 0 i)) in
  List.iter
    (fun n ->
      let kept = min n 5 in
      let input = List.filteri (fun i _ -> i < n) ps in
      let expected = List.filteri (fun i _ -> i < kept) ps in
      Alcotest.(check (list string))
        (Printf.sprintf "%d photo(s) -> %d kept, the first ones in order" n kept)
        (photo_ids expected)
        (photo_ids (To_identify.sent input)))
    [0; 1; 5; 6; 7]

(* ============================================================ *)
(* 2. identify_enabled *)
(* ============================================================ *)

let identify_enabled_tests () =
  let k = ready_key () in
  Alcotest.(check bool)
    "Ready, 1 photo -> true" true
    (To_identify.identify_enabled (Is.Ready k) ~photos:1);
  Alcotest.(check bool)
    "Ready, 0 photo -> false" false
    (To_identify.identify_enabled (Is.Ready k) ~photos:0);
  List.iter
    (fun (name, gate) ->
      Alcotest.(check bool)
        (Printf.sprintf "%s, 3 photos -> false" name)
        false
        (To_identify.identify_enabled gate ~photos:3))
    [("Offline", Is.Offline); ("No_key", Is.No_key); ("Waiting", Is.Waiting)]

(* ============================================================ *)
(* 3. identify_line *)
(* ============================================================ *)

let identify_line_tests () =
  let k = ready_key () in
  List.iter
    (fun (name, gate) ->
      Alcotest.(check (option string))
        (Printf.sprintf "%s, 0 photo -> no_photo_line" name)
        (Some To_identify.no_photo_line)
        (To_identify.identify_line gate ~photos:0))
    [
      ("Ready", Is.Ready k);
      ("Waiting", Is.Waiting);
      ("No_key", Is.No_key);
      ("Offline", Is.Offline);
    ];
  Alcotest.(check (option string))
    "No_key, 2 photos -> Identify_settings.no_key_line" (Some Is.no_key_line)
    (To_identify.identify_line Is.No_key ~photos:2);
  Alcotest.(check (option string))
    "Offline, 2 photos -> offline_line" (Some To_identify.offline_line)
    (To_identify.identify_line Is.Offline ~photos:2);
  Alcotest.(check (option string))
    "Ready, 2 photos -> None" None
    (To_identify.identify_line (Is.Ready k) ~photos:2);
  Alcotest.(check (option string))
    "Waiting, 2 photos -> None" None
    (To_identify.identify_line Is.Waiting ~photos:2)

(* ============================================================ *)
(* 4. identify_aria *)
(* ============================================================ *)

let identify_aria_tests () =
  let k = ready_key () in
  Alcotest.(check string)
    "0 photo, even offline -> aucune photo"
    "Identifier avec Pl@ntNet, aucune photo"
    (To_identify.identify_aria Is.Offline ~photos:0);
  Alcotest.(check string)
    "0 photo, even no key -> aucune photo"
    "Identifier avec Pl@ntNet, aucune photo"
    (To_identify.identify_aria Is.No_key ~photos:0);
  Alcotest.(check string)
    "Offline, a photo -> indisponible hors-ligne"
    "Identifier avec Pl@ntNet, indisponible hors-ligne"
    (To_identify.identify_aria Is.Offline ~photos:2);
  Alcotest.(check string)
    "No_key, a photo -> clé API manquante"
    "Identifier avec Pl@ntNet, clé API manquante"
    (To_identify.identify_aria Is.No_key ~photos:2);
  Alcotest.(check string)
    "Ready, a photo -> identify_label" To_identify.identify_label
    (To_identify.identify_aria (Is.Ready k) ~photos:2);
  Alcotest.(check string)
    "Waiting, a photo -> identify_label" To_identify.identify_label
    (To_identify.identify_aria Is.Waiting ~photos:2)

(* ============================================================ *)
(* 5. texts, and the generic key-not-exposed rule at 4k's level *)
(* ============================================================ *)

let texts_tests () =
  Alcotest.(check string)
    "identify_label" "Identifier avec Pl@ntNet" To_identify.identify_label;
  Alcotest.(check string) "or_by_name" "ou par le nom" To_identify.or_by_name;
  Alcotest.(check string)
    "offline_line" "Hors-ligne : l'identification reviendra avec le réseau."
    To_identify.offline_line;
  Alcotest.(check string)
    "no_photo_line" "Cette observation n'a pas de photo à envoyer à Pl@ntNet."
    To_identify.no_photo_line;
  let forbidden =
    ["cors"; "origin"; "origine"; "localhost"; "expos"; "api-key"]
  in
  let check_clean label text =
    let lower = String.lowercase_ascii text in
    List.iter
      (fun bad ->
        Alcotest.(check bool)
          (Printf.sprintf "%s does not name %S" label bad)
          false
          (Support_text.contains ~sub:bad lower))
      forbidden
  in
  check_clean "identify_label" To_identify.identify_label;
  check_clean "or_by_name" To_identify.or_by_name;
  check_clean "offline_line" To_identify.offline_line;
  check_clean "no_photo_line" To_identify.no_photo_line;
  let failure =
    Failure.of_error ~no_reject:false
      (Failure.Plantnet Plantnet.Key_not_exposed)
  in
  Alcotest.(check failure_t)
    "Key_not_exposed -> Not_answered (4k has no special case)"
    Failure.Not_answered failure;
  Alcotest.(check bool) "retry of it is true" true (Failure.retry failure);
  check_clean "Text.failure_title of it" (Text.failure_title failure);
  check_clean "Text.failure_body of it" (Text.failure_body ~photos:1 failure)

(* ============================================================ *)
(* 6. caller *)
(* ============================================================ *)

let caller_tests () =
  let pos ~index ~total : To_identify.position = {index; total; next = None} in
  Alcotest.(check caller_t)
    "Some {index = 2; total = 3} -> Queue (Some {index = 2; total = 3})"
    (Caller.Queue (Some {index = 2; total = 3}))
    (To_identify.caller (Some (pos ~index:2 ~total:3)));
  Alcotest.(check caller_t)
    "None (no longer in the queue) -> Queue None" (Caller.Queue None)
    (To_identify.caller None);
  let queue = To_identify.caller None in
  Alcotest.(check action_t)
    "Caller.action (caller _) ~owned:true = Link" Caller.Link
    (Caller.action queue ~owned:true);
  Alcotest.(check action_t)
    "Caller.action (caller _) ~owned:false = Create" Caller.Create
    (Caller.action queue ~owned:false)

(* ============================================================ *)
(* 7. after_layer *)
(* ============================================================ *)

let after_layer_tests () =
  let p = Lazy.force p1 in
  Alcotest.(check after_t)
    "Chosen p -> Resolve p" (To_identify.Resolve p)
    (To_identify.after_layer (Layer.Chosen p));
  List.iter
    (fun (name, outcome) ->
      Alcotest.(check after_t)
        (Printf.sprintf "%s -> Stay" name)
        To_identify.Stay
        (To_identify.after_layer outcome))
    [
      ("Left", Layer.Left);
      ("None_matches", Layer.None_matches);
      ("Retake", Layer.Retake);
      ("Keep_unnamed", Layer.Keep_unnamed);
    ]

(* ============================================================ *)
(* 8. Record_plan.of_choice: what a chosen proposal saves *)
(* ============================================================ *)

let save_a_live_owner_pending () =
  let p = Lazy.force p1 in
  let owner = plant ~gbif_key:(Some 3152559) "Ma plante" in
  Alcotest.(check target_t)
    "a live plant with gbif_key = Some k, resolution None -> Existing it"
    (Record_plan.Existing owner)
    (Record_plan.of_choice ~plants:[owner] (Choice.v p))

let save_b_deleted_owner_pending () =
  let p = Lazy.force p1 in
  let dead = plant ~gbif_key:(Some 3152559) ~deleted_at:(Some t0) "Ma plante" in
  Alcotest.(check target_t)
    "the same plant deleted -> Linked, Pl@ntNet's own taxon"
    (Record_plan.Linked {name = Choice.new_name p; taxon = plantnet_taxon_of p})
    (Record_plan.of_choice ~plants:[dead] (Choice.v p))

let save_c_resolved_key_and_accepted_key () =
  let p = Lazy.force p1 in
  let resolved : Gbif.Taxon.t =
    {Fixtures.digitalis_taxon with key = 7000000; accepted_key = None}
  in
  let owner = plant ~gbif_key:(Some resolved.key) "Plante résolue" in
  Alcotest.(check target_t)
    "resolution Resolved t, t.key <> k, a live plant on t.key -> Existing it"
    (Record_plan.Existing owner)
    (Record_plan.of_choice ~plants:[owner]
       (Choice.resolved (Choice.v p) (Choice.Resolved resolved)));
  let synonym = {resolved with accepted_key = Some 7000001} in
  let accepted_owner = plant ~gbif_key:(Some 7000001) "Plante acceptée" in
  Alcotest.(check target_t)
    "t.accepted_key = Some a, a plant on a -> Existing it"
    (Record_plan.Existing accepted_owner)
    (Record_plan.of_choice ~plants:[accepted_owner]
       (Choice.resolved (Choice.v p) (Choice.Resolved synonym)))

let save_d_resolved_no_owner () =
  let p = Lazy.force p1 in
  let taxon : Gbif.Taxon.t = {Fixtures.digitalis_taxon with key = 8000000} in
  Alcotest.(check target_t)
    "resolution Resolved t, no owner -> Linked {name; taxon = t}"
    (Record_plan.Linked {name = Choice.new_name p; taxon})
    (Record_plan.of_choice ~plants:[]
       (Choice.resolved (Choice.v p) (Choice.Resolved taxon)))

let save_e_unavailable_no_owner () =
  let p = Lazy.force p1 in
  Alcotest.(check target_t)
    "Unavailable \"x\", no owner -> Linked, Pl@ntNet's own taxon"
    (Record_plan.Linked {name = Choice.new_name p; taxon = plantnet_taxon_of p})
    (Record_plan.of_choice ~plants:[]
       (Choice.resolved (Choice.v p) (Choice.Unavailable "x")))

let save_e2_unavailable_owner () =
  let p = Lazy.force p1 in
  let owner = plant ~gbif_key:(Some 3152559) "Ma plante" in
  Alcotest.(check target_t)
    "Unavailable \"x\", a live plant on the proposal's id -> Existing it"
    (Record_plan.Existing owner)
    (Record_plan.of_choice ~plants:[owner]
       (Choice.resolved (Choice.v p) (Choice.Unavailable "x")))

let save_e3_unavailable_no_gbif_id () =
  let p = Lazy.force p4 in
  Alcotest.(check target_t)
    "gbif = None, Unavailable \"x\" -> Free (new_name p)"
    (Record_plan.Free (Choice.new_name p))
    (Record_plan.of_choice ~plants:[]
       (Choice.resolved (Choice.v p) (Choice.Unavailable "x")))

let save_f_unknown_no_matching_plant () =
  let p = Lazy.force p1 in
  Alcotest.(check target_t)
    "Unknown, no plant of that name -> Free (new_name p)"
    (Record_plan.Free (Choice.new_name p))
    (Record_plan.of_choice ~plants:[]
       (Choice.resolved (Choice.v p) Choice.Unknown))

let save_g_unknown_alias_case_folded () =
  let p = Lazy.force p1 in
  let different_case = String.uppercase_ascii (Choice.new_name p) in
  let owner = plant ~aliases:[different_case] "Autre nom" in
  Alcotest.(check target_t)
    "Unknown, a live plant whose alias is new_name p (different ASCII case) -> \
     Existing it"
    (Record_plan.Existing owner)
    (Record_plan.of_choice ~plants:[owner]
       (Choice.resolved (Choice.v p) Choice.Unknown))

let save_h_no_gbif_id_pending () =
  let p = Lazy.force p4 in
  Alcotest.(check target_t)
    "gbif = None, resolution None -> Free (new_name p)"
    (Record_plan.Free (Choice.new_name p))
    (Record_plan.of_choice ~plants:[] (Choice.v p))

let save_i_no_name_at_all () =
  let p =
    {
      (Lazy.force p1) with
      Plantnet.common_names = [];
      name = "";
      scientific_name = "";
    }
  in
  Alcotest.(check target_t)
    "no French nor Latin name, Unknown -> To_identify (nothing saved)"
    Record_plan.To_identify
    (Record_plan.of_choice ~plants:[]
       (Choice.resolved (Choice.v p) Choice.Unknown))

let save_j_first_owner_wins () =
  let p = Lazy.force p1 in
  let first = plant ~gbif_key:(Some 3152559) "Première"
  and second = plant ~gbif_key:(Some 3152559) "Seconde" in
  Alcotest.(check target_t)
    "two matching plants: the first in list order wins"
    (Record_plan.Existing first)
    (Record_plan.of_choice ~plants:[first; second] (Choice.v p))

(* ============================================================ *)
(* suite *)
(* ============================================================ *)

let identify_queue =
  [
    Alcotest.test_case
      "sent: 0, 1, 5, 6, 7 photos -> 0, 1, 5, 5, 5 kept, in order" `Quick
      sent_tests;
    Alcotest.test_case
      "identify_enabled: Ready with a photo, disabled otherwise" `Quick
      identify_enabled_tests;
    Alcotest.test_case
      "identify_line: no photo first, then No_key, then Offline, else None"
      `Quick identify_line_tests;
    Alcotest.test_case
      "identify_aria: photos = 0 wins over Offline and No_key, else 4d's" `Quick
      identify_aria_tests;
    Alcotest.test_case
      "texts: the four constants, none naming CORS/origin/localhost/exposing; \
       Key_not_exposed is Not_answered, retried"
      `Quick texts_tests;
    Alcotest.test_case
      "caller: Some -> Queue of it, None -> Queue None, action owned/not" `Quick
      caller_tests;
    Alcotest.test_case "after_layer: Chosen -> Resolve, the rest -> Stay" `Quick
      after_layer_tests;
    Alcotest.test_case "save a: a live owner, pending resolution -> Existing"
      `Quick save_a_live_owner_pending;
    Alcotest.test_case "save b: the owner deleted -> Linked" `Quick
      save_b_deleted_owner_pending;
    Alcotest.test_case
      "save c: resolved key and accepted key, each with its owner -> Existing"
      `Quick save_c_resolved_key_and_accepted_key;
    Alcotest.test_case "save d: resolved, no owner -> Linked with it" `Quick
      save_d_resolved_no_owner;
    Alcotest.test_case
      "save e: GBIF unavailable, no owner -> Linked, Pl@ntNet's taxon" `Quick
      save_e_unavailable_no_owner;
    Alcotest.test_case "save e2: GBIF unavailable, a live owner -> Existing"
      `Quick save_e2_unavailable_owner;
    Alcotest.test_case "save e3: GBIF unavailable, gbif = None -> Free" `Quick
      save_e3_unavailable_no_gbif_id;
    Alcotest.test_case "save f: Unknown, no matching plant -> Free" `Quick
      save_f_unknown_no_matching_plant;
    Alcotest.test_case
      "save g: Unknown, an alias matching case-insensitively -> Existing" `Quick
      save_g_unknown_alias_case_folded;
    Alcotest.test_case "save h: gbif = None, pending -> Free" `Quick
      save_h_no_gbif_id_pending;
    Alcotest.test_case "save i: no French nor Latin name -> None" `Quick
      save_i_no_name_at_all;
    Alcotest.test_case "save j: two matching owners, the first wins" `Quick
      save_j_first_owner_wins;
  ]
