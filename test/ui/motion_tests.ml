(* Herbier_ui_model.Motion: which transition a route change gets. *)

module Motion = Herbier_ui_model.Motion
module Plant_id = Herbier_domain.Ids.Plant_id
module Value = Herbier_test_support.Value

let p = Value.id "plant" Plant_id.of_string (Value.uuid7 1)
let q = Value.id "plant" Plant_id.of_string (Value.uuid7 2)

(* ---------- testables ---------- *)

let plant_id =
  Alcotest.testable
    (fun fmt id -> Format.pp_print_string fmt (Plant_id.to_string id))
    Plant_id.equal

let string_of_kind = function
  | Motion.Instant -> "Instant"
  | Motion.Fade -> "Fade"
  | Motion.Modal_in -> "Modal_in"
  | Motion.Modal_out -> "Modal_out"
  | Motion.Hero_in id -> Printf.sprintf "Hero_in %s" (Plant_id.to_string id)
  | Motion.Hero_out id -> Printf.sprintf "Hero_out %s" (Plant_id.to_string id)

let kind =
  Alcotest.testable
    (fun fmt k -> Format.pp_print_string fmt (string_of_kind k))
    Motion.equal_kind

let string_of_direction = function
  | Motion.Forward -> "Forward"
  | Motion.Back -> "Back"
  | Motion.Replace -> "Replace"
  | Motion.Unknown -> "Unknown"

let direction =
  Alcotest.testable
    (fun fmt d -> Format.pp_print_string fmt (string_of_direction d))
    Motion.equal_direction

let string_of_how = function
  | Motion.Now -> "Now"
  | Motion.Css_fade -> "Css_fade"
  | Motion.View -> "View"

let how =
  Alcotest.testable
    (fun fmt h -> Format.pp_print_string fmt (string_of_how h))
    Motion.equal_how

(* ---------- direction ---------- *)

let direction_tests =
  [
    Alcotest.test_case "before 3 after 4 is Forward" `Quick (fun () ->
        Alcotest.check direction "direction" Motion.Forward
          (Motion.direction ~before:(Some 3) ~after:(Some 4)));
    Alcotest.test_case "before 4 after 3 is Back" `Quick (fun () ->
        Alcotest.check direction "direction" Motion.Back
          (Motion.direction ~before:(Some 4) ~after:(Some 3)));
    Alcotest.test_case "before 5 after 1 is Back (any distance)" `Quick
      (fun () ->
        Alcotest.check direction "direction" Motion.Back
          (Motion.direction ~before:(Some 5) ~after:(Some 1)));
    Alcotest.test_case "before 2 after 2 is Replace" `Quick (fun () ->
        Alcotest.check direction "direction" Motion.Replace
          (Motion.direction ~before:(Some 2) ~after:(Some 2)));
    Alcotest.test_case "before None is Unknown" `Quick (fun () ->
        Alcotest.check direction "direction" Motion.Unknown
          (Motion.direction ~before:None ~after:(Some 2)));
    Alcotest.test_case "after None is Unknown" `Quick (fun () ->
        Alcotest.check direction "direction" Motion.Unknown
          (Motion.direction ~before:(Some 2) ~after:None));
    Alcotest.test_case "both None is Unknown" `Quick (fun () ->
        Alcotest.check direction "direction" Motion.Unknown
          (Motion.direction ~before:None ~after:None));
  ]

(* ---------- kind ---------- *)

let dirs = [Motion.Forward; Motion.Back; Motion.Replace; Motion.Unknown]

(* [kind_cases title from to_ expect]: one test case per direction in [dirs],
   checking [Motion.kind ~from ~to_ dir] against [expect dir]. *)
let kind_cases title from to_ expect =
  List.map
    (fun dir ->
      Alcotest.test_case
        (Printf.sprintf "%s: %s" title (string_of_direction dir))
        `Quick
        (fun () ->
          Alcotest.check kind "kind" (expect dir) (Motion.kind ~from ~to_ dir)))
    dirs

let always k _dir = k

