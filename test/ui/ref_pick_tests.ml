(* Ref_pick: what tapping a reference row does, per entry mode. *)

module Ref_pick = Herbier_ui_model.Ref_pick
module Plant_id = Herbier_domain.Ids.Plant_id
module Plant = Herbier_domain.Plant
module Gbif = Herbier_refs.Sources.Gbif

let utc = Fixtures.utc
let base_plant = Fixtures.base_plant
let digitalis_taxon = Fixtures.digitalis_taxon
let plant_with = Fixtures.plant_with

let action_str = function
  | Ref_pick.Inert -> "Inert"
  | Ref_pick.Open (p : Plant.t) -> "Open " ^ Plant_id.to_string p.id
  | Ref_pick.Attach_to (p : Plant.t) -> "Attach_to " ^ Plant_id.to_string p.id
  | Ref_pick.Create -> "Create"
  | Ref_pick.Link_this -> "Link_this"

let action =
  Alcotest.testable
    (fun f a -> Format.pp_print_string f (action_str a))
    Ref_pick.equal_action

let ref_pick_matching_plant_per_mode () =
  let a = plant_with ~gbif_key:(Some 5414995) () in
  let b = plant_with () in
  Alcotest.(check action)
    "Browse: Open" (Ref_pick.Open a)
    (Ref_pick.action Ref_pick.Browse ~current:None ~plants:[a; b]
       digitalis_taxon);
  Alcotest.(check action)
    "Attach: Attach_to" (Ref_pick.Attach_to a)
    (Ref_pick.action Ref_pick.Attach ~current:None ~plants:[a; b]
       digitalis_taxon);
  Alcotest.(check action)
    "Relink: Link_this" Ref_pick.Link_this
    (Ref_pick.action Ref_pick.Relink ~current:(Some b.id) ~plants:[a; b]
       digitalis_taxon)

let ref_pick_current_is_inert () =
  let a = plant_with ~gbif_key:(Some 5414995) () in
  List.iter
    (fun mode ->
      Alcotest.(check action)
        "Inert" Ref_pick.Inert
        (Ref_pick.action mode ~current:(Some a.id) ~plants:[a] digitalis_taxon))
    [Ref_pick.Browse; Ref_pick.Attach; Ref_pick.Relink]

let ref_pick_no_match () =
  let b = plant_with () in
  Alcotest.(check action)
    "Browse: Create" Ref_pick.Create
    (Ref_pick.action Ref_pick.Browse ~current:None ~plants:[b] digitalis_taxon);
  Alcotest.(check action)
    "Attach: Create" Ref_pick.Create
    (Ref_pick.action Ref_pick.Attach ~current:None ~plants:[b] digitalis_taxon);
  Alcotest.(check action)
    "Relink: Link_this" Ref_pick.Link_this
    (Ref_pick.action Ref_pick.Relink ~current:None ~plants:[b] digitalis_taxon)

let ref_pick_synonym_accepted_key_matches () =
  let a = plant_with ~gbif_key:(Some 5414995) () in
  let synonym =
    {digitalis_taxon with Gbif.Taxon.key = 7971454; accepted_key = Some 5414995}
  in
  Alcotest.(check action)
    "Browse: Open via accepted_key" (Ref_pick.Open a)
    (Ref_pick.action Ref_pick.Browse ~current:None ~plants:[a] synonym)

let ref_pick_deleted_ignored_first_match_wins () =
  let deleted =
    plant_with ~gbif_key:(Some 5414995) ~deleted_at:(Some (utc 2026 1 1 0 0)) ()
  in
  let live = plant_with ~gbif_key:(Some 5414995) () in
  Alcotest.(check action)
    "soft-deleted ignored" (Ref_pick.Open live)
    (Ref_pick.action Ref_pick.Browse ~current:None ~plants:[deleted; live]
       digitalis_taxon);
  let other = plant_with ~gbif_key:(Some 5414995) () in
  Alcotest.(check action)
    "two matches: the first in list order" (Ref_pick.Open live)
    (Ref_pick.action Ref_pick.Browse ~current:None ~plants:[live; other]
       digitalis_taxon)

let ref_pick_other_owner () =
  let a = plant_with ~gbif_key:(Some 5414995) () in
  let b = plant_with ~gbif_key:(Some 5414995) () in
  match
    Ref_pick.other_owner ~current:(Some a.id) ~plants:[a; b] digitalis_taxon
  with
  | Some (p : Plant.t) ->
      Alcotest.(check bool)
        "the other matching plant" true (Plant_id.equal p.id b.id)
  | None -> Alcotest.fail "expected Some"

let ref_pick_other_owner_none () =
  let a = plant_with ~gbif_key:(Some 5414995) () in
  let b = plant_with () in
  Alcotest.(check bool)
    "only the current plant has the species" true
    (Option.is_none
       (Ref_pick.other_owner ~current:(Some a.id) ~plants:[a; b] digitalis_taxon))

let ref_pick =
  [
    Alcotest.test_case
      "action: the matching plant per mode (Open / Attach_to / Link_this)"
      `Quick ref_pick_matching_plant_per_mode;
    Alcotest.test_case "action: current is Inert in every mode" `Quick
      ref_pick_current_is_inert;
    Alcotest.test_case
      "action: no match is Create (Browse / Attach) or Link_this (Relink)"
      `Quick ref_pick_no_match;
    Alcotest.test_case
      "action: a synonym's accepted_key matches the plant's gbif_key" `Quick
      ref_pick_synonym_accepted_key_matches;
    Alcotest.test_case
      "action: a soft-deleted plant is ignored, the first match wins" `Quick
      ref_pick_deleted_ignored_first_match_wins;
    Alcotest.test_case
      "other_owner: the first matching plant that is not current" `Quick
      ref_pick_other_owner;
    Alcotest.test_case "other_owner: None when only the current plant matches"
      `Quick ref_pick_other_owner_none;
  ]
