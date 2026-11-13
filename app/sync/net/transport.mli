(** {!Postgrest.Client.HTTP} over {!Herbier_bindings.Timed_fetch}, and the
    per-request connection (architecture §4: the token is awaited per request).
    Satisfies {!Rest.HTTP}: [module Remote = Rest.Make (Transport)]. *)

module IO : Postgrest.Client.IO with type 'a t = 'a Fut.t

type error = Herbier_bindings.Timed_fetch.error

val error_to_string : error -> string
(** {!Herbier_bindings.Timed_fetch.error_to_string}. *)

val send :
  meth:Herbier_bindings.Timed_fetch.meth ->
  url:Uri.t ->
  headers:(string * string) list ->
  ?body:string ->
  unit ->
  (Postgrest.Client.response, error) result IO.t
(** One {!Herbier_bindings.Timed_fetch.request}. Never raises; the future always
    resolves. *)

val conn_of_token : string -> Postgrest.Client.conn
(** {!Rest.conn} on {!Backend.supabase_url} and {!Backend.publishable_key} with
    this access token. *)

val conn : Auth.t -> (Postgrest.Client.conn, Auth.error) result Fut.t
(** {!Auth.access_token}, then {!conn_of_token}. [Error] as {!Auth.access_token}
    ([No_session] when signed out). *)
