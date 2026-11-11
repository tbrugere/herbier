(** The phone's time zone at a given instant ({!Herbier_bindings.Js_date}), for
    the pure {!Fr_date} functions that take [tz_offset_s]. *)

val offset_s : Ptime.t -> int
(** The zone's offset at that instant, in seconds east of UTC. *)

val date : Ptime.t -> Ptime.date
(** The local calendar day of that instant. *)
