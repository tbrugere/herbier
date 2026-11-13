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

let message e =
  Jstr.to_string (Jv.Error.name e) ^ ": " ^ Jstr.to_string (Jv.Error.message e)

let header_list response =
  List.map
    (fun (k, v) -> (Jstr.to_string k, Jstr.to_string v))
    (Brr_io.Fetch.Headers.to_assoc (Brr_io.Fetch.Response.headers response))

(* Building the headers throws on a value fetch refuses: that is an [Error],
   not an exception that would leave the caller's future pending. *)
let request ~meth ~url ~headers ~body =
  match
    Brr_io.Fetch.Headers.of_assoc
      (List.map (fun (k, v) -> (Jstr.v k, Jstr.v v)) headers)
  with
  | exception Jv.Error e -> Fut.return (Error (Failed (message e)))
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
        match !timed_out with true -> Timeout | false -> Failed (message e)
      in
      let init =
        Brr_io.Fetch.Request.init
          ~method':(Jstr.v (meth_to_string meth))
          ~headers
          ?body:
            (Option.map (fun b -> Brr_io.Fetch.Body.of_jstr (Jstr.v b)) body)
          ~signal:(Brr.Abort.signal abort) ()
      in
      let open Fut.Syntax in
      let+ result =
        let* response = Brr_io.Fetch.url ~init (Jstr.v url) in
        match response with
        | Error e -> Fut.return (Error (failed e))
        | Ok response -> (
            let+ text =
              Brr_io.Fetch.Body.text (Brr_io.Fetch.Response.as_body response)
            in
            match text with
            | Ok text ->
                Ok
                  {
                    status = Brr_io.Fetch.Response.status response;
                    headers = header_list response;
                    body = Jstr.to_string text;
                  }
            | Error e -> Error (failed e))
      in
      Brr.G.stop_timer timer;
      result
