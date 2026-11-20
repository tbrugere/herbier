(* Herbier_ui_model.System_bars: which surface (Light/Dark) each system bar
   is drawn under, from the route, the open overlays and the offline
   banner, and which of those two bars changed between two values. *)

module System_bars = Herbier_ui_model.System_bars

(* ---------- testables ---------- *)

let surface = Alcotest.testable System_bars.pp_surface System_bars.equal_surface
let bar = Alcotest.testable System_bars.pp_bar System_bars.equal_bar
let t = Alcotest.testable System_bars.pp System_bars.equal
let change = Alcotest.pair bar surface
let change_list = Alcotest.list change
let mk status navigation : System_bars.t = {System_bars.status; navigation}

(* ---------- resolve ---------- *)

let resolve_tests =
  let open System_bars in
  [
    Alcotest.test_case "route Light, no overlays, no banner: tabs" `Quick
      (fun () ->
        Alcotest.check t "resolve" (mk Light Light)
          (resolve ~route:Light ~overlays:[] ~offline_banner:false));
    Alcotest.test_case "route Dark, no overlays, no banner: 4d or 5e" `Quick
      (fun () ->
        Alcotest.check t "resolve" (mk Dark Dark)
          (resolve ~route:Dark ~overlays:[] ~offline_banner:false));
    Alcotest.test_case "route Dark under a Light overlay: 6c over 4d" `Quick
      (fun () ->
        Alcotest.check t "resolve" (mk Light Light)
          (resolve ~route:Dark ~overlays:[Light] ~offline_banner:false));
    Alcotest.test_case
      "route Dark under Dark then Light overlays: 6d over 6c over 4d, or 4d's \
       viewfinder over 6c"
      `Quick (fun () ->
        Alcotest.check t "resolve" (mk Dark Dark)
          (resolve ~route:Dark ~overlays:[Dark; Light] ~offline_banner:false));
    Alcotest.test_case
      "route Light under Dark then Light overlays: 6d over 6c over 4k/4g" `Quick
      (fun () ->
        Alcotest.check t "resolve" (mk Dark Dark)
          (resolve ~route:Light ~overlays:[Dark; Light] ~offline_banner:false));
    Alcotest.test_case "offline banner over a Light route forces status Dark"
      `Quick (fun () ->
        Alcotest.check t "resolve" (mk Dark Light)
          (resolve ~route:Light ~overlays:[] ~offline_banner:true));
    Alcotest.test_case
      "offline banner over a Dark route: both bars already Dark" `Quick
      (fun () ->
        Alcotest.check t "resolve" (mk Dark Dark)
          (resolve ~route:Dark ~overlays:[] ~offline_banner:true));
    Alcotest.test_case
      "offline banner with a Light overlay on top: status Dark, navigation \
       follows the overlay"
      `Quick (fun () ->
        Alcotest.check t "resolve" (mk Dark Light)
          (resolve ~route:Dark ~overlays:[Light] ~offline_banner:true));
    Alcotest.test_case
      "offline banner with a Dark overlay on a Light route: navigation follows \
       the overlay"
      `Quick (fun () ->
        Alcotest.check t "resolve" (mk Dark Dark)
          (resolve ~route:Light ~overlays:[Dark] ~offline_banner:true));
    Alcotest.test_case
      "only the head of the overlay stack counts, not the ones under it" `Quick
      (fun () ->
        Alcotest.check t "resolve (head Light, Dark under it)" (mk Light Light)
          (resolve ~route:Light ~overlays:[Light; Dark] ~offline_banner:false);
        Alcotest.check t "resolve (head Light over a Dark route, Dark under)"
          (mk Light Light)
          (resolve ~route:Dark ~overlays:[Light; Dark] ~offline_banner:false));
  ]

(* ---------- changes ---------- *)

let all_t =
  let open System_bars in
  [mk Light Light; mk Light Dark; mk Dark Light; mk Dark Dark]

let changes_tests =
  let open System_bars in
  [
    Alcotest.test_case "no previous: both bars, status first (Light both)" `Quick
      (fun () ->
        Alcotest.check change_list "changes"
          [(Status, Light); (Navigation, Light)]
          (changes ~previous:None (mk Light Light)));
    Alcotest.test_case "no previous: both bars, status first (mixed)" `Quick
      (fun () ->
        Alcotest.check change_list "changes"
          [(Status, Dark); (Navigation, Light)]
          (changes ~previous:None (mk Dark Light)));
    Alcotest.test_case "same value as the previous one: no change" `Quick
      (fun () ->
        List.iter
          (fun v ->
            Alcotest.check change_list (System_bars.show v) []
              (changes ~previous:(Some v) v))
          all_t);
    Alcotest.test_case "status alone changes" `Quick (fun () ->
        Alcotest.check change_list "changes"
          [(Status, Dark)]
          (changes ~previous:(Some (mk Light Light)) (mk Dark Light)));
    Alcotest.test_case "navigation alone changes" `Quick (fun () ->
        Alcotest.check change_list "changes"
          [(Navigation, Dark)]
          (changes ~previous:(Some (mk Light Light)) (mk Light Dark)));
    Alcotest.test_case "both change: status first" `Quick (fun () ->
        Alcotest.check change_list "changes"
          [(Status, Dark); (Navigation, Dark)]
          (changes ~previous:(Some (mk Light Light)) (mk Dark Dark)));
  ]

let tests = resolve_tests @ changes_tests
