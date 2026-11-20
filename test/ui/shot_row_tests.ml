(* Herbier_ui_model.Shot_row: 4d's thumbnail row, pure. Instantiated here with
   [int Shot_row.t] (the shot's identity does not matter to the row's own
   logic; ints make structural equality on `slots` straightforward). *)

module Shot_row = Herbier_ui_model.Shot_row

let ticket_t = Alcotest.testable Shot_row.pp_ticket Shot_row.equal_ticket

let slot_t (shot : 'a Alcotest.testable) : 'a Shot_row.slot Alcotest.testable =
  let pp fmt = function
    | Shot_row.Pending t -> Format.fprintf fmt "Pending %a" Shot_row.pp_ticket t
    | Shot_row.Ready s -> Format.fprintf fmt "Ready %a" (Alcotest.pp shot) s
  in
  Alcotest.testable pp (Shot_row.equal_slot (Alcotest.equal shot))

let slots_t shot = Alcotest.list (slot_t shot)
let int_slots_t = slots_t Alcotest.int

let empty () =
  let row : int Shot_row.t = Shot_row.empty in
  Alcotest.(check int_slots_t) "no slots" [] (Shot_row.slots row);
  Alcotest.(check (list int)) "no ready shots" [] (Shot_row.ready row);
  Alcotest.(check int) "nothing pending" 0 (Shot_row.pending row);
  Alcotest.(check bool) "can_save is false" false (Shot_row.can_save row)

let begin_capture_on_empty () =
  let row, t = Shot_row.begin_capture (Shot_row.empty : int Shot_row.t) in
  Alcotest.(check int_slots_t)
    "one Pending slot" [Shot_row.Pending t] (Shot_row.slots row);
  Alcotest.(check int) "one pending" 1 (Shot_row.pending row);
  Alcotest.(check bool)
    "a placeholder alone does not enable Enregistrer" false
    (Shot_row.can_save row)

let fill_the_single_pending_slot () =
  let row, t = Shot_row.begin_capture (Shot_row.empty : int Shot_row.t) in
  let row = Shot_row.fill t 1 row in
  Alcotest.(check int_slots_t)
    "slots = [Ready 1]" [Shot_row.Ready 1] (Shot_row.slots row);
  Alcotest.(check int) "nothing pending left" 0 (Shot_row.pending row);
  Alcotest.(check bool) "can_save is true" true (Shot_row.can_save row);
  Alcotest.(check bool)
    "the ticket is no longer pending" false
    (Shot_row.is_pending t row)

let fill_keeps_tap_order_not_settle_order () =
  let row, t1 = Shot_row.begin_capture (Shot_row.empty : int Shot_row.t) in
  let row, t2 = Shot_row.begin_capture row in
  (* The second tap settles first. *)
  let row = Shot_row.fill t2 2 row in
  Alcotest.(check int_slots_t)
    "t1 still pending, t2 ready: one still pending"
    [Shot_row.Pending t1; Shot_row.Ready 2]
    (Shot_row.slots row);
  Alcotest.(check bool)
    "can_save is false while t1 is still pending" false (Shot_row.can_save row);
  let row = Shot_row.fill t1 1 row in
  Alcotest.(check (list int))
    "ready is in tap order (1 then 2), not settle order" [1; 2]
    (Shot_row.ready row)

let drop_removes_only_that_placeholder () =
  let row = Shot_row.append [1] (Shot_row.empty : int Shot_row.t) in
  let row, t = Shot_row.begin_capture row in
  Alcotest.(check int_slots_t)
    "before drop: [Ready 1; Pending t]"
    [Shot_row.Ready 1; Shot_row.Pending t]
    (Shot_row.slots row);
  let row = Shot_row.drop t row in
  Alcotest.(check int_slots_t)
    "after drop: [Ready 1]" [Shot_row.Ready 1] (Shot_row.slots row);
  Alcotest.(check bool) "can_save is true" true (Shot_row.can_save row)

let stale_tickets_never_raise_and_leave_the_row_unchanged () =
  let row, t = Shot_row.begin_capture (Shot_row.empty : int Shot_row.t) in
  let dropped = Shot_row.drop t row in
  let filled_after_drop = Shot_row.fill t 1 dropped in
  Alcotest.(check int_slots_t)
    "fill after drop: unchanged" (Shot_row.slots dropped)
    (Shot_row.slots filled_after_drop);
  let filled = Shot_row.fill t 1 row in
  let filled_again = Shot_row.fill t 2 filled in
  Alcotest.(check int_slots_t)
    "a second fill of an already-filled ticket: unchanged"
    (Shot_row.slots filled)
    (Shot_row.slots filled_again);
  let dropped_after_fill = Shot_row.drop t filled in
  Alcotest.(check int_slots_t)
    "a drop of an already-filled ticket: unchanged" (Shot_row.slots filled)
    (Shot_row.slots dropped_after_fill);
  let dropped_twice = Shot_row.drop t dropped in
  Alcotest.(check int_slots_t)
    "a second drop: unchanged" (Shot_row.slots dropped)
    (Shot_row.slots dropped_twice)

let tickets_are_distinct () =
  let row, t1 = Shot_row.begin_capture (Shot_row.empty : int Shot_row.t) in
  let row, t2 = Shot_row.begin_capture row in
  Alcotest.(check bool)
    "equal_ticket t1 t2 = false" false
    (Shot_row.equal_ticket t1 t2);
  Alcotest.(check bool) "t1 pending" true (Shot_row.is_pending t1 row);
  Alcotest.(check bool) "t2 pending" true (Shot_row.is_pending t2 row);
  let row = Shot_row.drop t1 row in
  Alcotest.(check bool)
    "t1 no longer pending after its drop" false
    (Shot_row.is_pending t1 row);
  Alcotest.(check bool)
    "t2 still pending after dropping t1" true
    (Shot_row.is_pending t2 row)

let a_dropped_ticket_is_never_handed_out_again () =
  let row, t1 = Shot_row.begin_capture (Shot_row.empty : int Shot_row.t) in
  let row = Shot_row.drop t1 row in
  let row, t2 = Shot_row.begin_capture row in
  Alcotest.(check bool)
    "the ticket after a drop differs" false
    (Shot_row.equal_ticket t1 t2);
  Alcotest.(check int_slots_t)
    "drop t1 leaves [Pending t2]" [Shot_row.Pending t2]
    (Shot_row.slots (Shot_row.drop t1 row));
  Alcotest.(check int_slots_t)
    "fill t1 leaves [Pending t2]" [Shot_row.Pending t2]
    (Shot_row.slots (Shot_row.fill t1 9 row))

let a_filled_ticket_is_never_handed_out_again () =
  let row, t1 = Shot_row.begin_capture (Shot_row.empty : int Shot_row.t) in
  let row = Shot_row.fill t1 1 row in
  let row, t2 = Shot_row.begin_capture row in
  Alcotest.(check bool)
    "the ticket after a fill differs" false
    (Shot_row.equal_ticket t1 t2);
  Alcotest.(check int_slots_t)
    "fill t1 again leaves the row"
    [Shot_row.Ready 1; Shot_row.Pending t2]
    (Shot_row.slots (Shot_row.fill t1 9 row))

let a_late_capture_never_fills_a_newer_tap () =
  let row, ta = Shot_row.begin_capture (Shot_row.empty : int Shot_row.t) in
  let row, tb = Shot_row.begin_capture row in
  let row = Shot_row.drop ta row in
  let row, tc = Shot_row.begin_capture row in
  Alcotest.(check bool)
    "the third tap's ticket differs from the second's" false
    (Shot_row.equal_ticket tb tc);
  Alcotest.(check int_slots_t)
    "filling the second leaves the third pending"
    [Shot_row.Ready 2; Shot_row.Pending tc]
    (Shot_row.slots (Shot_row.fill tb 2 row))

let dropping_a_stuck_placeholder_enables_save_again () =
  let row = Shot_row.append [1] (Shot_row.empty : int Shot_row.t) in
  let row, t = Shot_row.begin_capture row in
  Alcotest.(check bool)
    "a pending capture blocks Enregistrer" false (Shot_row.can_save row);
  let row = Shot_row.drop t row in
  Alcotest.(check bool)
    "its ✕ (a drop) enables it again" true (Shot_row.can_save row);
  Alcotest.(check int_slots_t)
    "the ready photo is kept" [Shot_row.Ready 1] (Shot_row.slots row)

let append_after_a_pending_tap () =
  let row, t = Shot_row.begin_capture (Shot_row.empty : int Shot_row.t) in
  let row = Shot_row.append [1; 2] row in
  Alcotest.(check int_slots_t)
    "the pending slot stays first, the gallery picks after it"
    [Shot_row.Pending t; Shot_row.Ready 1; Shot_row.Ready 2]
    (Shot_row.slots row);
  Alcotest.(check bool)
    "can_save is false until the pending slot fills" false
    (Shot_row.can_save row);
  let row = Shot_row.fill t 3 row in
  Alcotest.(check bool)
    "can_save is true once filled" true (Shot_row.can_save row)

let remove_ready_slots_matching_a_predicate () =
  let row = Shot_row.append [1; 2] (Shot_row.empty : int Shot_row.t) in
  let row, t = Shot_row.begin_capture row in
  let row = Shot_row.remove (( = ) 1) row in
  Alcotest.(check int_slots_t)
    "the ready shot 1 is removed; 2 and the pending slot are kept"
    [Shot_row.Ready 2; Shot_row.Pending t]
    (Shot_row.slots row);
  (* Removing the last ready shot disables Enregistrer. *)
  let one_ready = Shot_row.append [1] (Shot_row.empty : int Shot_row.t) in
  Alcotest.(check bool)
    "can_save is true with one ready shot" true
    (Shot_row.can_save one_ready);
  let none_ready = Shot_row.remove (( = ) 1) one_ready in
  Alcotest.(check bool)
    "can_save is false once the last ready shot is removed" false
    (Shot_row.can_save none_ready)

let remove_several_ready_slots () =
  let row = Shot_row.append [1; 2; 3] (Shot_row.empty : int Shot_row.t) in
  Alcotest.(check int_slots_t)
    "a predicate matching two shots removes both" [Shot_row.Ready 2]
    (Shot_row.slots (Shot_row.remove (fun x -> x <> 2) row))

let ready_skips_pending_slots_and_keeps_order () =
  let row, _t = Shot_row.begin_capture (Shot_row.empty : int Shot_row.t) in
  let row = Shot_row.append [1; 2] row in
  Alcotest.(check (list int))
    "ready lists only the Ready shots, in order" [1; 2] (Shot_row.ready row)

let shot_row =
  [
    Alcotest.test_case "empty: no slots, nothing ready or pending, can't save"
      `Quick empty;
    Alcotest.test_case
      "begin_capture on empty: one Pending slot, can't save yet" `Quick
      begin_capture_on_empty;
    Alcotest.test_case "fill the single pending slot: Ready, can_save" `Quick
      fill_the_single_pending_slot;
    Alcotest.test_case
      "fill keeps tap order, not settle order; can_save only once all are ready"
      `Quick fill_keeps_tap_order_not_settle_order;
    Alcotest.test_case "drop removes only that placeholder" `Quick
      drop_removes_only_that_placeholder;
    Alcotest.test_case
      "stale tickets (fill or drop after drop or fill) never raise and leave \
       the row unchanged"
      `Quick stale_tickets_never_raise_and_leave_the_row_unchanged;
    Alcotest.test_case
      "tickets from two begin_capture calls are distinct; is_pending tracks \
       them"
      `Quick tickets_are_distinct;
    Alcotest.test_case "a dropped ticket is never handed out again" `Quick
      a_dropped_ticket_is_never_handed_out_again;
    Alcotest.test_case "a filled ticket is never handed out again" `Quick
      a_filled_ticket_is_never_handed_out_again;
    Alcotest.test_case "a late capture never fills a newer tap's placeholder"
      `Quick a_late_capture_never_fills_a_newer_tap;
    Alcotest.test_case
      "dropping a stuck placeholder (its ✕) enables Enregistrer again" `Quick
      dropping_a_stuck_placeholder_enables_save_again;
    Alcotest.test_case
      "append after a pending tap: gallery picks go after the placeholder"
      `Quick append_after_a_pending_tap;
    Alcotest.test_case
      "remove drops matching Ready slots, keeps Pending ones; emptying ready \
       disables can_save"
      `Quick remove_ready_slots_matching_a_predicate;
    Alcotest.test_case "remove with a predicate matching several shots" `Quick
      remove_several_ready_slots;
    Alcotest.test_case "ready skips pending slots and keeps order" `Quick
      ready_skips_pending_slots_and_keeps_order;
  ]
