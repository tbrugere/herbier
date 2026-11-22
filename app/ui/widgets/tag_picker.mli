(** The fiche's « + tag » and 5a's « Tags » picker: the dashed « + tag » pill
    turns into a combobox listing the existing tags
    ({!Herbier_ui_model.Tag_pick.suggestions}), filtered as one types, with a
    last « Créer « … » » row when the text names no tag. A tap or Enter adds the
    row (the highlighted one for Enter, moved with the arrows) and keeps the
    field open for the next; Escape or leaving the field turns it back into the
    pill, adding nothing. *)

type t = {
  el : Brr.El.t;
  added : string React.event;
      (** the name to put on the plant: an existing tag's, or a new one *)
  bindings : Rb.binding list;
}

val v :
  placeholder:string ->
  suggest:(string -> Herbier_ui_model.Tag_pick.entry list) ->
  unit ->
  t
(** [suggest text]: the rows for the text typed, read each time it changes, when
    the field opens and after each addition (once the screen has taken it). *)
