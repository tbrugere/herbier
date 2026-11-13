(** Why a sync cycle stopped before the end. Shared by {!Push}, {!Pull},
    {!Schedule} and {!Engine}. Pure. The payloads are text: the transport's and
    the store's errors are functor parameters ([H.error], [L.error]), different
    on the device and in test/sync, and a stop is only ever shown or logged. *)

type stop =
  | Signed_out  (** no session ({!Auth.access_token} = [No_session]) *)
  | Auth of string
      (** the token could not be refreshed (network, GoTrue 5xx) *)
  | Offline of string  (** fetch failed or timed out *)
  | Paused  (** 540 *)
  | Unauthorized  (** 401 *)
  | Transient of int  (** 408, 429, 5xx *)
  | Rejected of int
      (** pull only: another 4xx on a select (a schema the server no longer
          has); retried like the others, a push parks its entry instead *)
  | Bad_response of string  (** a 2xx select body that did not decode *)
  | Store of string
      (** a local read or write failed; for the pull, the whole transaction
          rolled back (a foreign key, checked before the commit) *)
[@@deriving eq, show]

val to_string : stop -> string
(** One line, never a token: ["signed out"], ["paused"], ["HTTP 503"], … *)

val retries : stop -> bool
(** [false] for [Signed_out] only (the next sign-in starts a cycle); every other
    stop is retried with backoff. *)

val persistent : stop -> bool
(** [true] for [Rejected], [Bad_response] and [Store]: a stop the next cycle
    will most likely meet again (a schema or a row this build cannot read, a
    local write that fails), until the app or the server changes; 4m shows it
    when the pull stopped on it. [false] for the passing ones (network, pause,
    token, sign-in). *)