let kind_tests =
  List.concat
    [
      kind_cases "Dev -> Tab is Instant" Motion.Dev Motion.Tab
        (always Motion.Instant);
      kind_cases "Collection -> Dev is Instant" Motion.Collection Motion.Dev
        (always Motion.Instant);
      kind_cases "Dev -> Dev is Instant" Motion.Dev Motion.Dev
        (always Motion.Instant);
      kind_cases "Dev -> Fiche p is Instant" Motion.Dev (Motion.Fiche p)
        (always Motion.Instant);
      kind_cases "Modal -> Dev is Instant" Motion.Modal Motion.Dev
        (always Motion.Instant);
      kind_cases "Collection -> Tab is Instant" Motion.Collection Motion.Tab
        (always Motion.Instant);
      kind_cases "Tab -> Collection is Instant" Motion.Tab Motion.Collection
        (always Motion.Instant);
      kind_cases "Tab -> Tab is Instant" Motion.Tab Motion.Tab
        (always Motion.Instant);
      kind_cases "Collection -> Fiche p" Motion.Collection (Motion.Fiche p)
        (function
        | Motion.Back -> Motion.Fade
        | Motion.Forward | Motion.Replace | Motion.Unknown -> Motion.Hero_in p);
      kind_cases "Fiche p -> Collection" (Motion.Fiche p) Motion.Collection
        (always (Motion.Hero_out p));
      kind_cases "Fiche q -> Collection" (Motion.Fiche q) Motion.Collection
        (always (Motion.Hero_out q));
      kind_cases "Tab -> Fiche p is not a hero" Motion.Tab (Motion.Fiche p)
        (function
        | Motion.Back -> Motion.Fade
        | Motion.Forward | Motion.Replace | Motion.Unknown -> Motion.Modal_in);
      kind_cases "Collection -> Modal" Motion.Collection Motion.Modal (function
        | Motion.Back -> Motion.Fade
        | Motion.Forward | Motion.Replace | Motion.Unknown -> Motion.Modal_in);
      kind_cases "Tab -> Modal" Motion.Tab Motion.Modal (function
        | Motion.Back -> Motion.Fade
        | Motion.Forward | Motion.Replace | Motion.Unknown -> Motion.Modal_in);
      kind_cases "Modal -> Collection" Motion.Modal Motion.Collection
        (always Motion.Modal_out);
      kind_cases "Modal -> Tab" Motion.Modal Motion.Tab
        (always Motion.Modal_out);
      kind_cases "Fiche p -> Tab" (Motion.Fiche p) Motion.Tab
        (always Motion.Modal_out);
      kind_cases "Modal -> Modal" Motion.Modal Motion.Modal (function
        | Motion.Forward -> Motion.Modal_in
        | Motion.Back -> Motion.Modal_out
        | Motion.Replace | Motion.Unknown -> Motion.Fade);
      kind_cases "Fiche p -> Modal" (Motion.Fiche p) Motion.Modal (function
        | Motion.Forward -> Motion.Modal_in
        | Motion.Back -> Motion.Modal_out
        | Motion.Replace | Motion.Unknown -> Motion.Fade);
      kind_cases "Modal -> Fiche p" Motion.Modal (Motion.Fiche p) (function
        | Motion.Forward -> Motion.Modal_in
        | Motion.Back -> Motion.Modal_out
        | Motion.Replace | Motion.Unknown -> Motion.Fade);
      kind_cases "Fiche p -> Fiche q" (Motion.Fiche p) (Motion.Fiche q)
        (function
        | Motion.Forward -> Motion.Modal_in
        | Motion.Back -> Motion.Modal_out
        | Motion.Replace | Motion.Unknown -> Motion.Fade);
    ]

(* ---------- without_hero ---------- *)

