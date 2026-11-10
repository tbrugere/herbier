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
