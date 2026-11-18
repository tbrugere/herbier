(* Herbier_ui_model.Identify.Compare (app/ui_model/identify/compare.ml): 6d
   Comparer as a pure value — which proposal and image are shown, in 6d's
   order (my photos' organs first), which of my photos is on top, ‹ › and
   swipe, and the images to load — plus 6d's French texts (Text). No
   DOM, no network: built directly from the recorded Pl@ntNet fixtures
   (two_flower_leaf: 5 proposals, 6/6/6/6/1 images, proposal 0 organs
   F F F L L L; one_auto: proposal 0 has 6 images, F F F None F F, the
   [None] being its "other" image Pl@ntNet does not offer as an organ). *)

module Identify = Herbier_ui_model.Identify
module Compare = Identify.Compare
module Caller = Identify.Caller
module Owned = Identify.Owned
module Text = Identify.Text
module Plantnet = Herbier_identify.Plantnet
module Proposal = Herbier_identify.Proposal
module Organ = Herbier_identify.Organ
module Fixture = Herbier_test_support.Fixture
module Support_text = Herbier_test_support.Text
module Plant_id = Herbier_domain.Ids.Plant_id

(* ---------- testables ---------- *)

let str s = `String s
let opt f = function None -> `Null | Some v -> f v

let image_json (i : Plantnet.image) =
  `Assoc
    [
      ("organ", opt (fun o -> str (Organ.to_string o)) i.organ);
      ("author", str i.author);
      ("licence", str i.licence);
      ("citation", opt str i.citation);
      ("small", str i.small);
      ("medium", str i.medium);
    ]

let image_t =
  Alcotest.testable
    (fun ppf i ->
      Format.pp_print_string ppf (Yojson.Safe.pretty_to_string (image_json i)))
    Plantnet.equal_image

let images_t = Alcotest.list image_t
let organ_t = Alcotest.testable Organ.pp Organ.equal
let pp_proposal ppf (p : Plantnet.proposal) = Format.pp_print_string ppf p.name
let proposal_t = Alcotest.testable pp_proposal Plantnet.equal_proposal

let pp_t ppf c =
  Format.fprintf ppf
    "{index=%d; count=%d; proposal=%s; image_index=%d; mine_index=%d; \
     to_load=[%a]}"
    (Compare.index c) (Compare.count c) (Compare.proposal c).name
    (Compare.image_index c) (Compare.mine_index c)
    (Format.pp_print_list
       ~pp_sep:(fun f () -> Format.fprintf f ";")
       Format.pp_print_int)
    (Compare.to_load c)

let t_t = Alcotest.testable pp_t Compare.equal

(* ---------- fixtures ---------- *)

let two_flower_leaf = "plantnet_identify_two_flower_leaf_200.json"
let one_auto = "plantnet_identify_one_auto_200.json"

let decode name =
  match Plantnet.decode_answer (Fixture.read name) with
  | Ok a -> a
  | Error e -> Alcotest.failf "decode %s: %s" name (Plantnet.error_to_string e)

let proposals_tfl = (decode two_flower_leaf).Plantnet.proposals
let proposals_auto = (decode one_auto).Plantnet.proposals

let nth what l i =
  match List.nth_opt l i with
  | Some x -> x
  | None -> Alcotest.failf "%s: no index %d in the fixture" what i

let proposal0 = nth "two_flower_leaf proposals" proposals_tfl 0
let mine_both = [Some Organ.Flower; Some Organ.Leaf]

let open_exn ~proposals ~mine ~proposal ~tile =
  match Compare.open_ ~proposals ~mine ~proposal ~tile with
  | Some c -> c
  | None -> Alcotest.fail "expected Some from Compare.open_"

let check_none msg = function
  | None -> ()
  | Some _ -> Alcotest.failf "%s: expected None" msg

let image_at (p : Plantnet.proposal) i = nth p.name p.images i

let rec next_n c n =
  if n <= 0 then c else next_n (Compare.step c Compare.Next) (n - 1)

(* ============================================================ *)
(* Opening: 6d opens only from a species image or « +N » *)
(* ============================================================ *)

let open_basic_tiles () =
  List.iter
    (fun tile ->
      let c =
        open_exn ~proposals:proposals_tfl ~mine:mine_both ~proposal:0 ~tile
      in
      Alcotest.(check int)
        (Printf.sprintf "tile %d: index" tile)
        0 (Compare.index c);
      (match Compare.image c with
      | Some img ->
          Alcotest.(check image_t)
            (Printf.sprintf "tile %d: image" tile)
            (image_at proposal0 tile) img
      | None -> Alcotest.failf "tile %d: expected an image" tile);
      Alcotest.(check int)
        (Printf.sprintf "tile %d: image_index" tile)
        tile (Compare.image_index c))
    [0; 1; 2]

let open_more_tile () =
  let c =
    open_exn ~proposals:proposals_tfl ~mine:mine_both ~proposal:0 ~tile:3
  in
  (match Compare.image c with
  | Some img ->
      Alcotest.(check image_t)
        "+N tile opens on Pl@ntNet index 4" (image_at proposal0 4) img
  | None -> Alcotest.fail "expected an image");
  Alcotest.(check int) "image_index = 4" 4 (Compare.image_index c)

(* With my leaf photo, 6d's order is 3 4 5 0 1 2: « +N » still opens on
   Pl@ntNet image 4, now at position 1. *)
let open_more_tile_reordered () =
  let c =
    open_exn ~proposals:proposals_tfl ~mine:[Some Organ.Leaf] ~proposal:0
      ~tile:3
  in
  Alcotest.(check int) "image_index = 1" 1 (Compare.image_index c);
  match Compare.image c with
  | Some img ->
      Alcotest.(check image_t)
        "+N tile opens on Pl@ntNet index 4" (image_at proposal0 4) img
  | None -> Alcotest.fail "expected an image"

(* Exactly four images: tile 3 is not « +N » and opens on its own image. *)
let open_last_tile_of_four () =
  let four = {proposal0 with Plantnet.images = List.take 4 proposal0.images} in
  let c = open_exn ~proposals:[four] ~mine:mine_both ~proposal:0 ~tile:3 in
  Alcotest.(check int) "image_index = 3" 3 (Compare.image_index c);
  match Compare.image c with
  | Some img ->
      Alcotest.(check image_t)
        "tile 3 opens on Pl@ntNet index 3" (image_at proposal0 3) img
  | None -> Alcotest.fail "expected an image"

let open_single_image_proposal () =
  let c =
    open_exn ~proposals:proposals_tfl ~mine:mine_both ~proposal:4 ~tile:0
  in
  Alcotest.(check int) "index = 4" 4 (Compare.index c);
  Alcotest.(check int) "image_index = 0" 0 (Compare.image_index c);
  List.iter
    (fun tile ->
      check_none
        (Printf.sprintf "proposal 4, tile %d" tile)
        (Compare.open_ ~proposals:proposals_tfl ~mine:mine_both ~proposal:4
           ~tile))
    [1; 3]

let open_out_of_range () =
  check_none "tile -1"
    (Compare.open_ ~proposals:proposals_tfl ~mine:mine_both ~proposal:0
       ~tile:(-1));
  check_none "tile 4"
    (Compare.open_ ~proposals:proposals_tfl ~mine:mine_both ~proposal:0 ~tile:4);
  check_none "proposal 5"
    (Compare.open_ ~proposals:proposals_tfl ~mine:mine_both ~proposal:5 ~tile:0);
  check_none "proposal -1"
    (Compare.open_ ~proposals:proposals_tfl ~mine:mine_both ~proposal:(-1)
       ~tile:0);
  check_none "mine = []"
    (Compare.open_ ~proposals:proposals_tfl ~mine:[] ~proposal:0 ~tile:0);
  check_none "proposals = []"
    (Compare.open_ ~proposals:[] ~mine:mine_both ~proposal:0 ~tile:0)

let open_empty_images_proposal () =
  let empty = {proposal0 with Plantnet.images = []} in
  List.iter
    (fun tile ->
      check_none
        (Printf.sprintf "no images, tile %d" tile)
        (Compare.open_ ~proposals:[empty] ~mine:mine_both ~proposal:0 ~tile))
    [0; 1; 2; 3]

let open_reorders_entry () =
  let c =
    open_exn ~proposals:proposals_tfl ~mine:[Some Organ.Leaf] ~proposal:0
      ~tile:0
  in
  Alcotest.(check int)
    "image_index = 3 (leaves first)" 3 (Compare.image_index c);
  match Compare.image c with
  | Some img ->
      Alcotest.(check image_t)
        "image is Pl@ntNet image 0 (the tapped flower)" (image_at proposal0 0)
        img
  | None -> Alcotest.fail "expected an image"

let opening_tests =
  [
    Alcotest.test_case "open_: tiles 0, 1, 2 open on their own Pl@ntNet image"
      `Quick open_basic_tiles;
    Alcotest.test_case
      "open_: the « +N » tile (tile 3, more > 0) opens on the first image 6c \
       does not show"
      `Quick open_more_tile;
    Alcotest.test_case
      "open_: « +N » opens on Pl@ntNet image 4 at its reordered position" `Quick
      open_more_tile_reordered;
    Alcotest.test_case
      "open_: with exactly four images, tile 3 opens on its own image" `Quick
      open_last_tile_of_four;
    Alcotest.test_case
      "open_: a one-image proposal opens on tile 0 only, other tiles None"
      `Quick open_single_image_proposal;
    Alcotest.test_case
      "open_: out-of-range tile or proposal, mine = [] or proposals = [] all \
       give None"
      `Quick open_out_of_range;
    Alcotest.test_case "open_: a proposal without images never opens" `Quick
      open_empty_images_proposal;
    Alcotest.test_case
      "open_: the entry image is the tapped Pl@ntNet image, at its reordered \
       position"
      `Quick open_reorders_entry;
  ]

(* ============================================================ *)
(* Swipe and ‹ ›: move as 6d's note says *)
(* ============================================================ *)

let shown_clamps () =
  let c0 =
    open_exn ~proposals:proposals_tfl ~mine:mine_both ~proposal:0 ~tile:0
  in
  let c4 = Compare.step c0 (Compare.Shown 4) in
  Alcotest.(check int) "Shown 4: image_index" 4 (Compare.image_index c4);
  Alcotest.(check int) "Shown 4: index unchanged" 0 (Compare.index c4);
  let c99 = Compare.step c0 (Compare.Shown 99) in
  Alcotest.(check int)
    "Shown 99: clamped to the last image" 5 (Compare.image_index c99);
  let cneg = Compare.step c0 (Compare.Shown (-2)) in
  Alcotest.(check int) "Shown -2: clamped to 0" 0 (Compare.image_index cneg)

let next_previous_reset_image () =
  let c0 =
    open_exn ~proposals:proposals_tfl ~mine:mine_both ~proposal:0 ~tile:0
  in
  let c4 = Compare.step c0 (Compare.Shown 4) in
  let cn = Compare.step c4 Compare.Next in
  Alcotest.(check int) "Next: index" 1 (Compare.index cn);
  Alcotest.(check int) "Next: image_index reset to 0" 0 (Compare.image_index cn);
  let cp = Compare.step cn Compare.Previous in
  Alcotest.(check int) "Previous: index" 0 (Compare.index cp);
  Alcotest.(check int)
    "Previous: image_index not restored to 4" 0 (Compare.image_index cp)

let bounds_unchanged_and_can_flags () =
  let c0 =
    open_exn ~proposals:proposals_tfl ~mine:mine_both ~proposal:0 ~tile:0
  in
  let cprev = Compare.step c0 Compare.Previous in
  Alcotest.(check t_t) "Previous at the first proposal: unchanged" c0 cprev;
  let c4 = next_n c0 4 in
  Alcotest.(check int) "proposal 4 reached" 4 (Compare.index c4);
  let cnext = Compare.step c4 Compare.Next in
  Alcotest.(check t_t) "Next at the last proposal: unchanged" c4 cnext;
  let c2 = next_n c0 2 in
  Alcotest.(check (Alcotest.pair bool bool))
    "can_previous/can_next at 0" (false, true)
    (Compare.can_previous c0, Compare.can_next c0);
  Alcotest.(check (Alcotest.pair bool bool))
    "can_previous/can_next at 2" (true, true)
    (Compare.can_previous c2, Compare.can_next c2);
  Alcotest.(check (Alcotest.pair bool bool))
    "can_previous/can_next at 4" (true, false)
    (Compare.can_previous c4, Compare.can_next c4)

let single_image_proposal_via_next () =
  let c0 =
    open_exn ~proposals:proposals_tfl ~mine:mine_both ~proposal:0 ~tile:0
  in
  let c4 = next_n c0 4 in
  Alcotest.(check int) "images length 1" 1 (List.length (Compare.images c4));
  let c4' = Compare.step c4 (Compare.Shown 3) in
  Alcotest.(check int) "Shown 3 clamps to 0" 0 (Compare.image_index c4')

let empty_images_proposal_reachable_by_next () =
  let empty = {(nth "proposals" proposals_tfl 1) with Plantnet.images = []} in
  let proposals =
    [nth "proposals" proposals_tfl 0; empty; nth "proposals" proposals_tfl 2]
  in
  let c0 = open_exn ~proposals ~mine:mine_both ~proposal:0 ~tile:0 in
  let c1 = Compare.step c0 Compare.Next in
  Alcotest.(check int) "index = 1" 1 (Compare.index c1);
  Alcotest.(check images_t) "images = []" [] (Compare.images c1);
  Alcotest.(check (Alcotest.option image_t))
    "image = None" None (Compare.image c1);
  Alcotest.(check int) "image_index = 0" 0 (Compare.image_index c1);
  Alcotest.(check (Alcotest.list Alcotest.int))
    "to_load = []" [] (Compare.to_load c1);
  let c1' = Compare.step c1 (Compare.Shown 2) in
  Alcotest.(check int)
    "Shown 2: image_index stays 0" 0 (Compare.image_index c1')

let count_and_proposal_accessor () =
  let c0 =
    open_exn ~proposals:proposals_tfl ~mine:mine_both ~proposal:0 ~tile:0
  in
  Alcotest.(check int) "count = 5" 5 (Compare.count c0);
  List.iter
    (fun i ->
      let c = next_n c0 i in
      Alcotest.(check proposal_t)
        (Printf.sprintf "proposal at index %d" i)
        (nth "proposals" proposals_tfl i)
        (Compare.proposal c))
    [0; 1; 2; 3; 4]

let swipe_tests =
  [
    Alcotest.test_case "Shown: becomes the image, clamped to the image range"
      `Quick shown_clamps;
    Alcotest.test_case
      "Next/Previous: change the proposal and reset the image to 0 (not \
       restored)"
      `Quick next_previous_reset_image;
    Alcotest.test_case
      "Previous at the first / Next at the last proposal: unchanged; \
       can_previous/can_next at the ends and in the middle"
      `Quick bounds_unchanged_and_can_flags;
    Alcotest.test_case
      "a one-image proposal reached by Next: images length 1, Shown clamps to 0"
      `Quick single_image_proposal_via_next;
    Alcotest.test_case
      "a proposal without images stays reachable by Next: no image, no \
       to_load, Shown has no effect"
      `Quick empty_images_proposal_reachable_by_next;
    Alcotest.test_case "count is the proposal count; proposal is List.nth"
      `Quick count_and_proposal_accessor;
  ]

(* ============================================================ *)
(* My photo on top *)
(* ============================================================ *)

let mine_on_top_two_organs () =
  let c0 =
    open_exn ~proposals:proposals_tfl ~mine:mine_both ~proposal:0 ~tile:0
  in
  Alcotest.(check int)
    "on a flower image: mine_index = 0" 0 (Compare.mine_index c0);
  Alcotest.(check (Alcotest.option organ_t))
    "on a flower image: mine_organ = Some Flower" (Some Organ.Flower)
    (Compare.mine_organ c0);
  let c3 = Compare.step c0 (Compare.Shown 3) in
  Alcotest.(check int)
    "on a leaf image: mine_index = 1" 1 (Compare.mine_index c3);
  Alcotest.(check (Alcotest.option organ_t))
    "mine_organ = Some Leaf" (Some Organ.Leaf) (Compare.mine_organ c3)

let mine_on_top_fallback_and_no_organ () =
  let mine = [None; Some Organ.Leaf] in
  (* mine's only distinct organ is Leaf, so display_order puts the three leaf
     images first (position 0): same reordering as ~mine:[Some Leaf]. *)
  let c0 = open_exn ~proposals:proposals_tfl ~mine ~proposal:0 ~tile:0 in
  Alcotest.(check int)
    "on a flower image, no photo matches: fallback to 0" 0
    (Compare.mine_index c0);
  let c_leaf = Compare.step c0 (Compare.Shown 0) in
  Alcotest.(check int)
    "on a leaf image: mine_index = 1" 1
    (Compare.mine_index c_leaf);
  let co = open_exn ~proposals:proposals_auto ~mine ~proposal:0 ~tile:0 in
  let co' = Compare.step co (Compare.Shown 3) in
  (match Compare.image co' with
  | Some img ->
      Alcotest.(check (Alcotest.option organ_t)) "organ is None" None img.organ
  | None -> Alcotest.fail "expected the \"other\" image");
  Alcotest.(check int)
    "an image of organ None: fallback to 0" 0 (Compare.mine_index co')

(* Two photos of the same organ: the first one is on top. *)
let mine_on_top_repeated_organ () =
  let c =
    open_exn ~proposals:proposals_tfl
      ~mine:[Some Organ.Leaf; Some Organ.Flower; Some Organ.Flower]
      ~proposal:0 ~tile:0
  in
  (match Compare.image c with
  | Some img ->
      Alcotest.(check (Alcotest.option organ_t))
        "a flower image" (Some Organ.Flower) img.organ
  | None -> Alcotest.fail "expected an image");
  Alcotest.(check int)
    "the first flower photo: mine_index = 1" 1 (Compare.mine_index c);
  Alcotest.(check (Alcotest.option organ_t))
    "mine_organ = Some Flower" (Some Organ.Flower) (Compare.mine_organ c);
  let c' =
    open_exn ~proposals:proposals_tfl
      ~mine:[Some Organ.Leaf; Some Organ.Flower; Some Organ.Leaf]
      ~proposal:0 ~tile:0
  in
  let leaf = Compare.step c' (Compare.Shown 0) in
  (match Compare.image leaf with
  | Some img ->
      Alcotest.(check (Alcotest.option organ_t))
        "a leaf image" (Some Organ.Leaf) img.organ
  | None -> Alcotest.fail "expected an image");
  Alcotest.(check int)
    "the first leaf photo, not the last: mine_index = 0" 0
    (Compare.mine_index leaf)

let mine_on_top_tests =
  [
    Alcotest.test_case
      "with two of my photos' organs: mine_index and mine_organ follow the \
       shown image's organ"
      `Quick mine_on_top_two_organs;
    Alcotest.test_case
      "no match (a None entry or an image of organ None) falls back to 0" `Quick
      mine_on_top_fallback_and_no_organ;
    Alcotest.test_case "two of my photos of one organ: the first one is on top"
      `Quick mine_on_top_repeated_organ;
  ]