let without_hero_tests =
  [
    Alcotest.test_case "Hero_in p becomes Modal_in" `Quick (fun () ->
        Alcotest.check kind "without_hero" Motion.Modal_in
          (Motion.without_hero (Motion.Hero_in p)));
    Alcotest.test_case "Hero_out p becomes Modal_out" `Quick (fun () ->
        Alcotest.check kind "without_hero" Motion.Modal_out
          (Motion.without_hero (Motion.Hero_out p)));
    Alcotest.test_case "every other kind is unchanged" `Quick (fun () ->
        List.iter
          (fun k ->
            Alcotest.check kind (string_of_kind k) k (Motion.without_hero k))
          [Motion.Instant; Motion.Fade; Motion.Modal_in; Motion.Modal_out]);
  ]

(* ---------- how ---------- *)

let how_tests =
  [
    Alcotest.test_case "reduced motion forces Now for every kind" `Quick
      (fun () ->
        List.iter
          (fun k ->
            List.iter
              (fun supported ->
                Alcotest.check how
                  (Printf.sprintf "%s, supported=%b" (string_of_kind k)
                     supported)
                  Motion.Now
                  (Motion.how ~supported ~reduced:true k))
              [true; false])
          [
            Motion.Instant;
            Motion.Fade;
            Motion.Modal_in;
            Motion.Modal_out;
            Motion.Hero_in p;
            Motion.Hero_out q;
          ]);
    Alcotest.test_case "Instant is always Now" `Quick (fun () ->
        List.iter
          (fun supported ->
            Alcotest.check how
              (Printf.sprintf "supported=%b" supported)
              Motion.Now
              (Motion.how ~supported ~reduced:false Motion.Instant))
          [true; false]);
    Alcotest.test_case "unsupported falls back to Css_fade" `Quick (fun () ->
        List.iter
          (fun k ->
            Alcotest.check how (string_of_kind k) Motion.Css_fade
              (Motion.how ~supported:false ~reduced:false k))
          [
            Motion.Fade;
            Motion.Modal_in;
            Motion.Modal_out;
            Motion.Hero_in p;
            Motion.Hero_out q;
          ]);
    Alcotest.test_case "supported, not reduced, runs the kind through View"
      `Quick (fun () ->
        List.iter
          (fun k ->
            Alcotest.check how (string_of_kind k) Motion.View
              (Motion.how ~supported:true ~reduced:false k))
          [
            Motion.Fade;
            Motion.Modal_in;
            Motion.Modal_out;
            Motion.Hero_in p;
            Motion.Hero_out q;
          ]);
  ]

(* ---------- attribute, hero, ready_cap_ms ---------- *)

let string_option = Alcotest.option Alcotest.string
let plant_id_option = Alcotest.option plant_id

let attribute_hero_tests =
  [
    Alcotest.test_case
      "attribute: one value per animated kind, None for Instant" `Quick
      (fun () ->
        Alcotest.check string_option "Instant" None
          (Motion.attribute Motion.Instant);
        Alcotest.check string_option "Fade" (Some "fade")
          (Motion.attribute Motion.Fade);
        Alcotest.check string_option "Modal_in" (Some "modal-in")
          (Motion.attribute Motion.Modal_in);
        Alcotest.check string_option "Modal_out" (Some "modal-out")
          (Motion.attribute Motion.Modal_out);
        Alcotest.check string_option "Hero_in" (Some "hero-in")
          (Motion.attribute (Motion.Hero_in p));
        Alcotest.check string_option "Hero_out" (Some "hero-out")
          (Motion.attribute (Motion.Hero_out p)));
    Alcotest.test_case "hero: Some the plant for Hero_in/Hero_out, else None"
      `Quick (fun () ->
        Alcotest.check plant_id_option "Hero_in p" (Some p)
          (Motion.hero (Motion.Hero_in p));
        Alcotest.check plant_id_option "Hero_out q" (Some q)
          (Motion.hero (Motion.Hero_out q));
        List.iter
          (fun k ->
            Alcotest.check plant_id_option (string_of_kind k) None
              (Motion.hero k))
          [Motion.Instant; Motion.Fade; Motion.Modal_in; Motion.Modal_out]);
    Alcotest.test_case "ready_cap_ms is 300" `Quick (fun () ->
        Alcotest.(check int) "ready_cap_ms" 300 Motion.ready_cap_ms);
  ]

(* ---------- in_view (viewport_height 800) ---------- *)

let in_view_tests =
  let viewport_height = 800. in
  let in_view top bottom = Motion.in_view ~viewport_height ~top ~bottom in
  [
    Alcotest.test_case "fully or partly on screen is true" `Quick (fun () ->
        Alcotest.(check bool) "top -50 bottom 100" true (in_view (-50.) 100.);
        Alcotest.(check bool) "top 700 bottom 900" true (in_view 700. 900.);
        Alcotest.(check bool) "top 100 bottom 300" true (in_view 100. 300.);
        Alcotest.(check bool)
          "top -100 bottom 900 (taller than the viewport)" true
          (in_view (-100.) 900.));
    Alcotest.test_case "off screen, including touching an edge, is false" `Quick
      (fun () ->
        Alcotest.(check bool)
          "top -300 bottom 0 (touches the top edge)" false (in_view (-300.) 0.);
        Alcotest.(check bool)
          "top 800 bottom 1000 (touches the bottom edge)" false
          (in_view 800. 1000.);
        Alcotest.(check bool)
          "top -300 bottom -10 (above the viewport)" false
          (in_view (-300.) (-10.)));
  ]

let motion =
  List.concat
    [
      direction_tests;
      kind_tests;
      without_hero_tests;
      how_tests;
      attribute_hero_tests;
      in_view_tests;
    ]
