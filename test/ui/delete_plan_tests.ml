(* Herbier_ui_model.Delete_plan: the texts and Cascade edits of 5a's, 4h's and
   the long-press delete of 4a / 4c. *)

module Delete_plan = Herbier_ui_model.Delete_plan
module Plant = Herbier_domain.Plant
module Plant_id = Herbier_domain.Ids.Plant_id
module Observation_id = Herbier_domain.Ids.Observation_id
module Photo_id = Herbier_domain.Ids.Photo_id
module Tag_id = Herbier_domain.Ids.Tag_id
module Outbox = Herbier_store.Outbox
module Codec = Herbier_store.Codec
module Cascade = Herbier_store.Cascade

let utc = Fixtures.utc
let plant_id = Fixtures.plant_id

(* ---------- a local [Codec.param] testable, per constructor ---------- *)

let show_param = function
  | Codec.Null -> "Null"
  | Codec.Int n -> Printf.sprintf "Int %d" n
  | Codec.Float f -> Printf.sprintf "Float %.17g" f
  | Codec.Text s -> Printf.sprintf "Text %S" s

let param_eq a b =
  match (a, b) with
  | Codec.Null, Codec.Null -> true
  | Codec.Int a, Codec.Int b -> Int.equal a b
  | Codec.Float a, Codec.Float b -> Float.equal a b
  | Codec.Text a, Codec.Text b -> String.equal a b
  | (Codec.Null | Codec.Int _ | Codec.Float _ | Codec.Text _), _ -> false

let param = Alcotest.testable (Fmt.of_to_string show_param) param_eq
let params = Alcotest.list param

(* ---------- fixtures ---------- *)

let ortie = Plant.v ~id:(plant_id ()) ~at:(utc 2026 1 1 0 0) "Ortie"
let now = utc 2026 11 20 10 0
let ids n fresh = List.init n (fun _ -> fresh ())

let plant_scope ?(observations = 0) ?(photos = 0) ?(tags = 0) () :
    Delete_plan.plant =
  {
    plant = ortie;
    observations = ids observations Observation_id.fresh;
    photos = ids photos Photo_id.fresh;
    tags = ids tags Tag_id.fresh;
  }

let obs_scope ?(photos = 0) () : Delete_plan.observation =
  {observation = Observation_id.fresh (); photos = ids photos Photo_id.fresh}

(* ---------- comparing two [Outbox.edit] lists statement-for-statement
   ---------- *)

let check_edits what expected actual =
  Alcotest.(check int)
    (what ^ ": same number of edits")
    (List.length expected) (List.length actual);
  List.iteri
    (fun i (e, a) ->
      let se = Outbox.bare_stmt (Outbox.without_entry e) in
      let sa = Outbox.bare_stmt (Outbox.without_entry a) in
      Alcotest.(check string)
        (Printf.sprintf "%s: edit %d, statement sql" what i)
        se.sql sa.sql;
      Alcotest.check params
        (Printf.sprintf "%s: edit %d, statement params" what i)
        se.params sa.params;
      let re = Outbox.reread e and ra = Outbox.reread a in
      Alcotest.(check string)
        (Printf.sprintf "%s: edit %d, read-back sql" what i)
        re.sql ra.sql;
      Alcotest.check params
        (Printf.sprintf "%s: edit %d, read-back params" what i)
        re.params ra.params)
    (List.combine expected actual)

(* ---------- plant_title ---------- *)

let plant_title_tests () =
  Alcotest.(check string)
    "plant_title names the plant, with 5a's guillemets"
    "Supprimer \xc2\xab Ortie \xc2\xbb ?"
    (Delete_plan.plant_title ortie)

(* ---------- plant_text ---------- *)

let plant_text_tests () =
  let cases =
    [
      (0, 0, "La fiche quitte l'herbier.");
      (0, 3, "La fiche quitte l'herbier.");
      (1, 0, "La fiche et son observation quittent l'herbier.");
      (3, 0, "La fiche et ses 3 observations quittent l'herbier.");
      ( 1,
        1,
        "La fiche, son observation et ses 1 photo quittent l'herbier. Les \
         originaux envoy\xc3\xa9s dans Google Drive y restent." );
      ( 1,
        4,
        "La fiche, son observation et ses 4 photos quittent l'herbier. Les \
         originaux envoy\xc3\xa9s dans Google Drive y restent." );
      ( 2,
        5,
        "La fiche, ses 2 observations et leurs 5 photos quittent l'herbier. \
         Les originaux envoy\xc3\xa9s dans Google Drive y restent." );
    ]
  in
  List.iter
    (fun (observations, photos, expected) ->
      Alcotest.(check string)
        (Printf.sprintf "plant_text, %d observation(s), %d photo(s)"
           observations photos)
        expected
        (Delete_plan.plant_text (plant_scope ~observations ~photos ())))
    cases

