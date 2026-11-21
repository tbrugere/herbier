(** GET requests to the reference sources (architecture §6): every call goes
    through one rate-limited queue, at most one request in flight per source and
    {!max_in_flight} overall, since a fetch fans out to several public APIs at
    once. Requests start in the order they were queued, except that a request
    whose source is busy lets later requests to idle sources go first. *)

module Source = Herbier_domain.Reference.Source

type error =
  | Network of string
      (** The request did not complete: offline, DNS, CORS refusal; the
          browser's message. *)
  | Timeout  (** No complete response within the timeout. *)
  | Status of {status : int; body : string; retry_after : string option}
      (** A response outside 200–299, with its body text ([""] when reading it
          failed) and its [Retry-After] header. A cross-origin page reads that
          header only when the server exposes it to CORS: Wikidata does, GBIF
          and the Wikipedia REST API do not, so it is [None] there. *)

val error_to_string : error -> string

val user_agent : string
(** ["Herbier/<git describe> (https://github.com/tbrugere/herbier)"]. *)

val max_in_flight : int
(** Requests in flight across all sources. *)

val default_timeout_ms : int
(** Timeout of {!get} when none is given, in milliseconds. *)

val get :
  ?timeout_ms:int -> Herbier_refs.Request.t -> (string, error) result Fut.t
(** [get request] queues a GET of [request.url] for [request.source] and
    resolves with the response body as text. It sends
    [Api-User-Agent: {!user_agent}] to the Wikimedia sources ([Wikidata],
    [Wikipedia]) and no custom header to the others (architecture §6).
    [timeout_ms] (default {!default_timeout_ms}) runs from the moment the
    request starts, not from when it was queued; on expiry the request is
    aborted and its slot freed. The result arrives after the slot is freed and
    the next queued request started. Never raises. *)

val in_flight : unit -> Source.t list
(** The sources with a request started and not settled (at most one each), for
    the dev log. *)

val run : ?timeout_ms:int -> 'a Herbier_refs.Step.t -> 'a Fut.t
(** Runs the program, each [Get] through {!get} (same queue, same headers,
    [timeout_ms] per request): [Ok body] that
    {!Herbier_refs.Decode.json_of_string} parses → [Body]; [Ok] non-JSON →
    [Failed] with the parser's message; [Error (Status {status = 404; _})] →
    [Absent]; any other [Error e] → [Failed (error_to_string e)]. Each [Failed]
    is logged (console warn: source, URL, message). Never raises; an exception
    raised by a continuation (a bug) is not caught here. *)
