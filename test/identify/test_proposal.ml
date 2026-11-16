(* Herbier_identify.Proposal: the four closest images and
   « +N », same organ first, licence labels and credits, and the uncertain
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
let organ = Alcotest.testable Organ.pp Organ.equal
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

(* ---------- same_organ_first ---------- *)

let is_leaf (i : Plantnet.image) =
  match i.organ with Some o -> Organ.equal o Organ.Leaf | None -> false

let same_organ_first_tests =
  [
    ( "mine = Some Leaf: the leaf images first, then the others, each group in \
       original order",
      `Quick,
      fun () ->
        let first, _ = first_and_fifth () in
        let leaves, others = List.partition is_leaf first.Plantnet.images in
        let reordered =
          Proposal.same_organ_first ~mine:(Some Organ.Leaf)
            first.Plantnet.images
        in
        Alcotest.(check (list (option organ)))
          "three leaves, then three flowers"
          [
            Some Organ.Leaf;
            Some Organ.Leaf;
            Some Organ.Leaf;
            Some Organ.Flower;
            Some Organ.Flower;
            Some Organ.Flower;
          ]
          (List.map (fun (i : Plantnet.image) -> i.organ) reordered);
        Alcotest.(check images)
          "same_organ_first ~mine:(Some Leaf)" (leaves @ others) reordered );
    ( "mine = Some Flower: the flower images are already first, unchanged",
      `Quick,
      fun () ->
        let first, _ = first_and_fifth () in
        Alcotest.(check images)
          "same_organ_first ~mine:(Some Flower)" first.Plantnet.images
          (Proposal.same_organ_first ~mine:(Some Organ.Flower)
             first.Plantnet.images) );
    ( "mine = None: unchanged",
      `Quick,
      fun () ->
        let first, _ = first_and_fifth () in
        Alcotest.(check images)
          "same_organ_first ~mine:None" first.Plantnet.images
          (Proposal.same_organ_first ~mine:None first.Plantnet.images) );
    ( "an image whose organ is None never matches: last after the flowers",
      `Quick,
      fun () ->
        match (decode one_auto).Plantnet.proposals with
        | first :: _ ->
            let flowers, others =
              List.partition
                (fun (i : Plantnet.image) ->
                  Option.equal Organ.equal i.organ (Some Organ.Flower))
                first.images
            in
            let reordered =
              Proposal.same_organ_first ~mine:(Some Organ.Flower) first.images
            in
            Alcotest.(check (list (option organ)))
              "five flowers, then the \"other\" image"
              [
                Some Organ.Flower;
                Some Organ.Flower;
                Some Organ.Flower;
                Some Organ.Flower;
                Some Organ.Flower;
                None;
              ]
              (List.map (fun (i : Plantnet.image) -> i.organ) reordered);
            Alcotest.(check images) "stable" (flowers @ others) reordered
        | [] -> Alcotest.fail "no proposals" );
    ( "mine = Some Fruit, matching no image: unchanged",
      `Quick,
      fun () ->
        let first, _ = first_and_fifth () in
        Alcotest.(check images)
          "same_organ_first ~mine:(Some Fruit)" first.Plantnet.images
          (Proposal.same_organ_first ~mine:(Some Organ.Fruit)
             first.Plantnet.images) );
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

let suites =
  [
    ("proposal closest / more / more_label", closest_more_tests);
    ("proposal same_organ_first", same_organ_first_tests);
    ("proposal licence_label", licence_label_tests);
    ("proposal credit", credit_tests);
    ("proposal uncertain", uncertain_tests);
  ]