(* ============================================================ *)
(* Loading *)
(* ============================================================ *)

let to_load_tests_fn () =
  let c0 =
    open_exn ~proposals:proposals_tfl ~mine:mine_both ~proposal:0 ~tile:0
  in
  Alcotest.(check (Alcotest.list Alcotest.int))
    "image 0 of 6" [0; 1] (Compare.to_load c0);
  let c3 = Compare.step c0 (Compare.Shown 3) in
  Alcotest.(check (Alcotest.list Alcotest.int))
    "image 3 of 6" [2; 3; 4] (Compare.to_load c3);
  let c5 = Compare.step c0 (Compare.Shown 5) in
  Alcotest.(check (Alcotest.list Alcotest.int))
    "image 5 of 6 (last)" [4; 5] (Compare.to_load c5);
  let c4 = next_n c0 4 in
  Alcotest.(check (Alcotest.list Alcotest.int))
    "a one-image proposal" [0] (Compare.to_load c4)

let loading_tests =
  [
    Alcotest.test_case
      "to_load: the shown image and its existing neighbours, ascending" `Quick
      to_load_tests_fn;
  ]

(* ============================================================ *)
(* Every image's credit text has its author and licence, none dropped (the
   rendering is a device check) *)
(* ============================================================ *)

let credit_covers_every_image () =
  let check_fixture name proposals =
    List.iteri
      (fun i (p : Plantnet.proposal) ->
        List.iter
          (fun (img : Plantnet.image) ->
            let credit = Proposal.credit img in
            Alcotest.(check bool)
              (Printf.sprintf "%s proposal %d: credit has the author" name i)
              true
              (Support_text.contains ~sub:img.author credit);
            Alcotest.(check bool)
              (Printf.sprintf "%s proposal %d: credit has the licence label"
                 name i)
              true
              (Support_text.contains
                 ~sub:(Proposal.licence_label img.licence)
                 credit);
            Alcotest.(check bool)
              (Printf.sprintf "%s proposal %d: credit ends with Pl@ntNet" name i)
              true
              (String.ends_with ~suffix:"· Pl@ntNet" credit))
          p.images;
        let c = open_exn ~proposals ~mine:[None] ~proposal:i ~tile:0 in
        Alcotest.(check int)
          (Printf.sprintf "%s proposal %d: no image dropped by 6d" name i)
          (List.length p.images)
          (List.length (Compare.images c)))
      proposals
  in
  check_fixture "two_flower_leaf" proposals_tfl;
  check_fixture "one_auto" proposals_auto

let credit_tests =
  [
    Alcotest.test_case
      "every image of every proposal of both fixtures has an author and a \
       licence in its credit; images is never shorter than Pl@ntNet's list"
      `Quick credit_covers_every_image;
  ]

