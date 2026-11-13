module Outbox = Herbier_store.Outbox

type report = {pushed : int; parked : int} [@@deriving eq, show]

type t = Done of report | Stopped of report * Outcome.stop
[@@deriving eq, show]

module Make (H : Net.Rest.HTTP) (L : Local.S with module IO = H.IO) = struct
  module R = Net.Rest.Make (H)
  module C = Io.Make (H) (L)

  type step = Next of report | Empty | Stop of report * Outcome.stop

  let write store report stmt then_ =
    let open C.Syntax in
    let* written = L.write store stmt in
    match written with
    | Error e -> C.return (Stop (report, C.store_error e))
    | Ok (_ : int) -> C.return (Next (then_ report))

  let park store report (e : Outbox.entry) error =
    write store report
      (Outbox.park e.seq ~error:(Last_error.to_string error))
      (fun r -> {r with parked = r.parked + 1})

  let invalid e = Last_error.Invalid (Synced.entry_error_to_string e)

  let send store ~conn report (e : Outbox.entry) t row =
    let open C.Syntax in
    let* connected = conn () in
    match connected with
    | Error stop -> C.return (Stop (report, stop))
    | Ok c -> (
        let* sent = R.upsert c t row in
        match sent with
        | Ok () ->
            write store report (Outbox.delete e.seq) (fun r ->
                {r with pushed = r.pushed + 1})
        | Error (Rejected status) ->
            park store report e (Last_error.Rejected status)
        | Error
            ((Offline _ | Paused | Unauthorized | Transient _ | Bad_response _)
             as err) ->
            C.return (Stop (report, C.stop_of_error err)))

  let run store ~conn =
    let open C.Syntax in
    let rec loop report =
      let* next = L.all store (Outbox.next ~limit:1) in
      let* step =
        match next with
        | Error e -> C.return (Stop (report, C.store_error e))
        | Ok [] -> C.return Empty
        | Ok (e :: _) -> (
            match Synced.decode_entry ~table_name:e.table_name e.payload with
            | Error err -> park store report e (invalid err)
            | Ok (Entry (t, row)) -> send store ~conn report e t row)
      in
      match step with
      | Empty -> C.return (Done report)
      | Stop (report, s) -> C.return (Stopped (report, s))
      | Next report -> loop report
    in
    loop {pushed = 0; parked = 0}
end
