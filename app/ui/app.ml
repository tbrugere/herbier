module Db = Herbier_store.Db

type t = {
  db : Db.t;
  state : State.t;
  saved : unit React.event;
  send_saved : unit -> unit;
}

let create ~db ~state =
  let saved, send = React.E.create () in
  {db; state; saved; send_saved = (fun () -> send ())}

let db t = t.db
let state t = t.state
let saved t = t.saved

(* [saved] fires from its own reaction on the result, so a subscriber that
   raises cannot keep the caller's future from being determined. *)
let save t edits =
  let r = Db.edit t.db edits in
  Fut.await r (function Ok 0 | Error _ -> () | Ok _ -> t.send_saved ());
  r

let save_photos t ~(observation : Herbier_domain.Observation.t) shots =
  let target = (React.S.value (State.account t.state)).storage in
  let one (s : Herbier_photos.Capture.shot) =
    Herbier_photos.Preview.save t.db ~preview:s.preview
      ~observation_id:observation.id
      ~taken_at:(Option.value s.exif.taken_at ~default:(Ptime_clock.now ()))
      ~original_target:target s.original
  in
  let step (saved, failed) s =
    Fut.map
      (function
        | Ok (_ : Herbier_domain.Photo.t) -> (saved + 1, failed)
        | Error e ->
            Brr.Console.(
              error
                [str "photo"; str (Herbier_photos.Preview.error_to_string e)]);
            (saved, s :: failed))
      (one s)
  in
  Fut.map
    (fun (saved, failed) ->
      (match saved with 0 -> () | _ -> t.send_saved ());
      List.rev failed)
    (List.fold_left
       (fun acc s -> Fut.bind acc (fun r -> step r s))
       (Fut.return (0, []))
       shots)