(* ============================================================ *)
(* Text: 6d's French strings *)
(* ============================================================ *)

let flower_image0 = image_at proposal0 0

let tile_label_tests () =
  Alcotest.(check string)
    "organ Some Flower, more 0" "Comparer : Hibiscus rosa-sinensis, fleur"
    (Text.tile_label proposal0 flower_image0 ~more:0);
  Alcotest.(check string)
    "organ None, more 0" "Comparer : Hibiscus rosa-sinensis"
    (Text.tile_label proposal0 {flower_image0 with organ = None} ~more:0);
  Alcotest.(check string)
    "more 2 (\"+2\")" "Comparer : Hibiscus rosa-sinensis, 2 photos de plus"
    (Text.tile_label proposal0 flower_image0 ~more:2);
  Alcotest.(check string)
    "more 1 (singular)" "Comparer : Hibiscus rosa-sinensis, 1 photo de plus"
    (Text.tile_label proposal0 flower_image0 ~more:1)

let compare_simple_texts () =
  Alcotest.(check string)
    "compare_close" "Fermer la comparaison" Text.compare_close;
  Alcotest.(check string)
    "compare_position" "Proposition 1 / 5"
    (Text.compare_position ~index:1 ~count:5);
  Alcotest.(check string)
    "compare_mine Some Flower" "Ma photo · fleur"
    (Text.compare_mine (Some Organ.Flower));
  Alcotest.(check string)
    "compare_mine None" "Ma photo" (Text.compare_mine None);
  Alcotest.(check string)
    "compare_species Some Leaf" "Pl@ntNet · feuille"
    (Text.compare_species (Some Organ.Leaf));
  Alcotest.(check string)
    "compare_species None" "Pl@ntNet"
    (Text.compare_species None);
  Alcotest.(check string)
    "compare_image_position" "3 / 6"
    (Text.compare_image_position ~index:3 ~count:6);
  Alcotest.(check string)
    "compare_previous" "Proposition précédente" Text.compare_previous;
  Alcotest.(check string)
    "compare_next" "Proposition suivante" Text.compare_next;
  Alcotest.(check string)
    "compare_no_image" "Pl@ntNet n'a pas envoyé de photo de cette espèce."
    Text.compare_no_image

let compare_names_tests () =
  Alcotest.(check (Alcotest.option Alcotest.string))
    "names and family" (Some "Rose de Chine · Malvaceae")
    (Text.compare_names proposal0);
  Alcotest.(check (Alcotest.option Alcotest.string))
    "names only" (Some "Rose de Chine")
    (Text.compare_names {proposal0 with family = None});
  Alcotest.(check (Alcotest.option Alcotest.string))
    "family only" (Some "Malvaceae")
    (Text.compare_names {proposal0 with common_names = []});
  Alcotest.(check (Alcotest.option Alcotest.string))
    "neither" None
    (Text.compare_names {proposal0 with family = None; common_names = []})

(* compare_owned is checked per caller in identify_tests.ml. *)
let compare_action_tests () =
  Alcotest.(check string)
    "compare_action Choose" "Choisir cette espèce"
    (Text.compare_action Caller.Choose);
  Alcotest.(check string)
    "compare_action Link" "Lier"
    (Text.compare_action Caller.Link);
  Alcotest.(check string)
    "compare_action Create" "+ Créer"
    (Text.compare_action Caller.Create)

let text_tests =
  [
    Alcotest.test_case
      "tile_label: organ or its absence, \"+N\" singular/plural" `Quick
      tile_label_tests;
    Alcotest.test_case
      "compare_close, compare_position, compare_mine, compare_species, \
       compare_image_position, compare_previous/next, compare_no_image: exact \
       strings"
      `Quick compare_simple_texts;
    Alcotest.test_case
      "compare_names: names and family joined, either alone, neither -> None"
      `Quick compare_names_tests;
    Alcotest.test_case "compare_action per caller action" `Quick
      compare_action_tests;
  ]

(* ============================================================ *)

let identify_compare =
  List.concat
    [
      opening_tests;
      swipe_tests;
      mine_on_top_tests;
      loading_tests;
      credit_tests;
      text_tests;
    ]
