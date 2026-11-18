(** What the dev pages share: a log line, buttons and their clicks, steps, a
    test JPEG, a substring test. *)

val append : Brr.El.t -> string -> unit
(** One [<div>] line of text at the end of the log. *)

val button : string -> Brr.El.t
(** A [<button type="button">] with that text. *)

val on_click : Brr.El.t -> (unit -> unit) -> unit
(** Calls [f] on every click, for the page's lifetime (never unlistened). *)

val heading : Brr.El.t -> string -> unit
(** One [<h2>] line at the end of the log. *)

val set_disabled : Brr.El.t -> bool -> unit
(** Sets or removes the [disabled] attribute. *)

val step :
  Brr.El.t ->
  string ->
  detail:('a -> string option) ->
  error:('e -> string) ->
  ('a, 'e) result Fut.t ->
  ('a, 'e) result Fut.t
(** As soon as the future settles, logs ["<label>: ok"], ["<label>: ok · <d>"]
    when [detail] gives [Some d], or ["<label>: <error e>"], and passes the
    result on: a chain of steps stops at its first failure while every outcome
    is shown. *)

val action : string -> (unit -> unit) -> Brr.El.t
(** A [<button>] (no [type]) with that text, calling [f] on every click for the
    page's lifetime. *)

val test_jpeg : ?color:string -> unit -> (Brr.Blob.t, string) result Fut.t
(** A 64×64 JPEG (quality 0.9): a square of [color] (default ["#2e7d32"]) with a
    red band across. The error is the encoder's, as text. *)

val contains : sub:string -> string -> bool
(** Whether [sub] occurs in the string. *)