let plant_text_ignores_tags_tests () =
  Alcotest.(check string)
    "plant_text, 1 observation, 0 photo, 3 tags: same as 0 tags"
    (Delete_plan.plant_text (plant_scope ~observations:1 ()))
    (Delete_plan.plant_text (plant_scope ~observations:1 ~tags:3 ()))

(* ---------- plant_action ---------- *)

let plant_action_tests () =
  Alcotest.(check string)
    "plant_action, no observation" "Supprimer la plante \xe2\x80\xba"
    (Delete_plan.plant_action (plant_scope ()));
  Alcotest.(check string)
    "plant_action, one observation"
    "Supprimer la plante et son observation \xe2\x80\xba"
    (Delete_plan.plant_action (plant_scope ~observations:1 ()));
  Alcotest.(check string)
    "plant_action, several observations"
    "Supprimer la plante et ses 4 observations \xe2\x80\xba"
    (Delete_plan.plant_action (plant_scope ~observations:4 ()))

(* ---------- plant_failure ---------- *)

let plant_failure_tests () =
  Alcotest.(check string)
    "plant_failure" "La plante n'a pas pu \xc3\xaatre supprim\xc3\xa9e."
    Delete_plan.plant_failure

(* ---------- observation_title ---------- *)

let observation_title_tests () =
  Alcotest.(check string)
    "observation_title" "Supprimer cette observation ?"
    Delete_plan.observation_title

(* ---------- observation_text ---------- *)

let observation_text_tests () =
  Alcotest.(check string)
    "observation_text, no photo" "Elle quitte l'herbier et le journal."
    (Delete_plan.observation_text (obs_scope ()));
  Alcotest.(check string)
    "observation_text, one photo"
    "Elle quitte l'herbier avec ses 1 photo. Les originaux envoy\xc3\xa9s dans \
     Google Drive y restent."
    (Delete_plan.observation_text (obs_scope ~photos:1 ()));
  Alcotest.(check string)
    "observation_text, several photos"
    "Elle quitte l'herbier avec ses 3 photos. Les originaux envoy\xc3\xa9s \
     dans Google Drive y restent."
    (Delete_plan.observation_text (obs_scope ~photos:3 ()))

(* ---------- observation_failure ---------- *)

let observation_failure_tests () =
  Alcotest.(check string)
    "observation_failure"
    "L'observation n'a pas pu \xc3\xaatre supprim\xc3\xa9e."
    Delete_plan.observation_failure

