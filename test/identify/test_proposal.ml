(* Herbier_identify.Proposal: the four closest images and
   « +N », 6d's display order, licence labels and credits, and the uncertain
   rule, over two_flower_leaf_200 and one_auto_200 decoded. *)

module Plantnet = Herbier_identify.Plantnet
module Proposal = Herbier_identify.Proposal
module Organ = Herbier_identify.Organ
module Fixture = Herbier_test_support.Fixture

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

let image =
  Alcotest.testable
    (fun ppf i ->
      Format.pp_print_string ppf (Yojson.Safe.pretty_to_string (image_json i)))
    Plantnet.equal_image

let images = Alcotest.list image
let two_flower_leaf = "plantnet_identify_two_flower_leaf_200.json"
let one_auto = "plantnet_identify_one_auto_200.json"

let decode name =
  match Plantnet.decode_answer (Fixture.read name) with
  | Ok a -> a
  | Error e ->
      Alcotest.failf "decode_answer %s: %s" name (Plantnet.error_to_string e)

(* The first (6 images) and fifth (1 image) proposals of two_flower_leaf_200,
   as pinned by test_plantnet.ml's decode_answer tests. *)
let first_and_fifth () =
  match (decode two_flower_leaf).Plantnet.proposals with
  | [first; _; _; _; fifth] -> (first, fifth)
  | proposals ->
      Alcotest.failf "expected exactly 5 proposals, got %d"
        (List.length proposals)

(* ---------- closest / more / more_label ---------- *)

let closest_more_tests =
  [
    ( "closest is the first four images, in order",
      `Quick,
      fun () ->
        let first, _ = first_and_fifth () in
        match first.Plantnet.images with
        | i1 :: i2 :: i3 :: i4 :: _ ->
            Alcotest.(check images)
              "closest" [i1; i2; i3; i4] (Proposal.closest first)
        | _ -> Alcotest.fail "expected at least 4 images" );
    ( "more is the count of images beyond the first four",
      `Quick,
      fun () ->
        let first, _ = first_and_fifth () in
        Alcotest.(check int) "more" 2 (Proposal.more first) );
    ( "more_label is \"+N\" when more > 0",
      `Quick,
      fun () ->
        let first, _ = first_and_fifth () in
        Alcotest.(check (option string))
          "more_label" (Some "+2")
          (Proposal.more_label first) );
    ( "a proposal with one image: closest is that image, no more",
      `Quick,
      fun () ->
        let _, fifth = first_and_fifth () in
        Alcotest.(check images)
          "closest" fifth.Plantnet.images (Proposal.closest fifth);
        Alcotest.(check int) "more" 0 (Proposal.more fifth);
        Alcotest.(check (option string))
          "more_label" None
          (Proposal.more_label fifth) );
  ]

(* ---------- tile_more ---------- *)

let tile_more_tests =
  [
    ( "6 images: the last tile is « +2 », the others 0",
      `Quick,
      fun () ->
        let first, _ = first_and_fifth () in
        Alcotest.(check (list int))
          "tile_more 0..3" [0; 0; 0; 2]
          (List.init Proposal.tiles (Proposal.tile_more first)) );
    ( "exactly 4 images: no « +N » tile",
      `Quick,
      fun () ->
        let first, _ = first_and_fifth () in
        let four =
          {first with Plantnet.images = List.take 4 first.Plantnet.images}
        in
        Alcotest.(check (list int))
          "tile_more 0..3" [0; 0; 0; 0]
          (List.init Proposal.tiles (Proposal.tile_more four)) );
  ]

(* ---------- licence_label ---------- *)

let licence_label_tests =
  [
    ( "cc-by-sa becomes CC BY-SA",
      `Quick,
      fun () ->
        Alcotest.(check string)
          "licence_label" "CC BY-SA"
          (Proposal.licence_label "cc-by-sa") );
    ( "cc-by becomes CC BY",
      `Quick,
      fun () ->
        Alcotest.(check string)
          "licence_label" "CC BY"
          (Proposal.licence_label "cc-by") );
    ( "CC-BY-NC (case-insensitive) becomes CC BY-NC",
      `Quick,
      fun () ->
        Alcotest.(check string)
          "licence_label" "CC BY-NC"
          (Proposal.licence_label "CC-BY-NC") );
    ( "cc0 becomes CC0",
      `Quick,
      fun () ->
        Alcotest.(check string)
          "licence_label" "CC0"
          (Proposal.licence_label "cc0") );
    ( "anything else is trimmed, as sent",
      `Quick,
      fun () ->
        Alcotest.(check string)
          "licence_label" "public domain"
          (Proposal.licence_label "  public domain ") );
    ( " cc-by-sa  is trimmed before the cc- rule",
      `Quick,
      fun () ->
        Alcotest.(check string)
          "licence_label" "CC BY-SA"
          (Proposal.licence_label " cc-by-sa ") );
    ( "a bare cc- is kept as sent, no dangling space",
      `Quick,
      fun () ->
        Alcotest.(check string)
          "licence_label" "cc-"
          (Proposal.licence_label "cc- ") );
  ]

(* ---------- credit ---------- *)

let credit_tests =
  [
    ( "credit of the first image: author, licence label, Pl@ntNet",
      `Quick,
      fun () ->
        let first, _ = first_and_fifth () in
        match first.Plantnet.images with
        | first_image :: _ ->
            Alcotest.(check string)
              "credit" "© Daniel Mardare · CC BY-SA · Pl@ntNet"
              (Proposal.credit first_image)
        | [] -> Alcotest.fail "no images" );
  ]

(* ---------- uncertain ---------- *)

let uncertain_tests =
  [
    ( "one_auto_200 is uncertain (0.44239 < min_best)",
      `Quick,
      fun () ->
        let a = decode one_auto in
        Alcotest.(check bool)
          "uncertain" true
          (Proposal.uncertain a.Plantnet.proposals) );
    ( "two_flower_leaf_200 is not uncertain (0.52853, lead 0.509)",
      `Quick,
      fun () ->
        let a = decode two_flower_leaf in
        Alcotest.(check bool)
          "uncertain" false
          (Proposal.uncertain a.Plantnet.proposals) );
    ( "built proposals, score only varied",
      `Quick,
      fun () ->
        let base, _ = first_and_fifth () in
        let with_scores scores =
          List.map (fun score -> {base with Plantnet.score}) scores
        in
        let check msg scores expected =
          Alcotest.(check bool)
            msg expected
            (Proposal.uncertain (with_scores scores))
        in
        check "[0.9; 0.8]: lead 0.1 < min_lead" [0.9; 0.8] true;
        check "[0.9; 0.7]: lead 0.2 >= min_lead" [0.9; 0.7] false;
        check "[0.75; 0.6]: lead exactly min_lead, not below" [0.75; 0.6] false;
        check "[0.6; 0.45]: lead exactly min_lead despite binary rounding"
          [0.6; 0.45] false;
        check "[0.6; 0.45001]: lead just below min_lead" [0.6; 0.45001] true;
        check "[0.49]: below min_best" [0.49] true;
        check "[0.5]: at min_best, not below" [0.5] false;
        check "[0.6]: above min_best, no second" [0.6] false;
        check "[]: nothing to be sure of" [] true;
        check "[0.2; 0.9]: Pl@ntNet's order, first taken as best" [0.2; 0.9]
          true );
  ]

(* ---------- display_order ---------- *)

let display_order_identity_tests =
  [
    ( "mine = []: identity",
      `Quick,
      fun () ->
        let first, _ = first_and_fifth () in
        Alcotest.(check (list int))
          "display_order ~mine:[]"
          (List.init (List.length first.Plantnet.images) (fun i -> i))
          (Proposal.display_order ~mine:[] first.Plantnet.images) );
    ( "mine = [None]: identity",
      `Quick,
      fun () ->
        let first, _ = first_and_fifth () in
        Alcotest.(check (list int))
          "display_order ~mine:[None]"
          (List.init (List.length first.Plantnet.images) (fun i -> i))
          (Proposal.display_order ~mine:[None] first.Plantnet.images) );
    ( "[] images -> []",
      `Quick,
      fun () ->
        Alcotest.(check (list int))
          "display_order ~mine:[] []" []
          (Proposal.display_order ~mine:[] []) );
  ]

let display_order_grouping_tests =
  [
    ( "mine:[Some Leaf] on F F F L L L -> leaves then flowers",
      `Quick,
      fun () ->
        let first, _ = first_and_fifth () in
        Alcotest.(check (list int))
          "display_order" [3; 4; 5; 0; 1; 2]
          (Proposal.display_order ~mine:[Some Organ.Leaf] first.Plantnet.images)
    );
    ( "mine:[Some Flower; Some Leaf]: already grouped, identity",
      `Quick,
      fun () ->
        let first, _ = first_and_fifth () in
        Alcotest.(check (list int))
          "display_order" [0; 1; 2; 3; 4; 5]
          (Proposal.display_order
             ~mine:[Some Organ.Flower; Some Organ.Leaf]
             first.Plantnet.images) );
    ( "mine:[Some Leaf; Some Flower]: the leaves' group still comes first",
      `Quick,
      fun () ->
        let first, _ = first_and_fifth () in
        Alcotest.(check (list int))
          "display_order" [3; 4; 5; 0; 1; 2]
          (Proposal.display_order
             ~mine:[Some Organ.Leaf; Some Organ.Flower]
             first.Plantnet.images) );
    ( "mine:[Some Flower] on F F F L L L: the flowers already first, identity",
      `Quick,
      fun () ->
        let first, _ = first_and_fifth () in
        Alcotest.(check (list int))
          "display_order" [0; 1; 2; 3; 4; 5]
          (Proposal.display_order ~mine:[Some Organ.Flower]
             first.Plantnet.images) );
    ( "mine:[Some Fruit], matching no image: identity",
      `Quick,
      fun () ->
        let first, _ = first_and_fifth () in
        Alcotest.(check (list int))
          "display_order" [0; 1; 2; 3; 4; 5]
          (Proposal.display_order ~mine:[Some Organ.Fruit] first.Plantnet.images)
    );
  ]

(* Proposal 1's images relabelled Fruit, Leaf, Flower, Fruit, Leaf, Flower:
   three organs, so the second organ of [mine] has a group of its own between
   the first one's and the others. *)
let three_organs () =
  let first, _ = first_and_fifth () in
  let organs = Organ.[Fruit; Leaf; Flower; Fruit; Leaf; Flower] in
  List.map2
    (fun (i : Plantnet.image) o -> {i with organ = Some o})
    first.Plantnet.images organs

let display_order_three_organs_tests =
  [
    ( "mine:[Some Leaf; Some Flower] on Fr L F Fr L F: leaves, flowers, then \
       fruits",
      `Quick,
      fun () ->
        Alcotest.(check (list int))
          "display_order" [1; 4; 2; 5; 0; 3]
          (Proposal.display_order
             ~mine:[Some Organ.Leaf; Some Organ.Flower]
             (three_organs ())) );
    ( "mine:[Some Flower; None; Some Leaf] on Fr L F Fr L F: flowers, leaves, \
       then fruits",
      `Quick,
      fun () ->
        Alcotest.(check (list int))
          "display_order" [2; 5; 1; 4; 0; 3]
          (Proposal.display_order
             ~mine:[Some Organ.Flower; None; Some Organ.Leaf]
             (three_organs ())) );
  ]

let display_order_skips_repeats_and_nones_tests =
  [
    ( "None and repeats in mine are skipped: same as [Some Leaf]",
      `Quick,
      fun () ->
        let first, _ = first_and_fifth () in
        Alcotest.(check (list int))
          "display_order ~mine:[None; Some Leaf; Some Leaf]"
          (Proposal.display_order ~mine:[Some Organ.Leaf] first.Plantnet.images)
          (Proposal.display_order
             ~mine:[None; Some Organ.Leaf; Some Organ.Leaf]
             first.Plantnet.images) );
  ]

let display_order_none_organ_never_matches_tests =
  [
    ( "one_auto proposal 1's \"other\" image (organ None, Pl@ntNet index 3) \
       never moves forward",
      `Quick,
      fun () ->
        match (decode one_auto).Plantnet.proposals with
        | first :: _ ->
            Alcotest.(check (list int))
              "display_order ~mine:[Some Flower]" [0; 1; 2; 4; 5; 3]
              (Proposal.display_order ~mine:[Some Organ.Flower] first.images)
        | [] -> Alcotest.fail "no proposals" );
  ]

let all_proposals () =
  (decode two_flower_leaf).Plantnet.proposals
  @ (decode one_auto).Plantnet.proposals

let display_order_is_always_a_permutation_tests =
  [
    ( "display_order is a permutation of [0 .. n-1] for every proposal of both \
       fixtures and every mine",
      `Quick,
      fun () ->
        let mines =
          [[]; [Some Organ.Leaf; Some Organ.Flower]]
          @ List.map (fun o -> [Some o]) Organ.all
        in
        List.iter
          (fun (p : Plantnet.proposal) ->
            List.iter
              (fun mine ->
                let order = Proposal.display_order ~mine p.images in
                Alcotest.(check (list int))
                  (Printf.sprintf "permutation of %d images"
                     (List.length p.images))
                  (List.init (List.length p.images) (fun i -> i))
                  (List.sort compare order))
              mines)
          (all_proposals ()) );
  ]

let suites =
  [
    ("proposal closest / more / more_label", closest_more_tests);
    ("proposal tile_more", tile_more_tests);
    ("proposal licence_label", licence_label_tests);
    ("proposal credit", credit_tests);
    ("proposal uncertain", uncertain_tests);
    ("proposal display_order: identity cases", display_order_identity_tests);
    ( "proposal display_order: grouping by mine's first distinct organs",
      display_order_grouping_tests );
    ( "proposal display_order: three organs, two of them mine",
      display_order_three_organs_tests );
    ( "proposal display_order: None and repeats in mine are skipped",
      display_order_skips_repeats_and_nones_tests );
    ( "proposal display_order: an image with organ = None never matches",
      display_order_none_organ_never_matches_tests );
    ( "proposal display_order: always a permutation",
      display_order_is_always_a_permutation_tests );
  ]
