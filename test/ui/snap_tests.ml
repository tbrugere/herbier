(* Snap: where a released sheet settles, over the dev page's points. *)

module Snap = Herbier_ui_model.Snap

let snaps = Snap.of_list [72.; 360.; 640.]

let settles name ~at ~speed ~rest_ms expected =
  Alcotest.test_case name `Quick (fun () ->
      Alcotest.(check int)
        "index" expected
        (Snap.release snaps ~at ~speed ~rest_ms))

let raises name l =
  Alcotest.test_case name `Quick (fun () ->
      match Snap.of_list l with
      | (_ : float array) -> Alcotest.fail "accepted"
      | exception Invalid_argument _ -> ())

let snap =
  [
    Alcotest.test_case "one point" `Quick (fun () ->
        Alcotest.(check int) "index" 0 (Snap.nearest [|100.|] 900.));
    Alcotest.test_case "tie takes the lower" `Quick (fun () ->
        Alcotest.(check int) "index" 0 (Snap.nearest snaps 216.));
    Alcotest.test_case "clamp" `Quick (fun () ->
        Alcotest.(check (float 0.)) "low" 72. (Snap.clamp snaps 10.);
        Alcotest.(check (float 0.)) "high" 640. (Snap.clamp snaps 700.);
        Alcotest.(check (float 0.)) "inside" 300. (Snap.clamp snaps 300.));
    settles "slow release between two points" ~at:250. ~speed:0. ~rest_ms:0. 1;
    settles "slow release near the bottom" ~at:200. ~speed:0. ~rest_ms:0. 0;
    settles "flick up one point" ~at:200. ~speed:1. ~rest_ms:10. 1;
    settles "flick down one point" ~at:300. ~speed:(-1.) ~rest_ms:10. 0;
    settles "fast flick passes a point" ~at:100. ~speed:3. ~rest_ms:10. 2;
    settles "flick past the top" ~at:600. ~speed:5. ~rest_ms:10. 2;
    settles "flick past the bottom" ~at:100. ~speed:(-5.) ~rest_ms:10. 0;
    settles "rested flick projects nothing" ~at:200. ~speed:3. ~rest_ms:200. 0;
    raises "no point" [];
    raises "descending" [360.; 72.];
    raises "repeated" [72.; 72.];
  ]
