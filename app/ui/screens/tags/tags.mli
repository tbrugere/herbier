(** 4l Tags (modal): the four most used tags as cards, the others as chips with
    their plant count. A tap filters the collection by that tag alone and
    returns to Collection ([history.back()]). Each card and chip has a pencil
    button (« Modifier « <nom> » ») and a long-press, both opening {!Tag_editor}
    on it; the « + » button at the bottom right ({!Widgets.Fab}, « Nouveau tag
    ») opens it to create one. The pencils, long-presses and « + » do nothing («
    \+ » aria-disabled) until a read of the tags has succeeded since the box's
    last save. The list is read again on {!App.saved} (each save of the box, a
    pull) and patched, not rebuilt. The subtitle says when there is no tag or
    the read failed ({!Herbier_ui_model.Tag_edits.subtitle}). Covers are
    placeholders. *)

val v : App.t -> Screen.t
