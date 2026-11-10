module Fetch = Brr_io.Fetch

let message e = Jstr.to_string (Jv.Error.message e)

let blob web_path =
  let open Fut.Syntax in
  let* response = Fetch.url (Jstr.v web_path) in
  match response with
  | Error e -> Fut.return (Error (message e))
  | Ok response -> (
      match Fetch.Response.ok response with
      | false ->
          Fut.return
            (Error
               (Printf.sprintf "HTTP %d %s"
                  (Fetch.Response.status response)
                  (Jstr.to_string (Fetch.Response.status_text response))))
      | true ->
          let+ body = Fetch.Body.blob (Fetch.Response.as_body response) in
          Result.map_error message body)
