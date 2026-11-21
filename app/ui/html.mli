(** DOM helpers of the screens and widgets. *)

val cls : string -> Brr.At.t
(** The [class] attribute, one class. *)

val button :
  ?label:string -> ?at:Brr.At.t list -> string list -> Brr.El.t list -> Brr.El.t
(** [button ?label ?at classes children]: a [<button type="button">], then
    [aria-label] when [label] is given, then one [class] per element of
    [classes], then [at], in that order. *)

val enter : Brr.Ev.Keyboard.t Brr.Ev.t -> bool
(** The key of a [keydown] is Enter. *)

val escape : Brr.Ev.Keyboard.t Brr.Ev.t -> bool
(** The key of a [keydown] is Escape. *)
