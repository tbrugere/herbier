(** A screen's MapLibre map through the screen's life: [Creating] until
    [Herbier_geo_io.Map.create] answers, then [Ready] or [Failed]; [Released]
    once the screen is torn down. *)

type t = Creating | Ready of Herbier_geo_io.Map.t | Failed | Released

val alive : t -> bool
(** [false] once [Released]: a map that arrives after that is removed. *)

val release : t ref -> unit
(** Removes a [Ready] map; the slot becomes [Released] whatever it held. *)
