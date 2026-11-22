(* Herbier_ui_model.Incoming_photos: the captures handed to an observation
   by 4d's Enregistrer, per observation (M8.88). *)

module Incoming = Herbier_ui_model.Incoming_photos
module Observation_id = Herbier_domain.Ids.Observation_id

let counts id t = (Incoming.on_way id t, Incoming.written id t)
let pair = Alcotest.(pair int int)

let counted_per_observation () =
  let a = Observation_id.fresh () and b = Observation_id.fresh () in
  let t = Incoming.(empty |> add a |> add a |> add b) in
  Alcotest.check pair "two on their way to a" (2, 0) (counts a t);
  Alcotest.check pair "one to b" (1, 0) (counts b t);
  let t = Incoming.settle ~written:true a t in
  Alcotest.check pair "a: one written, one on its way" (1, 1) (counts a t);
  let t = Incoming.settle ~written:false a t in
  Alcotest.check pair "a: the other failed" (0, 1) (counts a t);
  Alcotest.check pair "b untouched" (1, 0) (counts b t)

let settle_without_any_is_unchanged () =
  let a = Observation_id.fresh () in
  let t = Incoming.settle ~written:true a Incoming.empty in
  Alcotest.(check bool) "empty" true (Incoming.equal Incoming.empty t);
  let t = Incoming.(empty |> add a |> settle ~written:false a) in
  let again = Incoming.settle ~written:true a t in
  Alcotest.(check bool)
    "a second settle: unchanged" true (Incoming.equal t again);
  Alcotest.check pair "nothing written" (0, 0) (counts a again)

let incoming_photos =
  [
    Alcotest.test_case "counted per observation, written or failed" `Quick
      counted_per_observation;
    Alcotest.test_case "settling with none on the way changes nothing" `Quick
      settle_without_any_is_unchanged;
  ]
