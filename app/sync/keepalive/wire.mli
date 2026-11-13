(** What the app hands the keep-alive job (web/runner/keepalive.js) and the
    small answers it reads back (architecture §4, keep-alive); the run report is
    {!Report}'s. The job is not OCaml: these values are its contract, all JSON
    text, versioned ["v":1]. Pure: no Brr, Fut, Jv or bindings; of Auth it names
    only the pure Auth.Session and Auth.Gotrue (test/sync copies it, with a shim
    Auth holding those two). Never logs or returns a token in an error string.
*)

val label : string
(** ["re.bruge.herbier.keepalive"]: the runner's label in capacitor.config.ts
    (and the name of its SharedPreferences file). *)

val version : int
(** 1: the ["v"] of every document here and of the job's answers. *)

val interval_minutes : int
(** 720: the job's period, also written in capacitor.config.ts. *)

val queue_limit : int
(** 200: at most this many entries are handed off (oldest first). *)

(** {1 Events of the runner script} *)

type event =
  | Run  (** ["keepAlive"]: WorkManager's event (config [event]) *)
  | Run_now  (** ["runNow"]: the same run, dispatched by #dev/keepalive *)
  | Set_session  (** ["setSession"] *)
  | Take_session  (** ["takeSession"] *)
  | Hand_off  (** ["handOff"] *)
  | Reclaim  (** ["reclaim"] *)
  | Report  (** ["report"] *)

val event_to_string : event -> string
(** The name the script listens to. *)

(** {1 Requests} *)

type meth = [`DELETE | `GET | `PATCH | `POST]

type request = {
  meth : meth;
  url : string;
  headers : (string * string) list;
      (** never an [authorization] header (the job adds
          [Authorization: Bearer <its access token>]); [apikey] included *)
  body : string option;
}
[@@deriving eq]

val request_to_yojson : request -> Yojson.Safe.t
(** [{"method":…,"url":…,"headers":{name:value,…},"body":<string|null>}]; header
    names lowercased. *)

val push_request :
  supabase_url:string ->
  apikey:string ->
  Herbier_store.Outbox.entry ->
  (request, string) result
(** The request {!Net.Rest.Make.upsert} would send for this entry's row
    ({!Synced.decode_entry}: [POST <url>/rest/v1/<table>],
    [Prefer: resolution=merge-duplicates,missing=default],
    [Content-Type: application/json], body structurally equal to the entry's
    payload), captured by a recording {!Postgrest.Client.HTTP} whose IO collects
    the requests instead of sending them, with the [authorization] header
    removed. Unknown [table_name] or a payload that does not decode →
    [Error why] ({!Synced.entry_error_to_string}, the reason the engine parks
    such an entry with). Never raises. *)

val ping_request : supabase_url:string -> apikey:string -> request
(** The job's one authenticated query: [Postgrest.Client.select] of [tags],
    columns [id] only, filter [id=eq.00000000-0000-0000-0000-000000000000] (no
    row can match: the answer is [[]], the work is one index probe), rendered
    through the same recorder: [GET <url>/rest/v1/tags?…], headers without
    [authorization]. *)

(** {1 Hand-off documents} *)

val session_doc :
  supabase_url:string -> apikey:string -> Auth.Session.t -> string
(** [setSession]'s details:
    [{"backend":{"v":1,"supabase_url":…,"apikey":…,"ping":<request>,
     "refresh":<request>,"logout":<request>}, "session":<Auth.Session.to_json>}],
    each [<request>] a {!request_to_yojson}: [ping] is {!ping_request};
    [refresh] is {!Auth.Gotrue.refresh_grant} with a [null] body (the job writes
    [{"refresh_token":…}]); [logout] is {!Auth.Gotrue.logout} without its
    [authorization] header (the job adds the bearer of the session it logs out).
    [supabase_url] keeps no trailing ['/']. *)

type skipped = {seq : int; why : string}

type queue = {
  doc : string;
      (** [handOff]'s details: [{"v":1,"requests":[<request_to_yojson>,…]}] *)
  count : int;  (** the number of requests in [doc] *)
  skipped : skipped option;
}

val queue_doc :
  supabase_url:string ->
  apikey:string ->
  Herbier_store.Outbox.entry list ->
  queue
(** The first {!queue_limit} entries in the given order (the caller passes
    [Outbox.next] order: seq ascending, unparked). An entry whose
    {!push_request} fails stops the list there (its successors may depend on it:
    the job must not push past it) and is returned as [skipped]; an entry past
    the {!queue_limit}th is never looked at. Empty list →
    [{"v":1,"requests":[]}]. *)

(** {1 Answers} *)

val decode_reclaim : string -> (bool, string) result
(** [reclaim]'s answer [{"v":1,"in_flight":bool}]: [true] when a request of the
    job's queue was still in flight when the job stopped waiting for it (it may
    land after the engine's next push). Errors: {!Json_read}'s,
    ["bad or missing in_flight"]. *)

val decode_taken_session : string -> (Auth.Session.t option, string) result
(** [takeSession]'s answer [{"v":1,"session":<object|null>}] → [Some]/[None];
    the session object is read by {!Auth.Session.of_json}. Errors:
    {!Json_read}'s, ["bad or missing session"], the session's own. *)
