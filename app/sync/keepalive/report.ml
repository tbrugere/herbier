type ping = Ping_status of int | Ping_failed of string | Ping_not_run

type session_outcome =
  | No_session
  | Fresh
  | Refreshed
  | Revoked of int
  | Refresh_failed of string
  | Replaced

type trigger = Job | Dispatch

let trigger_to_string = function Job -> "job" | Dispatch -> "dispatch"

type queue =
  | Not_run
  | Skipped_app_active
  | Pushed of {count : int; stop : string option}

type run = {
  at : Ptime.t;
  trigger : trigger;
  app_active : bool;
  session : session_outcome;
  queue : queue;
  error : string option;
  ping : ping;
}

type t = {session_expires_at : Ptime.t option; queued : int; runs : run list}

(* The JSON as the job writes it, decoded by the derived readers; the
   variants it spells as strings or several shapes are read from these. A
   [float] reads an [`Int], an [`Intlit] (under js_of_ocaml an [int] is 32
   bits: a millisecond clock comes back as one) and a [`Float]. *)
module Json = struct
  type queue = {pushed : int; stop : string option}
  [@@deriving of_yojson {strict = false}]

  type run = {
    at : float;
    trigger : string;
    app_active : bool;
    session : string;
    (* Read only for the outcome that uses it, as the job writes it. *)
    revoked_status : Yojson.Safe.t; [@default `Null]
    refresh_error : Yojson.Safe.t; [@default `Null]
    queue : Yojson.Safe.t;
    error : string option;
    ping : Yojson.Safe.t;
  }
  [@@deriving of_yojson {strict = false}]

  type t = {
    session_expires_at : float option;
    queued : int;
    runs : Yojson.Safe.t;
  }
  [@@deriving of_yojson {strict = false}]
end

let bad field = Error ("bad or missing " ^ field)

(* The derived readers' errors are paths ([<Module>.Json.run.at]): the
   field, its last segment, is kept. *)
let derived of_yojson json =
  let field path =
    match String.rindex_opt path '.' with
    | Some i -> String.sub path (i + 1) (String.length path - i - 1)
    | None -> path
  in
  Result.map_error (fun path -> "bad or missing " ^ field path) (of_yojson json)

let time_of ~scale ~field n =
  match Ptime.of_float_s (n /. scale) with Some t -> Ok t | None -> bad field

let trigger_of = function
  | "job" -> Ok Job
  | "dispatch" -> Ok Dispatch
  | _ -> bad "trigger"

let session_of (w : Json.run) =
  match (w.session, w.revoked_status, w.refresh_error) with
  | "none", _, _ -> Ok No_session
  | "fresh", _, _ -> Ok Fresh
  | "refreshed", _, _ -> Ok Refreshed
  | "replaced", _, _ -> Ok Replaced
  | "revoked", `Int status, _ -> Ok (Revoked status)
  | "revoked", _, _ -> bad "revoked_status"
  | "refresh_failed", _, `String why -> Ok (Refresh_failed why)
  | "refresh_failed", _, _ -> bad "refresh_error"
  | _ -> Error "unknown session outcome"

let queue_of = function
  | `Null -> Ok Not_run
  | `String "skipped" -> Ok Skipped_app_active
  | `Assoc _ as json -> (
      match Json.queue_of_yojson json with
      | Ok {pushed; stop} when pushed >= 0 -> Ok (Pushed {count = pushed; stop})
      | Ok _ | Error _ -> bad "queue")
  | _ -> bad "queue"

let ping_of = function
  | `Null -> Ok Ping_not_run
  | `Int status -> Ok (Ping_status status)
  | `String why -> Ok (Ping_failed why)
  | _ -> bad "ping"

let run_of = function
  | `Assoc _ as json ->
      let open Result.Syntax in
      let* (w : Json.run) = derived Json.run_of_yojson json in
      let* at = time_of ~scale:1000. ~field:"at" w.at in
      let* trigger = trigger_of w.trigger in
      let* session = session_of w in
      let* queue = queue_of w.queue in
      let+ ping = ping_of w.ping in
      {
        at;
        trigger;
        app_active = w.app_active;
        session;
        queue;
        error = w.error;
        ping;
      }
  | _ -> Error "not an object"

let runs_of = function
  | `List runs ->
      let rec go i acc = function
        | [] -> Ok (List.rev acc)
        | json :: rest -> (
            match run_of json with
            | Ok run -> go (i + 1) (run :: acc) rest
            | Error why -> Error (Printf.sprintf "run %d: %s" i why))
      in
      go 0 [] runs
  | _ -> Error "runs is not an array"

let decode text =
  let open Result.Syntax in
  let* fields = Json_read.versioned Wire.version text in
  let* (w : Json.t) = derived Json.of_yojson (`Assoc fields) in
  let* session_expires_at =
    match w.session_expires_at with
    | None -> Ok None
    | Some n ->
        Result.map Option.some (time_of ~scale:1. ~field:"session_expires_at" n)
  in
  let+ runs = runs_of w.runs in
  {session_expires_at; queued = w.queued; runs}

let session_to_string = function
  | No_session -> "none"
  | Fresh -> "fresh"
  | Refreshed -> "refreshed"
  | Replaced -> "replaced"
  | Revoked status -> Printf.sprintf "revoked %d" status
  | Refresh_failed why -> "refresh failed (" ^ why ^ ")"

let queue_to_strings = function
  | Not_run -> []
  | Skipped_app_active -> ["queue skipped"]
  | Pushed {count; stop} ->
      Printf.sprintf "pushed %d" count
      :: (match stop with Some why -> ["stop (" ^ why ^ ")"] | None -> [])

let ping_to_string = function
  | Ping_status status -> Printf.sprintf "ping %d" status
  | Ping_failed why -> "ping failed (" ^ why ^ ")"
  | Ping_not_run -> "no ping"

let run_to_string r =
  String.concat " "
    (List.concat
       [
         [
           Ptime.to_rfc3339 ~tz_offset_s:0 r.at;
           trigger_to_string r.trigger;
           session_to_string r.session;
         ];
         queue_to_strings r.queue;
         (match r.error with Some why -> ["error (" ^ why ^ ")"] | None -> []);
         [ping_to_string r.ping];
       ])
