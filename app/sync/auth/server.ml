module Timed_fetch = Herbier_bindings.Timed_fetch

type error = Network of string | Rejected of Gotrue.error

let error_to_string = function
  | Network m -> "network: " ^ m
  | Rejected e -> Gotrue.error_to_string e

let base_url = Backend.supabase_url
let apikey = Backend.publishable_key

(* A non-2xx status is not an [Error]: the {!Gotrue} decoders classify it. *)
let post (r : Gotrue.request) =
  Timed_fetch.request ~meth:`POST ~url:r.url ~headers:r.headers ~body:r.body

let grant request =
  let sent = Ptime_clock.now () in
  Fut.map
    (function
      | Error e -> Error (Network (Timed_fetch.error_to_string e))
      | Ok {Timed_fetch.status; body; _} ->
          Result.map_error
            (fun e -> Rejected e)
            (Gotrue.decode_session ~now:sent ~status body))
    (post request)

let id_token_grant ~raw_nonce ~id_token =
  grant (Gotrue.id_token_grant ~base_url ~apikey ~id_token ~nonce:raw_nonce)

let refresh (s : Session.t) =
  grant (Gotrue.refresh_grant ~base_url ~apikey ~refresh_token:s.refresh_token)

let logout (s : Session.t) =
  Fut.map
    (function
      | Error e -> Error (Network (Timed_fetch.error_to_string e))
      | Ok {Timed_fetch.status; body; _} ->
          Result.map_error
            (fun e -> Rejected e)
            (Gotrue.decode_empty ~status body))
    (post (Gotrue.logout ~base_url ~apikey ~access_token:s.access_token))
