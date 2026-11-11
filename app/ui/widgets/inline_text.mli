(** Text edited in place (4f « Mes notes », 4h « Note de cette rencontre »): the
    text as a button, a textarea in its place on tap. *)

type t = {el : Brr.El.t; bindings : Rb.binding list}

val v :
  ?cls:string ->
  label:string ->
  placeholder:string ->
  save:(string -> bool Fut.t) ->
  string React.signal ->
  t
(** [v ~placeholder ~save value] shows [value] ([placeholder] in [hint] while it
    is empty). Leaving the textarea, or releasing the bindings while it is open
    (removing a focused element fires no [blur]: Android back), calls [save]
    with the trimmed text when it differs from [value]. [save] may run inside an
    update step, so it only starts its work (an {!App.save}). When its future is
    [false] the text is kept and offered again on the next tap. [cls] is added
    to both the text and the textarea (the type role, e.g. ["t-notes"]); [label]
    names the textarea for screen readers. *)