(* ---------- plant_edits = exactly Cascade.plant's edits ---------- *)

let plant_edits_tests () =
  let scope = plant_scope ~observations:2 ~photos:3 ~tags:2 () in
  let expected =
    Cascade.plant ~at:now ~photos:scope.photos ~observations:scope.observations
      ~tags:scope.tags scope.plant.id
  in
  let actual = Delete_plan.plant_edits ~at:now scope in
  check_edits "plant_edits, 2 observations/3 photos/2 tags" expected actual;
  Alcotest.(check int) "length = 1 + 2 + 3 + 2 = 8" 8 (List.length actual);
  let empty_scope = plant_scope () in
  let expected_empty =
    Cascade.plant ~at:now ~photos:[] ~observations:[] ~tags:[]
      empty_scope.plant.id
  in
  let actual_empty = Delete_plan.plant_edits ~at:now empty_scope in
  check_edits "plant_edits, no dependents" expected_empty actual_empty;
  Alcotest.(check int) "exactly one edit" 1 (List.length actual_empty)

(* ---------- observation_edits = exactly Cascade.observation's edits
   ---------- *)

let observation_edits_tests () =
  let a = Photo_id.fresh () and b = Photo_id.fresh () in
  let observation = Observation_id.fresh () in
  let scope : Delete_plan.observation = {observation; photos = [a; b]} in
  let expected = Cascade.observation ~at:now ~photos:[a; b] observation in
  let actual = Delete_plan.observation_edits ~at:now scope in
  check_edits "observation_edits, 2 photos" expected actual;
  Alcotest.(check int) "length = 1 + 2 = 3" 3 (List.length actual);
  let scope0 : Delete_plan.observation = {observation; photos = []} in
  let expected0 = Cascade.observation ~at:now ~photos:[] observation in
  let actual0 = Delete_plan.observation_edits ~at:now scope0 in
  check_edits "observation_edits, no photo" expected0 actual0;
  Alcotest.(check int) "length = 1" 1 (List.length actual0)

(* ---------- the edits carry the caller's instant ---------- *)

let edits_carry_the_given_at_tests () =
  let t1 = utc 2026 11 20 10 0 and t2 = utc 2026 11 21 9 30 in
  let scope = plant_scope () in
  let stmt_params at =
    (Outbox.bare_stmt
       (Outbox.without_entry (List.hd (Delete_plan.plant_edits ~at scope))))
      .params
  in
  let p1 = stmt_params t1 and p2 = stmt_params t2 in
  let carried t p =
    let stamp = Codec.Text (Codec.timestamp t) in
    (Some stamp, List.find_opt (param_eq stamp) p)
  in
  let expected, found = carried t1 p1 in
  Alcotest.(check (option param))
    "t1's statement carries Codec.timestamp t1" expected found;
  let expected, found = carried t2 p2 in
  Alcotest.(check (option param))
    "t2's statement carries Codec.timestamp t2" expected found;
  let cascade_at at =
    (Outbox.bare_stmt
       (Outbox.without_entry
          (List.hd
             (Cascade.plant ~at ~photos:[] ~observations:[] ~tags:[]
                scope.plant.id))))
      .params
  in
  Alcotest.check params "plant_edits ~at:t1 matches Cascade.plant ~at:t1"
    (cascade_at t1) p1;
  Alcotest.check params "plant_edits ~at:t2 matches Cascade.plant ~at:t2"
    (cascade_at t2) p2

(* ---------- plant_of / observation_of: the rows' ids, in order ---------- *)

let photo observation_id : Herbier_domain.Photo.t =
  {
    id = Photo_id.fresh ();
    observation_id;
    taken_at = now;
    width = 1;
    height = 1;
    sha256 = "";
    preview_path = "";
    preview_bucket_key = None;
    original_target = App_only;
    drive_file_id = None;
    upload_state = Pending;
    created_at = now;
    updated_at = now;
    deleted_at = None;
  }

let of_rows_tests () =
  let o1 = Fixtures.plant_obs (Some ortie.id)
  and o2 = Fixtures.plant_obs (Some ortie.id) in
  let ph1 = photo o1.id and ph2 = photo o2.id in
  let tag = Herbier_domain.Tag.v ~id:(Fixtures.tag_id ()) ~at:now "haie" in
  let strings to_string = List.map to_string in
  let d =
    Delete_plan.plant_of ortie ~observations:[o1; o2] ~photos:[ph1; ph2]
      ~tags:[tag]
  in
  Alcotest.(check string)
    "plant_of: the plant"
    (Plant_id.to_string ortie.id)
    (Plant_id.to_string d.plant.id);
  Alcotest.(check (list string))
    "plant_of: observation ids"
    (strings Observation_id.to_string [o1.id; o2.id])
    (strings Observation_id.to_string d.observations);
  Alcotest.(check (list string))
    "plant_of: photo ids"
    (strings Photo_id.to_string [ph1.id; ph2.id])
    (strings Photo_id.to_string d.photos);
  Alcotest.(check (list string))
    "plant_of: tag ids"
    (strings Tag_id.to_string [tag.id])
    (strings Tag_id.to_string d.tags);
  let e = Delete_plan.observation_of o1.id ~photos:[ph1] in
  Alcotest.(check string)
    "observation_of: the observation"
    (Observation_id.to_string o1.id)
    (Observation_id.to_string e.observation);
  Alcotest.(check (list string))
    "observation_of: photo ids"
    (strings Photo_id.to_string [ph1.id])
    (strings Photo_id.to_string e.photos)

let delete_plan =
  [
    Alcotest.test_case "plant_of / observation_of keep the rows' ids" `Quick
      of_rows_tests;
    Alcotest.test_case "plant_title: 5a's guillemets around the display name"
      `Quick plant_title_tests;
    Alcotest.test_case
      "plant_text: by observation and photo counts, 0 observations ignores \
       photos"
      `Quick plant_text_tests;
    Alcotest.test_case "plant_text: the tag count changes nothing" `Quick
      plant_text_ignores_tags_tests;
    Alcotest.test_case "plant_action: 5a's footer label by observation count"
      `Quick plant_action_tests;
    Alcotest.test_case "plant_failure is 5a's failure line" `Quick
      plant_failure_tests;
    Alcotest.test_case "observation_title is 4h's title" `Quick
      observation_title_tests;
    Alcotest.test_case "observation_text: by photo count" `Quick
      observation_text_tests;
    Alcotest.test_case "observation_failure is 4h's failure line" `Quick
      observation_failure_tests;
    Alcotest.test_case
      "plant_edits: exactly Cascade.plant's edits, with and without dependents"
      `Quick plant_edits_tests;
    Alcotest.test_case
      "observation_edits: exactly Cascade.observation's edits, with and \
       without photos"
      `Quick observation_edits_tests;
    Alcotest.test_case
      "plant_edits carries the caller's instant, not a fixed one" `Quick
      edits_carry_the_given_at_tests;
  ]
