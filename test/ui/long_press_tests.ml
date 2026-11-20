(* Combinations long_press.mli does not list are only checked not to raise. *)

module Long_press = Herbier_ui_model.Long_press

let down x y = Long_press.Down {x; y}

let show_output = function
  | Long_press.Nothing -> "Nothing"
  | Long_press.Arm k -> Printf.sprintf "Arm %d" k
  | Long_press.Long -> "Long"
  | Long_press.Tap -> "Tap"

let output = Alcotest.testable (Fmt.of_to_string show_output) ( = )

let is_arm = function
  | Long_press.Arm _ -> true
  | Long_press.Nothing | Long_press.Long | Long_press.Tap -> false

let token = function
  | Long_press.Arm k -> k
  | Long_press.Nothing | Long_press.Long | Long_press.Tap ->
      Alcotest.fail "expected Arm"

let long_press =
  let open Long_press in
  (* From each phase, a [Down] arms a token greater than the last one, and the
     new press then behaves as one from idle. *)
  let down_from t last =
    let t1, o1 = step t (down 5. 5.) in
    let k = token o1 in
    Alcotest.(check bool) "a fresh, greater token" true (k > last);
    let t2, o2 = step t1 (Elapsed last) in
    Alcotest.check output "the earlier token fires nothing" Nothing o2;
    let t3, _ = step t2 Up in
    let _, o4 = step t3 Click in
    Alcotest.check output "then a tap" Tap o4
  in
  [
    Alcotest.test_case "the hold and slop constants from the signature" `Quick
      (fun () ->
        Alcotest.(check int) "hold_ms" 500 hold_ms;
        Alcotest.(check (float 0.)) "slop_px" 10. slop_px);
    Alcotest.test_case "a quick press and release is a tap" `Quick (fun () ->
        let t1, o1 = step idle (down 0. 0.) in
        Alcotest.(check bool) "arms a timer" true (is_arm o1);
        let t2, o2 = step t1 Up in
        Alcotest.check output "released: nothing yet" Nothing o2;
        let _, o3 = step t2 Click in
        Alcotest.check output "click after release: a tap" Tap o3);
    Alcotest.test_case
      "a long-press fires once and swallows the click that follows the lift"
      `Quick (fun () ->
        let t1, o1 = step idle (down 0. 0.) in
        let k = token o1 in
        let t2, o2 = step t1 (Elapsed k) in
        Alcotest.check output "fires" Long o2;
        let t3, o3 = step t2 Up in
        Alcotest.check output "lift: nothing yet" Nothing o3;
        let t4, o4 = step t3 Click in
        Alcotest.check output "swallowed, not a tap" Nothing o4;
        let _, o5 = step t4 Click in
        Alcotest.check output "back to idle: a later click is a tap" Tap o5);
    Alcotest.test_case "a move within the slop still allows the hold" `Quick
      (fun () ->
        let t1, o1 = step idle (down 0. 0.) in
        let k = token o1 in
        (* sqrt(6^2 + 8^2) = 10, exactly the slop: not beyond it *)
        let t2, o2 = step t1 (Move {x = 6.; y = 8.}) in
        Alcotest.check output "within slop: nothing" Nothing o2;
        let _, o3 = step t2 (Elapsed k) in
        Alcotest.check output "still fires" Long o3);
    Alcotest.test_case "a move beyond the slop cancels the hold" `Quick
      (fun () ->
        let t1, o1 = step idle (down 0. 0.) in
        let k = token o1 in
        (* sqrt(8^2 + 8^2) ≈ 11.3, beyond the slop *)
        let t2, _ = step t1 (Move {x = 8.; y = 8.}) in
        let t3, o3 = step t2 (Elapsed k) in
        Alcotest.check output "the stale hold fires nothing" Nothing o3;
        let t4, o4 = step t3 Up in
        Alcotest.check output "release: nothing yet" Nothing o4;
        let _, o5 = step t4 Click in
        Alcotest.check output "a plain tap" Tap o5);
    Alcotest.test_case "a stale timer from an earlier press fires nothing"
      `Quick (fun () ->
        let t1, o1 = step idle (down 0. 0.) in
        let k1 = token o1 in
        let t2, _ = step t1 Up in
        let t3, _ = step t2 Click in
        let t4, o4 = step t3 (down 10. 10.) in
        let k2 = token o4 in
        Alcotest.(check bool) "a fresh press, a fresh token" true (k2 > k1);
        let t5, o5 = step t4 (Elapsed k1) in
        Alcotest.check output "the earlier press's timer is ignored" Nothing o5;
        let _, o6 = step t5 (Elapsed k2) in
        Alcotest.check output "the current press's timer still fires" Long o6);
    Alcotest.test_case "a cancel (scroll) drops the press" `Quick (fun () ->
        let t1, o1 = step idle (down 0. 0.) in
        let k = token o1 in
        let t2, o2 = step t1 Cancel in
        Alcotest.check output "cancelled: nothing yet" Nothing o2;
        let t3, o3 = step t2 (Elapsed k) in
        Alcotest.check output "the cancelled press's timer fires nothing"
          Nothing o3;
        let _, o4 = step t3 Click in
        Alcotest.check output "idle: a click with no pointer seen is a tap" Tap
          o4);
    Alcotest.test_case "a click while still pressed is a tap" `Quick (fun () ->
        let t1, _ = step idle (down 0. 0.) in
        let t2, o2 = step t1 Click in
        Alcotest.check output "pressed, click: a tap" Tap o2;
        let _, o3 = step t2 Click in
        Alcotest.check output "back to idle: a click is a tap" Tap o3);
    Alcotest.test_case
      "a click right after the long-press, before the lift, is swallowed" `Quick
      (fun () ->
        let t1, o1 = step idle (down 0. 0.) in
        let t2, _ = step t1 (Elapsed (token o1)) in
        let t3, o3 = step t2 Click in
        Alcotest.check output "fired, click: nothing" Nothing o3;
        let _, o4 = step t3 Click in
        Alcotest.check output "back to idle: a click is a tap" Tap o4);
    Alcotest.test_case "a cancel after the long-press returns to idle" `Quick
      (fun () ->
        let t1, o1 = step idle (down 0. 0.) in
        let t2, _ = step t1 (Elapsed (token o1)) in
        let t3, o3 = step t2 Cancel in
        Alcotest.check output "fired, cancel: nothing" Nothing o3;
        let _, o4 = step t3 Click in
        Alcotest.check output "idle: a click is a tap" Tap o4);
    Alcotest.test_case "a cancel after a move beyond the slop returns to idle"
      `Quick (fun () ->
        let t1, o1 = step idle (down 0. 0.) in
        let k = token o1 in
        let t2, o2 = step t1 (Move {x = 20.; y = 0.}) in
        Alcotest.check output "moved: nothing" Nothing o2;
        let t3, o3 = step t2 Cancel in
        Alcotest.check output "moved, cancel: nothing" Nothing o3;
        let t4, o4 = step t3 (Elapsed k) in
        Alcotest.check output "idle, timer: nothing" Nothing o4;
        let _, o5 = step t4 Click in
        Alcotest.check output "idle: a click is a tap" Tap o5);
    Alcotest.test_case "the timer after the release fires nothing" `Quick
      (fun () ->
        let t1, o1 = step idle (down 0. 0.) in
        let t2, _ = step t1 Up in
        let t3, o3 = step t2 (Elapsed (token o1)) in
        Alcotest.check output "released, timer: nothing" Nothing o3;
        let _, o4 = step t3 Click in
        Alcotest.check output "released, click: still a tap" Tap o4);
    Alcotest.test_case "tokens strictly increase across presses" `Quick
      (fun () ->
        let _, tokens =
          List.fold_left
            (fun (t, acc) _ ->
              let t1, o1 = step t (down 0. 0.) in
              let t2, _ = step t1 Up in
              let t3, _ = step t2 Click in
              (t3, token o1 :: acc))
            (idle, []) [1; 2; 3; 4]
        in
        let tokens = List.rev tokens in
        let rec increasing = function
          | a :: (b :: _ as rest) -> a < b && increasing rest
          | [_] | [] -> true
        in
        Alcotest.(check bool) "strictly increasing" true (increasing tokens));
    Alcotest.test_case "a Down while pressed starts a new press" `Quick
      (fun () ->
        let t1, o1 = step idle (down 0. 0.) in
        let k1 = token o1 in
        let t2, o2 = step t1 (down 1. 1.) in
        let k2 = token o2 in
        Alcotest.(check bool) "a fresh, greater token" true (k2 > k1);
        let t3, o3 = step t2 (Elapsed k1) in
        Alcotest.check output "the first press's timer fires nothing" Nothing o3;
        let _, o4 = step t3 (Elapsed k2) in
        Alcotest.check output "the second's fires" Long o4);
    Alcotest.test_case "a Down after a long-press starts a new press" `Quick
      (fun () ->
        let t1, o1 = step idle (down 0. 0.) in
        let k = token o1 in
        let fired, _ = step t1 (Elapsed k) in
        down_from fired k;
        let swallowing, _ = step fired Up in
        down_from swallowing k);
    Alcotest.test_case "a click ending a move beyond the slop is no tap" `Quick
      (fun () ->
        let t1, _ = step idle (down 0. 0.) in
        let t2, _ = step t1 (Move {x = 20.; y = 0.}) in
        let t3, o3 = step t2 Click in
        Alcotest.check output "moved, click: nothing" Nothing o3;
        let _, o4 = step t3 Click in
        Alcotest.check output "back to idle: a click is a tap" Tap o4);
    Alcotest.test_case
      "a keyboard activation after a long-press with no click is a tap" `Quick
      (fun () ->
        let t1, o1 = step idle (down 0. 0.) in
        let t2, _ = step t1 (Elapsed (token o1)) in
        let t3, _ = step t2 Up in
        let t4, o4 = step t3 Activate in
        Alcotest.check output "swallowing, activate: a tap" Tap o4;
        let _, o5 = step t4 Click in
        Alcotest.check output "idle: a click is a tap" Tap o5);
    Alcotest.test_case "an activation is a tap from every phase" `Quick
      (fun () ->
        let pressed, o = step idle (down 0. 0.) in
        let fired = fst (step pressed (Elapsed (token o))) in
        List.iter
          (fun t ->
            Alcotest.check output "activate: a tap" Tap (snd (step t Activate)))
          [
            idle;
            pressed;
            fst (step pressed (Move {x = 100.; y = 100.}));
            fst (step pressed Up);
            fired;
            fst (step fired Up);
          ]);
    Alcotest.test_case
      "step is total: every phase accepts every input without raising" `Quick
      (fun () ->
        let pressed = fst (step idle (down 0. 0.)) in
        let moved = fst (step pressed (Move {x = 100.; y = 100.})) in
        let released = fst (step pressed Up) in
        let fired =
          let t1, o1 = step idle (down 0. 0.) in
          fst (step t1 (Elapsed (token o1)))
        in
        let swallowing = fst (step fired Up) in
        let phases = [idle; pressed; moved; released; fired; swallowing] in
        let inputs =
          [
            down 1. 1.;
            Move {x = 1.; y = 1.};
            Up;
            Cancel;
            Elapsed 999999;
            Click;
            Activate;
          ]
        in
        List.iter
          (fun phase ->
            List.iter
              (fun input ->
                let (_ : Long_press.t * Long_press.output) = step phase input in
                ())
              inputs)
          phases;
        Alcotest.(check bool) "completed without raising" true true);
  ]
