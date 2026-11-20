let timeout_ms = 15_000

type response = {status : int; headers : (string * string) list; body : string}
type meth = [`DELETE | `GET | `PATCH | `POST]

let meth_to_string : meth -> string = function
  | `GET -> "GET"
  | `POST -> "POST"
  | `PATCH -> "PATCH"
  | `DELETE -> "DELETE"

type error = Timeout | Failed of string

let error_to_string = function Timeout -> "timeout" | Failed m -> m
let message e = Jstr.to_string (Jv.Error.name e) ^ ": " ^ Js_error.message e

let header_list response =
  List.map
    (fun (k, v) -> (Jstr.to_string k, Jstr.to_string v))
    (Brr_io.Fetch.Headers.to_assoc (Brr_io.Fetch.Response.headers response))

type non_2xx_body = Read | Read_or_empty | Skip

let read_body ~non_2xx_body ~failed response =
  let open Fut.Syntax in
  let answer body =
    Ok
      {
        status = Brr_io.Fetch.Response.status response;
        headers = header_list response;
        body;
      }
  in
  let text () =
    Brr_io.Fetch.Body.text (Brr_io.Fetch.Response.as_body response)
  in
  match (Brr_io.Fetch.Response.ok response, non_2xx_body) with
  | false, Skip -> Fut.return (answer "")
  | false, Read_or_empty -> (
      let+ text = text () in
      match text with
      | Ok text -> answer (Jstr.to_string text)
      | Error _ -> answer "")
  | true, (Read | Read_or_empty | Skip) | false, Read -> (
      let+ text = text () in
      match text with
      | Ok text -> answer (Jstr.to_string text)
      | Error e -> Error (failed e))

(* [describe] gives a [Failed]'s text (see the .mli). Building the headers
   throws on a value fetch refuses: that is an [Error],
   not an exception that would leave the caller's future pending. *)
let fetch ~cache ~describe ~timeout_ms ~non_2xx_body ~meth ~url ~headers ~body =
  match
    Brr_io.Fetch.Headers.of_assoc
      (List.map (fun (k, v) -> (Jstr.v k, Jstr.v v)) headers)
  with
  | exception Jv.Error e -> Fut.return (Error (Failed (describe e)))
  | headers ->
      let abort = Brr.Abort.controller () in
      (* style: a local ref because the timer callback and the rejection
         handler must agree on why the fetch ended. *)
      let timed_out = ref false in
      let timer =
        Brr.G.set_timeout ~ms:timeout_ms (fun () ->
            timed_out := true;
            Brr.Abort.abort abort)
      in
      let failed e =
        match !timed_out with true -> Timeout | false -> Failed (describe e)
      in
      let init =
        Brr_io.Fetch.Request.init
          ~method':(Jstr.v (meth_to_string meth))
          ~headers ?body ?cache ~signal:(Brr.Abort.signal abort) ()
      in
      let open Fut.Syntax in
      let+ result =
        let* response = Brr_io.Fetch.url ~init (Jstr.v url) in
        match response with
        | Error e -> Fut.return (Error (failed e))
        | Ok response -> read_body ~non_2xx_body ~failed response
      in
      Brr.G.stop_timer timer;
      result

let request ~meth ~url ~headers ~body =
  fetch ~cache:None ~describe:message ~timeout_ms ~non_2xx_body:Read ~meth ~url
    ~headers
    ~body:(Option.map (fun b -> Brr_io.Fetch.Body.of_jstr (Jstr.v b)) body)

let request_blob ?(timeout_ms = timeout_ms) ~meth ~url ~headers blob =
  fetch ~cache:None ~describe:message ~timeout_ms ~non_2xx_body:Read ~meth ~url
    ~headers
    ~body:(Some (Brr_io.Fetch.Body.of_blob blob))

type form_file = {field : string; filename : string; blob : Brr.Blob.t}

let form_data ~fields files =
  let data = Brr_io.Form.Data.create () in
  List.iter
    (fun (name, value) ->
      Brr_io.Form.Data.append data (Jstr.v name) (Jstr.v value))
    fields;
  List.iter
    (fun {field; filename; blob} ->
      Brr_io.Form.Data.append_blob ~filename:(Jstr.v filename) data
        (Jstr.v field) blob)
    files;
  data

let request_form ?(timeout_ms = timeout_ms) ~url ~fields files =
  fetch ~cache:None ~describe:message ~timeout_ms ~non_2xx_body:Read ~meth:`POST
    ~url ~headers:[]
    ~body:(Some (Brr_io.Fetch.Body.of_form_data (form_data ~fields files)))

let get ?(timeout_ms = timeout_ms) ?(non_2xx_body = Read) ?(headers = []) ?cache
    url =
  fetch ~cache ~describe:Js_error.message ~timeout_ms ~non_2xx_body ~meth:`GET
    ~url ~headers ~body:None
