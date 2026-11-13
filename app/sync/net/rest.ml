module Client = Postgrest.Client

let base_url supabase_url =
  match String.ends_with ~suffix:"/" supabase_url with
  | true -> String.sub supabase_url 0 (String.length supabase_url - 1)
  | false -> supabase_url

let rest_base supabase_url = Uri.of_string (base_url supabase_url ^ "/rest/v1")

let conn ~supabase_url ~apikey ~token =
  Client.supabase_conn (rest_base supabase_url) ~apikey ~token:(fun () ->
      Some token)

let page_size = 500
let overlap = Ptime.Span.of_int_s 5

type status_class = Paused | Unauthorized | Transient | Rejected
[@@deriving eq, show {with_path = false}]

(* 540 is what Supabase answers for every request to a paused project. *)
let classify_status = function
  | 540 -> Paused
  | 401 -> Unauthorized
  | 408 | 429 -> Transient
  | s when s >= 500 -> Transient
  | s when s >= 400 -> Rejected
  | _ -> Transient

let bad_response_to_string : Client.bad_response -> string = function
  | RowError (i, e) ->
      Printf.sprintf "row %d: %s" i (Herbier_store.Codec.row_error_to_string e)
  | ExpectedArray -> "expected an array"
  | JsonError m -> "not JSON: " ^ m

module type HTTP = sig
  include Client.HTTP

  val error_to_string : error -> string
end

module Make (H : HTTP) = struct
  module C = Client.Make (H)

  type error =
    | Offline of H.error
    | Paused
    | Unauthorized
    | Transient of int
    | Rejected of int
    | Bad_response of Client.bad_response

  let error_to_string = function
    | Offline e -> "offline: " ^ H.error_to_string e
    | Paused -> "paused (540)"
    | Unauthorized -> "unauthorized (401)"
    | Transient s -> Printf.sprintf "transient (%d)" s
    | Rejected s -> Printf.sprintf "rejected (%d)" s
    | Bad_response b -> "bad response: " ^ bad_response_to_string b

  let of_client : C.error -> error = function
    | IOError e -> Offline e
    | BadResponse b -> Bad_response b
    | ErrorStatus status -> (
        match classify_status status with
        | Paused -> Paused
        | Unauthorized -> Unauthorized
        | Transient -> Transient status
        | Rejected -> Rejected status)

  let map_error io =
    H.IO.bind io (fun result -> H.IO.return (Result.map_error of_client result))

  let upsert conn t row =
    map_error
      (C.insert conn ~on_conflict:`Upsert ~returning:Zero (Synced.input t row)
         (Synced.table t))

  let range_headers page =
    let first = page * page_size in
    [
      ("Range-Unit", "items");
      ("Range", Printf.sprintf "%d-%d" first (first + page_size - 1));
    ]

  let since_filter t = function
    | None -> Postgrest.Filter.And []
    | Some since ->
        let bound =
          Option.value (Ptime.sub_span since overlap) ~default:Ptime.min
        in
        Postgrest.Filter.Gt (Synced.updated_at_col t, Value bound)

  let select_since (conn : Client.conn) t ~since ~page =
    let paged =
      {conn with headers = (fun () -> conn.headers () @ range_headers page)}
    in
    map_error
      (C.select paged ~order:(Synced.order t)
         (Many (Synced.row t))
         (since_filter t since) (Synced.table t))
end
