(** What {!Push} and {!Pull} share over the HTTP and the store: the IO's binding
    operators, a fold, and how a REST or store error stops a cycle. Pure:
    test/sync copies it. *)

module Make (H : Net.Rest.HTTP) (L : Local.S with module IO = H.IO) : sig
  val return : 'a -> 'a H.IO.t

  module Syntax : sig
    val ( let* ) : 'a H.IO.t -> ('a -> 'b H.IO.t) -> 'b H.IO.t

    val ( let*? ) :
      ('a, 'e) result H.IO.t ->
      ('a -> ('b, 'e) result H.IO.t) ->
      ('b, 'e) result H.IO.t
    (** [let*] on the [Ok] case; an [Error] is returned as is. *)
  end

  val fold :
    ('acc -> 'a -> ('acc, 'e) result H.IO.t) ->
    'acc ->
    'a list ->
    ('acc, 'e) result H.IO.t
  (** [f] over the list in order, one at a time; stops at the first [Error]. *)

  val store_error : L.error -> Outcome.stop
  (** [Store (L.error_to_string e)]. *)

  val store : ('a, L.error) result H.IO.t -> ('a, Outcome.stop) result H.IO.t
  (** The error through {!store_error}. *)

  val stop_of_error : Net.Rest.Make(H).error -> Outcome.stop
  (** [Offline e] → [Offline (H.error_to_string e)]; [Paused], [Unauthorized],
      [Transient s], [Rejected s] → the same stop; [Bad_response b] →
      [Bad_response (Net.Rest.bad_response_to_string b)]. *)
end
