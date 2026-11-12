(** A program of GETs to the reference sources, written without IO: each step is
    either a result or one request and what to do with its response. Run by
    [Herbier_refs_io.Http.run] in the app and by {!run} (a function standing for
    the network) in tests. Requests of one program are sequential; several
    programs run concurrently. Pure; nothing here raises. *)

type response =
  | Body of Yojson.Safe.t  (** A 2xx response whose body parsed as JSON. *)
  | Absent  (** HTTP 404: the source has no such page / taxon. *)
  | Failed of string
      (** Anything else (network, timeout, another status, a body that is not
          JSON): a message for logs. *)

(* style: transparent: the runners (Http.run, tests) match on it. *)
type 'a t = Done of 'a | Get of Request.t * (response -> 'a t)

val return : 'a -> 'a t
val get : Request.t -> response t
val bind : 'a t -> ('a -> 'b t) -> 'b t
val map : ('a -> 'b) -> 'a t -> 'b t

val recover : (string -> 'a) -> 'a t -> 'a t
(** The same program, except that a continuation which raises ends it with [f]
    of the exception's text, so a runner's future is always determined. Programs
    here do not raise; this guards the runner against a bug. *)

module Syntax : sig
  val ( let* ) : 'a t -> ('a -> 'b t) -> 'b t
  val ( let+ ) : 'a t -> ('a -> 'b) -> 'b t
end

val run : (Request.t -> response) -> 'a t -> 'a
(** Runs the program, answering each request with the function, in order. *)

val requests : (Request.t -> response) -> 'a t -> Request.t list
(** The requests {!run} would make, in order (for tests and logs). *)
