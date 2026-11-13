module Timed_fetch = Herbier_bindings.Timed_fetch

module IO = struct
  type 'a t = 'a Fut.t

  let return = Fut.return
  let bind = Fut.bind
end

type error = Timed_fetch.error

let error_to_string = Timed_fetch.error_to_string

let send ~meth ~url ~headers ?body () =
  Fut.map
    (Result.map (fun (r : Timed_fetch.response) ->
         {
           Postgrest.Client.status = r.status;
           headers = r.headers;
           body = r.body;
         }))
    (Timed_fetch.request ~meth ~url:(Uri.to_string url) ~headers ~body)

let conn_of_token token =
  Rest.conn ~supabase_url:Backend.supabase_url ~apikey:Backend.publishable_key
    ~token

let conn auth = Fut.map (Result.map conn_of_token) (Auth.access_token auth)
