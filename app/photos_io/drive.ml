module Api = Herbier_photos.Drive
module Timed_fetch = Herbier_bindings.Timed_fetch

type 'e error = Token of 'e | Drive of Api.error

let error_to_string token_error = function
  | Token e -> "token: " ^ token_error e
  | Drive e -> "drive: " ^ Api.error_to_string e

let upload_timeout_ms = 300_000

(* The URL's path only: the query holds species names, which stay out of the
   console. *)
let path url =
  let before_query =
    match String.index_opt url '?' with
    | Some i -> String.sub url 0 i
    | None -> url
  in
  let scheme = "https://" in
  match String.starts_with ~prefix:scheme before_query with
  | false -> before_query
  | true -> (
      let n = String.length scheme in
      match String.index_from_opt before_query n '/' with
      | Some i -> String.sub before_query i (String.length before_query - i)
      | None -> "/")

let log (request : Api.request) outcome =
  Brr.Console.(
    log
      [
        str
          (Printf.sprintf "drive: %s %s → %s"
             (Timed_fetch.meth_to_string (request.meth :> Timed_fetch.meth))
             (path request.url) outcome);
      ])

let send ~media ~token (request : Api.request) =
  let url = request.url and meth = (request.meth :> Timed_fetch.meth) in
  let headers =
    ("Authorization", "Bearer " ^ token)
    :: Option.fold ~none:[]
         ~some:(fun ct -> [("Content-Type", ct)])
         (Api.content_type request.body)
  in
  let sent =
    match (request.body, media) with
    | Empty, _ -> Timed_fetch.request ~meth ~url ~headers ~body:None
    | Json json, _ -> Timed_fetch.request ~meth ~url ~headers ~body:(Some json)
    | Multipart {prefix; suffix; _}, Some media ->
        Timed_fetch.request_blob ~timeout_ms:upload_timeout_ms ~meth ~url
          ~headers
          (Herbier_bindings.Blob_frame.wrap ~prefix ~suffix media)
    | Multipart _, None ->
        (* Unreachable: only put_original sends a Multipart body, always
           with media. *)
        Fut.return
          (Error (Timed_fetch.Failed "a multipart request without media"))
  in
  Fut.map
    (fun answer ->
      let response : Api.response =
        match answer with
        | Ok {Timed_fetch.status; headers; body} ->
            Answer {status; headers; body}
        | Error e -> Unreachable (Timed_fetch.error_to_string e)
      in
      log request
        (match response with
        | Answer {status; _} -> string_of_int status
        | Unreachable m -> m);
      response)
    sent

let run ~token ~drop_token ?media program =
  let open Fut.Syntax in
  let rec go current = function
    | Api.Done (Ok x) -> Fut.return (Ok x)
    | Api.Done (Error e) -> Fut.return (Error (Drive e))
    | Api.Send (request, k) -> (
        let* response = send ~media ~token:current request in
        match response with
        | Answer {status = 401; _} -> (
            (* Play Services hands back the same dead token until it is
               cleared. *)
            let* () = drop_token current in
            let* fresh = token () in
            match fresh with
            | Error e -> Fut.return (Error (Token e))
            | Ok fresh ->
                let* response = send ~media ~token:fresh request in
                go fresh (k response))
        | Answer _ | Unreachable _ -> go current (k response))
  in
  let* first = token () in
  match first with
  | Error e -> Fut.return (Error (Token e))
  | Ok first -> go first program

let put_original ~token ~drop_token original media =
  run ~token ~drop_token ~media (Api.put_original original)

let start_session ~token ~drop_token target =
  run ~token ~drop_token (Api.start_session target)

let presence ~token ~drop_token ~file_id =
  run ~token ~drop_token (Api.presence ~file_id)

let boundary () =
  Result.map
    (fun random -> Api.boundary ~random)
    (Herbier_bindings.Web_crypto.random_bytes 16)
