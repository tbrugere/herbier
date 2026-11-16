(** [window.matchMedia]: whether a media query matches now. *)

val matches : string -> bool
(** [window.matchMedia(q).matches], read at each call; [false] when [matchMedia]
    is missing or throws (an invalid query). *)
