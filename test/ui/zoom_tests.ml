module Zoom = Herbier_ui_model.Zoom

let zoom =
  let w = 400. and h = 800. in
  let z =
    Alcotest.testable
      (fun f (t : Zoom.t) -> Format.fprintf f "{%g %g %g}" t.scale t.x t.y)
      (fun (a : Zoom.t) b ->
        Float.abs (a.scale -. b.scale) < 1e-9
        && Float.abs (a.x -. b.x) < 1e-9
        && Float.abs (a.y -. b.y) < 1e-9)
  in
  [
    Alcotest.test_case "about keeps the point still" `Quick (fun () ->
        Alcotest.check z "x2 at (100,200)"
          {scale = 2.; x = -100.; y = -200.}
          (Zoom.about ~w ~h Zoom.identity ~cx:100. ~cy:200. ~ratio:2.);
        let t = {Zoom.scale = 2.; x = -100.; y = -200.} in
        let t' = Zoom.about ~w ~h t ~cx:300. ~cy:100. ~ratio:1.5 in
        Alcotest.check z "x1.5 from x2 at (300,100)"
          {scale = 3.; x = -300.; y = -350.}
          t';
        (* the content point under (300, 100) stays under it *)
        Alcotest.(check (float 1e-9))
          "fixed"
          ((300. -. t.x) /. t.scale)
          ((300. -. t'.x) /. t'.scale));
    Alcotest.test_case "clamped scale and covering offsets" `Quick (fun () ->
        Alcotest.check z "below 1" Zoom.identity
          (Zoom.about ~w ~h Zoom.identity ~cx:0. ~cy:0. ~ratio:0.5);
        Alcotest.check z "above 4"
          {scale = 4.; x = -300.; y = -600.}
          (Zoom.about ~w ~h Zoom.identity ~cx:100. ~cy:200. ~ratio:10.);
        Alcotest.check z "capped from x3"
          {scale = 4.; x = 100. -. (400. *. 4. /. 3.); y = -500.}
          (Zoom.about ~w ~h
             {scale = 3.; x = -300.; y = -350.}
             ~cx:100. ~cy:100. ~ratio:2.);
        let t = {Zoom.scale = 2.; x = -100.; y = -200.} in
        Alcotest.check z "pinched out from x2" Zoom.identity
          (Zoom.about ~w ~h t ~cx:300. ~cy:100. ~ratio:0.25);
        Alcotest.check z "pan past the left and bottom edges"
          {scale = 2.; x = -400.; y = 0.}
          (Zoom.pan ~w ~h t ~dx:(-1000.) ~dy:500.);
        Alcotest.check z "pan past the right and top edges"
          {scale = 2.; x = 0.; y = -800.}
          (Zoom.pan ~w ~h t ~dx:1000. ~dy:(-1000.)));
    Alcotest.test_case "zoomed above 1 %, settled below" `Quick (fun () ->
        let t = {Zoom.scale = 2.; x = -100.; y = -200.} in
        let barely = {Zoom.scale = 1.005; x = -2.; y = -1.} in
        Alcotest.(check bool) "zoomed" true (Zoom.zoomed t);
        Alcotest.(check bool) "not zoomed" false (Zoom.zoomed Zoom.identity);
        Alcotest.(check bool) "x1.005" false (Zoom.zoomed barely);
        Alcotest.check z "settle x1.005" Zoom.identity (Zoom.settle barely);
        Alcotest.check z "settle x2" t (Zoom.settle t));
  ]
