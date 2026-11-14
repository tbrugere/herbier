type network = Any | Unmetered

type failure =
  | Answered of {status : int; body : string}
  | File_missing
  | Gave_up of string
[@@deriving eq]

type state =
  | Enqueued
  | Blocked
  | Running
  | Succeeded of {status : int; body : string}
  | Failed of failure
  | Cancelled
[@@deriving eq]

type job = {id : string; state : state; attempts : int} [@@deriving eq]
type listener = Jv.t

let plugin = "uploader"
let network_to_string = function Any -> "connected" | Unmetered -> "unmetered"

let enqueue ~id ~path ~url ~mime ~network =
  Cap_call.call plugin "enqueue"
    [|
      Jv.obj
        [|
          ("id", Jv.of_string id);
          ("path", Jv.of_string path);
          ("url", Jv.of_string url);
          ("mimeType", Jv.of_string mime);
          ("network", Jv.of_string (network_to_string network));
        |];
    |]
    ~ok:Cap_call.unit_ok

(* A field the plugin may leave out: absent (undefined or null) is [None], a
   present one of the wrong type an error. *)
let optional read entry name =
  match Jv.find entry name with
  | None -> Ok None
  | Some _ -> Result.map Option.some (read entry name)

let failure entry =
  let open Result.Syntax in
  let* status = optional Cap_call.int_field entry "httpStatus" in
  match status with
  | Some status ->
      let+ body = optional Cap_call.string_field entry "body" in
      Answered {status; body = Option.value body ~default:""}
  | None -> (
      let* error = optional Cap_call.string_field entry "error" in
      match error with
      | Some "FILE_NOT_FOUND" -> Ok File_missing
      | Some "GAVE_UP" ->
          let+ message = optional Cap_call.string_field entry "message" in
          Gave_up (Option.value message ~default:"")
      (* A job WorkManager failed with empty output (an Error the worker does
         not catch) or an unknown [error]: a failure like any other, not a
         list the queue cannot read. *)
      | Some _ | None -> Ok (Gave_up ""))

let state entry =
  let open Result.Syntax in
  let* wire = Cap_call.string_field entry "state" in
  match wire with
  | "ENQUEUED" -> Ok Enqueued
  | "BLOCKED" -> Ok Blocked
  | "RUNNING" -> Ok Running
  | "SUCCEEDED" ->
      let* status = Cap_call.int_field entry "httpStatus" in
      let+ body = Cap_call.string_field entry "body" in
      Succeeded {status; body}
  | "FAILED" -> Result.map (fun f -> Failed f) (failure entry)
  | "CANCELLED" -> Ok Cancelled
  | _ -> Error (Cap_error.Unexpected "state")

let job entry =
  let open Result.Syntax in
  let* id = Cap_call.string_field entry "id" in
  let* attempts = Cap_call.int_field entry "attempts" in
  let+ state = state entry in
  {id; state; attempts}

let jobs_of r =
  match Cap_call.field r "jobs" with
  | Ok entries when Jv.is_array entries ->
      List.fold_right
        (fun entry acc ->
          Result.bind acc (fun l -> Result.map (fun j -> j :: l) (job entry)))
        (Jv.to_list Fun.id entries)
        (Ok [])
  | Ok _ | Error _ -> Error (Cap_error.Unexpected "jobs")

let jobs () = Cap_call.call plugin "jobs" [||] ~ok:jobs_of

let cancel ~id =
  Cap_call.call plugin "cancel"
    [|Jv.obj [|("id", Jv.of_string id)|]|]
    ~ok:Cap_call.unit_ok

let on_change f =
  let callback = Jv.callback ~arity:1 (fun (_ : Jv.t) -> f ()) in
  Cap_call.call plugin "addListener"
    [|Jv.of_string "jobsChanged"; callback|]
    ~ok:(fun handle -> Ok handle)

let remove handle = Cap_call.on handle "remove" [||] ~ok:Cap_call.unit_ok
