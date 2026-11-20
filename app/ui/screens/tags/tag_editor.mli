(** 4l's tag box: a centred box over a veil (the {!Widgets.Dialog} look), opened
    on a {!Herbier_ui_model.Tag_edits.editor}. The name field (focused on open,
    Enter = the primary button when enabled, Escape = Annuler), the line of
    {!Herbier_ui_model.Tag_edits.primary}, the primary button (aria-disabled
    when not enabled), in [Edit] « Supprimer le tag » (danger), which asks
    {!Herbier_ui_model.Tag_edits.delete_title} /
    {!Herbier_ui_model.Tag_edits.delete_text} in a {!Widgets.Dialog} with «
    Supprimer » / « Annuler » (Annuler and Escape go back to the field), and «
    Annuler ». While open it is an {!Overlay} ([Light]): Android back closes it,
    the question included. A change is written with {!App.save} at once; while
    it runs the buttons and {!t.open_} do nothing; a failure keeps the box open
    with « Enregistrement impossible : rien n’a été modifié. », unless back
    closed it meanwhile (then it is only logged). *)

type t = {
  el : Brr.El.t;  (** put it once in the screen; [position: fixed] *)
  open_ : Herbier_ui_model.Tag_edits.editor -> unit;
      (** call outside update steps; replaces what the box was open on *)
  saved : Herbier_ui_model.Tag_edits.change React.event;
      (** after a successful save; the box is already closed and
          {!State.filters} already follows the change
          ({!Herbier_ui_model.Tag_edits.followed}) *)
  bindings : Rb.binding list;
      (** releasing them closes it and removes its overlay *)
}

val v : App.t -> tags:Herbier_domain.Tag.t list React.signal -> t
(** [tags]: the live tags, for {!Herbier_ui_model.Tag_edits.check}. A change's
    {!Herbier_ui_model.Tag_edits.plan} is saved as one {!App.save} (one
    transaction), after reading again what a pull may have changed since the box
    opened: a merge relinks the plants carrying the merged tag at save time, a
    rename writes over the tag as stored then (a tag gone meanwhile is a
    failure). *)
