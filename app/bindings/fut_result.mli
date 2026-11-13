(** Futures of results: the two combinators the services repeat. *)

val map_error : ('e -> 'f) -> ('a, 'e) result Fut.t -> ('a, 'f) result Fut.t
(** [map_error f fut] maps the error of [fut]'s result. *)

val traverse :
  ('a -> ('b, 'e) result Fut.t) -> 'a list -> ('b list, 'e) result Fut.t
(** [traverse f xs] runs [f] on each item in turn, each started after the
    previous one resolved (never two at once), and stops at the first [Error]:
    the later items are never started. [Ok] carries the results in the order of
    [xs]. *)
