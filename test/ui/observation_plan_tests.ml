(* Herbier_ui_model.Observation_plan: 4h's arrival (toast, auto-open of the
   identification layer), its Identifier button's line, and what a chosen
   proposal writes (shared with 4k's 6j). *)

module Observation_plan = Herbier_ui_model.Observation_plan
module Identify = Herbier_ui_model.Identify
module Caller = Identify.Caller
module Choice = Identify.Choice
module Record_plan = Herbier_ui_model.Record_plan
module To_identify = Herbier_ui_model.To_identify
module Is = Herbier_ui_model.Identify_settings
module Plant_link = Herbier_ui_model.Plant_link
module Plant = Herbier_domain.Plant
module Plant_id = Herbier_domain.Ids.Plant_id
module Observation = Herbier_domain.Observation
module Gbif = Herbier_refs.Sources.Gbif
module Plantnet = Herbier_identify.Plantnet
module Fixture = Herbier_test_support.Fixture

let utc = Fixtures.utc
let plant_id = Fixtures.plant_id

(* ---------- testables ---------- *)

let pp_write fmt = function
  | Observation_plan.Attach id ->
      Format.fprintf fmt "Attach %s" (Plant_id.to_string id)
  | Observation_plan.Create_free p ->
      Format.fprintf fmt "Create_free %a" Plant.pp p
  | Observation_plan.Create_linked {plant; taxon} ->
      Format.fprintf fmt "Create_linked {plant = %a; taxon = %a}" Plant.pp plant
        Gbif.Taxon.pp taxon

let write_t = Alcotest.testable pp_write Observation_plan.equal_write
let write_opt_t = Alcotest.option write_t

(* ---------- shared values ---------- *)

let now = utc 2026 11 20 10 0

let base_plant name : Plant.t =
  {
    id = plant_id ();
    display_name = name;
    aliases = [];
    scientific_name = None;
    authorship = None;
    gbif_key = None;
    notes = "";
    notes_updated_at = None;
    cover_photo_id = None;
    created_at = now;
    updated_at = now;
    deleted_at = None;
  }

let obs ?plant () : Observation.t =
  {
    id = Herbier_domain.Ids.Observation_id.fresh ();
    plant_id = plant;
    at = now;
    position = None;
    place_label = None;
    place_derived = None;
    place_detail = None;
    note = None;
    created_at = now;
    updated_at = now;
    deleted_at = None;
  }

let ready_key () =
  match Is.Key.of_input "abcdefgh" with
  | Some k -> k
  | None -> Alcotest.fail "Key.of_input \"abcdefgh\" should be a key"

let ready () = Is.Ready (ready_key ())
let all_gates () = [ready (); Is.Waiting; Is.No_key; Is.Offline]

let gate_name = function
  | Is.Ready _ -> "Ready"
  | Is.Waiting -> "Waiting"
  | Is.No_key -> "No_key"
  | Is.Offline -> "Offline"

(* ---------- toast ---------- *)

let toast_tests () =
  let rose = base_plant "Rose" in
  Alcotest.(check (option string))
    "Opened, Some plant -> None" None
    (Observation_plan.toast Observation_plan.Opened ~layer:false (Some rose));
  Alcotest.(check (option string))
    "Opened, None -> None" None
    (Observation_plan.toast Observation_plan.Opened ~layer:false None);
  let recorded = Observation_plan.Recorded {identify = false} in
  Alcotest.(check (option string))
    "Recorded, Some Rose -> \"Enregistrée · ajoutée à Rose\""
    (Some "Enregistr\xc3\xa9e \xc2\xb7 ajout\xc3\xa9e \xc3\xa0 Rose")
    (Observation_plan.toast recorded ~layer:false (Some rose));
  Alcotest.(check (option string))
    "Recorded, None -> \"Enregistrée · à identifier\""
    (Some "Enregistr\xc3\xa9e \xc2\xb7 \xc3\xa0 identifier")
    (Observation_plan.toast recorded ~layer:false None);
  List.iter
    (fun identify ->
      Alcotest.(check (option string))
        (Printf.sprintf "Recorded {identify = %b}, layer:true -> None" identify)
        None
        (Observation_plan.toast
           (Observation_plan.Recorded {identify})
           ~layer:true (Some rose)))
    [true; false];
  let due = Observation_plan.Recorded {identify = true} in
  Alcotest.(check (option string))
    "Recorded {identify = true}, the layer did not open, Some Rose -> the toast"
    (Some "Enregistr\xc3\xa9e \xc2\xb7 ajout\xc3\xa9e \xc3\xa0 Rose")
    (Observation_plan.toast due ~layer:false (Some rose));
  Alcotest.(check (option string))
    "Recorded {identify = true}, the layer did not open, None -> the toast"
    (Some "Enregistr\xc3\xa9e \xc2\xb7 \xc3\xa0 identifier")
    (Observation_plan.toast due ~layer:false None);
  Alcotest.(check int) "toast_ms = 2500" 2500 Observation_plan.toast_ms

(* ---------- opens_layer ---------- *)

let opens_layer_tests () =
  let key = ready_key () in
  let unidentified = obs () and identified = obs ~plant:(plant_id ()) () in
  let recorded_true = Observation_plan.Recorded {identify = true} in
  Alcotest.(check bool)
    "every condition met -> true" true
    (Observation_plan.opens_layer recorded_true unidentified (Is.Ready key)
       ~photos:1);
  Alcotest.(check bool)
    "identify = false -> false" false
    (Observation_plan.opens_layer
       (Observation_plan.Recorded {identify = false})
       unidentified (Is.Ready key) ~photos:1);
  Alcotest.(check bool)
    "arrival Opened -> false" false
    (Observation_plan.opens_layer Observation_plan.Opened unidentified
       (Is.Ready key) ~photos:1);
  Alcotest.(check bool)
    "plant_id = Some _ (already identified) -> false" false
    (Observation_plan.opens_layer recorded_true identified (Is.Ready key)
       ~photos:1);
  List.iter
    (fun gate ->
      Alcotest.(check bool)
        (Printf.sprintf "gate %s -> false" (gate_name gate))
        false
        (Observation_plan.opens_layer recorded_true unidentified gate ~photos:1))
    [Is.Offline; Is.No_key; Is.Waiting];
  Alcotest.(check bool)
    "photos = 0 -> false" false
    (Observation_plan.opens_layer recorded_true unidentified (Is.Ready key)
       ~photos:0)

(* ---------- identifiable ---------- *)

let identifiable_tests () =
  Alcotest.(check bool)
    "plant_id = None -> true" true
    (Observation_plan.identifiable (obs ()));
  Alcotest.(check bool)
    "plant_id = Some _ -> false" false
    (Observation_plan.identifiable (obs ~plant:(plant_id ()) ()))

(* ---------- identify_line ---------- *)

let identify_line_tests () =
  List.iter
    (fun gate ->
      Alcotest.(check (option string))
        (Printf.sprintf "%s, 0 photos -> no_photo_line" (gate_name gate))
        (Some To_identify.no_photo_line)
        (Observation_plan.identify_line gate ~photos:0))
    (all_gates ());
  Alcotest.(check (option string))
    "Offline, 2 photos -> Some offline_line" (Some To_identify.offline_line)
    (Observation_plan.identify_line Is.Offline ~photos:2);
  Alcotest.(check (option string))
    "No_key, 2 photos -> None (no key line on 4h, unlike 6i)" None
    (Observation_plan.identify_line Is.No_key ~photos:2);
  Alcotest.(check (option string))
    "Ready, 2 photos -> None" None
    (Observation_plan.identify_line (Is.Ready (ready_key ())) ~photos:2);
  Alcotest.(check (option string))
    "Waiting, 2 photos -> None" None
    (Observation_plan.identify_line Is.Waiting ~photos:2)

(* ---------- caller, labels ---------- *)

let caller_and_labels_tests () =
  Alcotest.(check bool)
    "Caller.action Observation ~owned:true = Link" true
    (Caller.equal_action
       (Caller.action Caller.Observation ~owned:true)
       Caller.Link);
  Alcotest.(check bool)
    "Caller.action Observation ~owned:false = Create" true
    (Caller.equal_action
       (Caller.action Caller.Observation ~owned:false)
       Caller.Create);
  Alcotest.(check string)
    "by_name_label" "Par le nom" Observation_plan.by_name_label;
  Alcotest.(check string)
    "map_label" "Corriger la position sur la carte" Observation_plan.map_label

(* ---------- write (literal cases) ---------- *)

let digitalis_taxon : Gbif.Taxon.t =
  {
    key = 5414995;
    scientific_name = "Digitalis purpurea L.";
    canonical_name = Some "Digitalis purpurea";
    authorship = Some "L.";
    rank = Some "SPECIES";
    status = Some Gbif.Status.Accepted;
    accepted_key = None;
    family = Some "Plantaginaceae";
    vernacular_name = Some "Foxglove";
  }

let write_literal_tests () =
  let new_plant = Plant_id.fresh () in
  let existing = base_plant "Arnica" in
  Alcotest.(check write_opt_t)
    "Target (Existing p) -> Some (Attach p.id)"
    (Some (Observation_plan.Attach existing.id))
    (Observation_plan.write ~at:now ~new_plant
       (Record_plan.Target (Record_plan.Existing existing)));
  Alcotest.(check write_opt_t)
    "Target (Free \"Rose?\") -> Some (Create_free (Plant.v ~id ~at \"Rose?\"))"
    (Some (Observation_plan.Create_free (Plant.v ~id:new_plant ~at:now "Rose?")))
    (Observation_plan.write ~at:now ~new_plant
       (Record_plan.Target (Record_plan.Free "Rose?")));
  Alcotest.(check write_opt_t)
    "Linked {name; taxon} -> Some (Create_linked {plant = Plant_link.create \
     ...; taxon})"
    (Some
       (Observation_plan.Create_linked
          {
            plant =
              Plant_link.create ~id:new_plant ~at:now ~name:"Digitale pourpre"
                digitalis_taxon;
            taxon = digitalis_taxon;
          }))
    (Observation_plan.write ~at:now ~new_plant
       (Record_plan.Linked {name = "Digitale pourpre"; taxon = digitalis_taxon}));
  Alcotest.(check write_opt_t)
    "Target To_identify -> None" None
    (Observation_plan.write ~at:now ~new_plant
       (Record_plan.Target Record_plan.To_identify))

(* ---------- write, through Record_plan.of_choice over a recorded fixture
   ---------- *)

let decode name =
  match Plantnet.decode_answer (Fixture.read name) with
  | Ok a -> a
  | Error e -> Alcotest.failf "decode %s: %s" name (Plantnet.error_to_string e)

let uncertain_answer = lazy (decode "plantnet_identify_one_auto_200.json")

let nth n =
  match List.nth_opt (Lazy.force uncertain_answer).proposals n with
  | Some p -> p
  | None ->
      Alcotest.failf "plantnet_identify_one_auto_200.json has no proposal %d" n

(* P1: Hibiscus rosa-sinensis L., gbif 3152559, "Rose de Chine" first (as
   record_plan_tests.ml). *)
let p1 = lazy (nth 0)

(* P4: "Hibiscus spp." (genus-level), gbif null, "Hibiscus commun" first (as
   record_plan_tests.ml). *)
let p4 = lazy (nth 3)

let write_via_of_choice_tests () =
  let new_plant = Plant_id.fresh () in
  let write choice = Observation_plan.write ~at:now ~new_plant choice in
  let p1 = Lazy.force p1 in
  let owner = {(base_plant "Ma plante") with gbif_key = Some 3152559} in
  Alcotest.(check write_opt_t)
    "owned gbif key -> Attach owner.id"
    (Some (Observation_plan.Attach owner.id))
    (write (Record_plan.of_choice ~plants:[owner] (Choice.v p1)));
  Alcotest.(check write_opt_t)
    "Resolved, not owned -> Create_linked with that taxon"
    (Some
       (Observation_plan.Create_linked
          {
            plant =
              Plant_link.create ~id:new_plant ~at:now ~name:"Rose de Chine"
                digitalis_taxon;
            taxon = digitalis_taxon;
          }))
    (write
       (Record_plan.of_choice ~plants:[]
          (Choice.resolved (Choice.v p1) (Choice.Resolved digitalis_taxon))));
  let p4 = Lazy.force p4 in
  Alcotest.(check write_opt_t)
    "Unknown, no match -> Create_free \"Hibiscus commun\""
    (Some
       (Observation_plan.Create_free
          (Plant.v ~id:new_plant ~at:now "Hibiscus commun")))
    (write
       (Record_plan.of_choice ~plants:[]
          (Choice.resolved (Choice.v p4) Choice.Unknown)));
  let hibiscus = base_plant "hibiscus Commun" in
  Alcotest.(check write_opt_t)
    "Unknown, a plant named Hibiscus Commun -> Attach it"
    (Some (Observation_plan.Attach hibiscus.id))
    (write
       (Record_plan.of_choice ~plants:[hibiscus]
          (Choice.resolved (Choice.v p4) Choice.Unknown)))

let plant_id_t = Alcotest.testable Plant_id.pp Plant_id.equal

let plant_of_tests () =
  let new_plant = Plant_id.fresh () in
  let existing = base_plant "Arnica" in
  Alcotest.(check plant_id_t)
    "Attach id -> id" existing.id
    (Observation_plan.plant_of (Observation_plan.Attach existing.id));
  Alcotest.(check plant_id_t)
    "Create_free p -> p.id" new_plant
    (Observation_plan.plant_of
       (Observation_plan.Create_free (Plant.v ~id:new_plant ~at:now "Rose?")));
  Alcotest.(check plant_id_t)
    "Create_linked {plant = p; _} -> p.id" new_plant
    (Observation_plan.plant_of
       (Observation_plan.Create_linked
          {
            plant =
              Plant_link.create ~id:new_plant ~at:now ~name:"Digitale pourpre"
                digitalis_taxon;
            taxon = digitalis_taxon;
          }))

let chosen_tests () =
  let new_plant = Plant_id.fresh () in
  let p1 = Lazy.force p1 in
  let owner = {(base_plant "Ma plante") with gbif_key = Some 3152559} in
  Alcotest.(check write_opt_t)
    "owned gbif key -> Attach owner.id"
    (Some (Observation_plan.Attach owner.id))
    (Observation_plan.chosen ~at:now ~new_plant ~plants:[owner] (Choice.v p1));
  Alcotest.(check string)
    "no_name" "Cette proposition n'a pas de nom." Observation_plan.no_name

let observation_plan =
  [
    Alcotest.test_case
      "toast: Opened -> None; Recorded with/without a plant; the layer already \
       open -> None; toast_ms"
      `Quick toast_tests;
    Alcotest.test_case
      "opens_layer: true only when every condition holds, false for each one \
       broken"
      `Quick opens_layer_tests;
    Alcotest.test_case "identifiable: None -> true, Some _ -> false" `Quick
      identifiable_tests;
    Alcotest.test_case
      "identify_line: no-photo line first, then offline, nothing for No_key \
       (unlike 6i), Ready or Waiting"
      `Quick identify_line_tests;
    Alcotest.test_case "Caller.Observation's actions; by_name_label, map_label"
      `Quick caller_and_labels_tests;
    Alcotest.test_case
      "write: Existing -> Attach, Free -> Create_free, Linked -> \
       Create_linked, To_identify -> None"
      `Quick write_literal_tests;
    Alcotest.test_case
      "write through Record_plan.of_choice over a recorded Pl@ntNet proposal"
      `Quick write_via_of_choice_tests;
    Alcotest.test_case "plant_of: Attach's id, the new plant's id for Create_*"
      `Quick plant_of_tests;
    Alcotest.test_case "chosen: of_choice then write; no_name" `Quick
      chosen_tests;
  ]
