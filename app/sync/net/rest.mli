(** The PostgREST requests of sync (architecture §4) over any
    {!Postgrest.Client.HTTP}: Brr fetch on the device ({!Transport}), a recorder
    in tests. One row per push request; pull by [updated_at]. Pure: no Brr, Fut,
    Jv or bindings (test/sync copies it). *)

val conn :
  supabase_url:string -> apikey:string -> token:string -> Postgrest.Client.conn
(** [Postgrest.Client.supabase_conn] on [<supabase_url>/rest/v1] (a single
    trailing ['/'] of [supabase_url] is dropped), headers
    [Authorization: Bearer <token>] and [apikey: <apikey>]. *)

val page_size : int
(** 500 rows: page [n] of a select asks for [Range: <500 n>-<500 n + 499>]
    ([Range-Unit: items]), below Supabase's [max_rows] (1000), so a full page
    means "maybe more". *)

val overlap : Ptime.Span.t
(** 5 s, subtracted from [since] (architecture §4). *)

type status_class =
  | Paused  (** 540: the Supabase project is paused *)
  | Unauthorized  (** 401: token missing, expired or rejected *)
  | Transient
      (** 408, 429, ≥ 500 except 540, and any status < 400 that reaches here *)
  | Rejected
      (** other 4xx (400, 403, 404, 409, 422, …): this request will fail again
          as is (park the entry) *)

val classify_status : int -> status_class
val equal_status_class : status_class -> status_class -> bool
val pp_status_class : Format.formatter -> status_class -> unit

val bad_response_to_string : Postgrest.Client.bad_response -> string
(** One line: ["row <i>: <why>"], ["expected an array"], ["not JSON: …"]. *)

module type HTTP = sig
  include Postgrest.Client.HTTP

  val error_to_string : error -> string
end

module Make (H : HTTP) : sig
  type error =
    | Offline of H.error  (** no answer (fetch failed, timeout) *)
    | Paused
    | Unauthorized
    | Transient of int  (** the status *)
    | Rejected of int  (** the status *)
    | Bad_response of Postgrest.Client.bad_response
        (** a 2xx whose body did not decode: not JSON, not an array, or row [i]
            did not decode (the whole select fails) *)

  val error_to_string : error -> string
  (** One line; never a token. *)

  val upsert :
    Postgrest.Client.conn ->
    ('table, 'row) Synced.t ->
    'row ->
    (unit, error) result H.IO.t
  (** [Client.insert ~on_conflict:`Upsert ~returning:Zero (Synced.input t row)
       (Synced.table t)]: [POST <base>/<table>], no query string, headers =
      [conn]'s, [Prefer: resolution=merge-duplicates,missing=default],
      [Content-Type: application/json]; body = [Input.to_json_string]. Any
      status below 400 → [Ok ()] (body ignored). Status ≥ 400 → its
      {!classify_status} constructor. *)

  val select_since :
    Postgrest.Client.conn ->
    ('table, 'row) Synced.t ->
    since:Ptime.t option ->
    page:int ->
    ('row list, error) result H.IO.t
  (** [GET <base>/<table>?updated_at=gt.<since - overlap>&select=<row's
       columns>&order=updated_at,id], with [since = None] the filter left out
      (first pull). [since] is a server [updated_at] (the last pull's), never
      the device clock. Headers: [conn]'s, [Range-Unit: items],
      [Range: <page * page_size>-<page * page_size + page_size - 1>],
      [Accept: application/json], [Prefer: missing=default] (the library's;
      PostgREST ignores it on a GET). The bound is rendered by [Postgrest.Col]
      in whole seconds UTC (["…Z"]), which only widens the overlap. Rows decoded
      with {!Synced.row}, in the server's order. Errors as {!upsert}.

      Paging is the caller's: one pull of a table keeps [since] fixed and asks
      pages 0, 1, … until one has fewer than [page_size] rows (architecture §4,
      pull).

      The library's decoder raises [Failure] on an integer literal beyond [int]
      (32 bits under js_of_ocaml): the synced integer columns are Postgres
      [integer], so a server row never carries one. *)
end
