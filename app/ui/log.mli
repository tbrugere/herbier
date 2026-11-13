(** The console errors of the screens: one line of two parts, what failed (after
    its screen's [scope] and [": "]) and why. *)

val error : ?scope:string -> string -> string -> unit
(** [error ?scope what detail]: [console.error(scope ^ ": " ^ what, detail)], or
    [console.error(what, detail)] without [scope]. *)

val db : ?scope:string -> string -> Herbier_store_io.Db.error -> unit
(** {!error} of [Db.error_to_string]. *)

val cap : ?scope:string -> string -> Herbier_bindings.Cap_error.t -> unit
(** {!error} of [Cap_error.to_string]. *)
