module Db = Herbier_store.Db
module Cap_app = Herbier_bindings.Cap_app
module Cap_error = Herbier_bindings.Cap_error
module Outcome = Cycle.Outcome
module Schedule = Cycle.Schedule
module Report = Cycle.Report

module Device = struct
  module IO = Net.Transport.IO
  include Db
end

module Remote_push = Cycle.Push.Make (Net.Transport) (Device)
module Remote_pull = Cycle.Pull.Make (Net.Transport) (Device)

(* style: mutable fields because the schedule's state, its timer and the
   last report change from future, timer and app-state callbacks, outside any
   reaction; nothing outside this module sees them. *)
type t = {
  db : Db.t;
  auth : Auth.t;
  on_cycle : Report.t -> unit;
  mutable started : bool;
  mutable state : Schedule.state;
  mutable timer : Brr.G.timer_id option;
  mutable last : Report.t option;
}

let create ~db ~auth ~on_cycle =
  {
    db;
    auth;
    on_cycle;
    started = false;
    state = Schedule.initial;
    timer = None;
    last = None;
  }

let state t = t.state
let last t = t.last
let log m = Brr.Console.(log [str ("sync: " ^ m)])
let warn m = Brr.Console.(warn [str ("sync: " ^ m)])

let clear_timer t =
  Option.iter Brr.G.stop_timer t.timer;
  t.timer <- None

let ms_of span =
  Float.to_int (Float.max 0. (Ptime.Span.to_float_s span *. 1000.))

let conn auth () =
  Fut.map
    (function
      | Ok c -> Ok c
      | Error Auth.No_session -> Error Outcome.Signed_out
      | Error e -> Error (Outcome.Auth (Auth.error_to_string e)))
    (Net.Transport.conn auth)

let after_stop t = function
  | Some Outcome.Unauthorized ->
      Fut.map
        (function
          | Ok () -> log "token refreshed after 401"
          | Error e -> warn ("refresh after 401: " ^ Auth.error_to_string e))
        (Auth.refresh_now t.auth)
  | Some
      ( Outcome.Signed_out | Auth _ | Offline _ | Paused | Transient _
      | Rejected _ | Bad_response _ | Store _ )
  | None ->
      Fut.return ()

let rec apply t = function
  | Schedule.Run trigger ->
      clear_timer t;
      cycle t trigger
  | Wait span ->
      clear_timer t;
      log (Printf.sprintf "retry in %.0f s" (Ptime.Span.to_float_s span));
      t.timer <-
        Some
          (Brr.G.set_timeout ~ms:(ms_of span) (fun () ->
               t.timer <- None;
               send t Schedule.Retry_timer))
  | Cancel_timer -> clear_timer t
  | Nothing -> ()

and send t trigger =
  match t.started with
  | false -> ()
  | true ->
      let state, action = Schedule.trigger t.state trigger in
      t.state <- state;
      apply t action

and cycle t trigger =
  let started = Ptime_clock.now () in
  let conn = conn t.auth in
  let open Fut.Syntax in
  Fut.await
    (let* push = Remote_push.run t.db ~conn in
     let* cycle =
       match push with
       | Done p ->
           Fut.map
             (fun pull -> Report.Pushed (p, pull))
             (Remote_pull.run t.db ~conn)
       | Stopped (p, s) -> Fut.return (Report.Push_stopped (p, s))
     in
     let report = {Report.trigger; started; cycle} in
     let+ () = after_stop t (Report.stop report) in
     report)
    (fun report -> finish t report)

and finish t report =
  let state, action = Schedule.finished t.state (Report.stop report) in
  t.state <- state;
  t.last <- Some report;
  log (Report.to_string report);
  apply t action;
  t.on_cycle report

let local_write t = send t Schedule.Local_write
let signed_in t = send t Signed_in
let sync_now t = send t Manual

let start t =
  match t.started with
  | true -> ()
  | false ->
      t.started <- true;
      Fut.await
        (Cap_app.on_state_change (function
          | Active -> send t Schedule.Resume
          | Inactive -> send t Backgrounded))
        (function
          | Ok (_ : Cap_app.listener) -> ()
          | Error e -> warn ("app state listener: " ^ Cap_error.to_string e));
      send t Schedule.Start
