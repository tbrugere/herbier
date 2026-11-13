module Db = Herbier_store_io.Db
module Outbox = Herbier_store.Outbox
module Cap_error = Herbier_bindings.Cap_error
module Runner = Herbier_bindings.Cap_background_runner
module Wire = Herbier_sync_core.Keepalive.Wire
module Report = Herbier_sync_core.Keepalive.Report
module Session = Herbier_sync_core.Auth.Session

(* style: mutable fields because dispatches resolve in future callbacks,
   outside any reaction; nothing outside this module sees them. *)
type t = {
  db : Db.t;
  chain : Serial.t; (* the dispatches that must not overtake each other *)
  mutable handed : bool;
      (* The job may hold a queue: a hand-off may have reached it since the
         last confirmed take-back. [true] at start: a queue handed by an
         earlier process survives in the job's KV. *)
  mutable no_plugin : bool;
}

let create ~db =
  {db; chain = Serial.create (); handed = true; no_plugin = false}

let log = Console_line.log Keepalive
let warn = Console_line.warn Keepalive
let serially t step = Serial.run t.chain step

type error =
  | No_runner
  | Rejected of string
  | Timed_out of string
  | Bad_answer of string

let timeout_s = 15

let error_to_string = function
  | No_runner -> "no background runner in this build"
  | Rejected why -> why
  | Timed_out event ->
      Printf.sprintf "%s: no answer within %d s" event timeout_s
  | Bad_answer why -> why

(* [Rejected]: the plugin or the handler refused it, so the handler's write
   did not happen (each handler writes last). [Timed_out]: it may still
   land. *)
type answer = Answer of string option | No_job | Failed of error

(* The plugin runs the app's dispatches one at a time on its thread: one
   stuck behind a long one must not hold the engine's push forever. The
   late answer stays in [raw] for the callers that must act on it. *)
let within event raw =
  let result, set = Fut.create () in
  let settled = ref false in
  let settle v =
    match !settled with
    | true -> ()
    | false ->
        settled := true;
        set v
  in
  Fut.await raw settle;
  Fut.await
    (Fut.tick ~ms:(timeout_s * 1000))
    (fun () -> settle (Failed (Timed_out (Wire.event_to_string event))));
  result

let dispatch_raw t ~event json =
  let event = Wire.event_to_string event in
  match t.no_plugin with
  | true -> Fut.return No_job
  | false ->
      Fut.map
        (function
          | Ok json -> Answer json
          | Error (Cap_error.Unavailable _) ->
              t.no_plugin <- true;
              log "no background runner in this build";
              No_job
          | Error e -> Failed (Rejected (event ^ ": " ^ Cap_error.to_string e)))
        (Runner.dispatch_event ~label:Wire.label ~event ~json)

let dispatch t ~event json = within event (dispatch_raw t ~event json)

let acked = function
  | Answer _ -> Ok ()
  | No_job -> Error No_runner
  | Failed e -> Error e

let decoded ~event decode = function
  | No_job -> Error No_runner
  | Failed e -> Error e
  | Answer None ->
      Error (Bad_answer (Wire.event_to_string event ^ ": no answer"))
  | Answer (Some json) ->
      Result.map_error
        (fun why -> Bad_answer (Wire.event_to_string event ^ ": " ^ why))
        (decode json)

let reclaim_now t =
  let confirmed () =
    t.handed <- false;
    Ok ()
  in
  Fut.map
    (fun answer ->
      let result =
        match answer with
        | No_job -> confirmed ()
        | Answer _ | Failed _ -> (
            match decoded ~event:Wire.Reclaim Wire.decode_reclaim answer with
            | Ok false -> confirmed ()
            | Ok true -> Error (Bad_answer "reclaim: a job request in flight")
            | Error e -> Error e)
      in
      Result.iter_error (fun e -> warn (error_to_string e)) result;
      result)
    (dispatch t ~event:Wire.Reclaim None)

let reclaim t = serially t (fun () -> reclaim_now t)

let before_push t =
  serially t (fun () ->
      match t.handed with false -> Fut.return (Ok ()) | true -> reclaim_now t)

let skipped_line ({seq; why} : Wire.skipped) =
  Printf.sprintf "entry #%d not handed off (%s), nor the ones after it" seq why

(* The queue is the outbox's unparked prefix as read here: an entry
   committed after the read is simply not in it, which is safe only because
   it is a prefix in seq order (see Wire.queue_doc). *)
let hand_off_now t =
  let open Fut.Syntax in
  let* entries = Db.all t.db (Outbox.next ~limit:Wire.queue_limit) in
  match (entries, t.no_plugin) with
  | Error e, _ ->
      warn ("outbox not read: " ^ Db.error_to_string e);
      Fut.return ()
  | Ok [], _ | Ok _, true -> Fut.return ()
  | Ok entries, false -> (
      let {Wire.doc; count; skipped} =
        Wire.queue_doc ~supabase_url:Backend.supabase_url
          ~apikey:Backend.publishable_key entries
      in
      Option.iter (fun s -> warn (skipped_line s)) skipped;
      (* Set before the dispatch: one whose answer is lost may still have
         landed. A rejected one wrote nothing, so it restores the flag: an
         earlier queue the job may hold is still there. *)
      let was_handed = t.handed in
      t.handed <- true;
      let+ answer = dispatch t ~event:Wire.Hand_off (Some doc) in
      match answer with
      | Answer _ -> log (Printf.sprintf "handed off %d" count)
      | No_job -> t.handed <- false
      | Failed (Rejected why) ->
          t.handed <- was_handed;
          warn why
      | Failed e -> warn (error_to_string e))

let hand_off t = serially t (fun () -> hand_off_now t)

let set_session_now t s =
  dispatch t ~event:Wire.Set_session
    (Some
       (Wire.session_doc ~supabase_url:Backend.supabase_url
          ~apikey:Backend.publishable_key s))

let set_session t s =
  serially t (fun () ->
      Fut.map
        (fun answer ->
          (match answer with
          | Failed e -> warn (error_to_string e)
          | Answer _ | No_job -> ());
          acked answer)
        (set_session_now t s))

let logout what s =
  Fut.map
    (function
      | Ok () -> log (what ^ " logged out")
      | Error e -> warn (what ^ " logout: " ^ Auth.Server.error_to_string e))
    (Auth.Server.logout s)

(* An expired access token cannot log out: the refresh gives a live one,
   and the logout then revokes the whole session. *)
let live s =
  match Session.expired ~now:(Ptime_clock.now ()) s with
  | false -> Fut.return (Some s)
  | true ->
      Fut.map
        (function
          | Auth.Server.Fresh fresh -> Some fresh
          | Revoked _ -> None
          | Failed e ->
              warn ("job session refresh: " ^ Auth.Server.error_to_string e);
              None)
        (Auth.Server.refresh s)

(* A session taken from the job is revoked on the server: nobody holds it
   any more. *)
let retire what = function
  | None -> Fut.return ()
  | Some s -> (
      let open Fut.Syntax in
      let* live = live s in
      match live with None -> Fut.return () | Some s -> logout what s)

let taken_of = function
  | No_job -> Ok None
  | (Answer _ | Failed _) as answer ->
      decoded ~event:Wire.Take_session Wire.decode_taken_session answer

(* takeSession, timed. On a timeout the late answer is still followed: the
   job has dropped that session from its KV by then, so it is logged out
   when it comes. *)
let take t =
  let raw = dispatch_raw t ~event:Wire.Take_session None in
  Fut.map
    (fun answer ->
      (match answer with
      | Failed (Timed_out _) ->
          Fut.await raw (fun late ->
              match taken_of late with
              | Ok taken -> Fut.await (retire "late job session" taken) Fun.id
              | Error e -> warn ("late " ^ error_to_string e))
      | Answer _ | No_job | Failed (Rejected _ | No_runner | Bad_answer _) -> ());
      taken_of answer)
    (within Wire.Take_session raw)

let drop_session t =
  let open Fut.Syntax in
  let* taken = serially t (fun () -> take t) in
  match taken with
  | Error e ->
      warn (error_to_string e);
      Fut.return (Error e)
  | Ok taken -> Fut.map (fun () -> Ok ()) (retire "job session" taken)

(* Take and set in one step of the chain, so that no other take or set
   lands between them; the logouts run after it. *)
let replace_session t s =
  let open Fut.Syntax in
  let* taken, set =
    serially t (fun () ->
        let* taken = take t in
        match taken with
        | Error e -> Fut.return (None, Error e)
        | Ok taken ->
            let+ set = set_session_now t s in
            (taken, acked set))
  in
  let* () = retire "previous job session" taken in
  match set with
  | Ok () -> Fut.return (Ok ())
  | Error No_runner ->
      (* No job to hold it: the second grant is not left live. *)
      Fut.map (fun () -> Error No_runner) (logout "unused job session" s)
  | Error e ->
      warn (error_to_string e);
      Fut.map (fun () -> Error e) (logout "job session not handed" s)

let report t =
  Fut.map
    (decoded ~event:Wire.Report Report.decode)
    (dispatch t ~event:Wire.Report None)

let run_now t =
  let open Fut.Syntax in
  let* ran = dispatch_raw t ~event:Wire.Run_now None in
  match acked ran with Error e -> Fut.return (Error e) | Ok () -> report t
