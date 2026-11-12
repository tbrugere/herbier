(** 4h Observation (modal). Header ← / « OBSERVATION » and the plant's name ›
    (its fiche; « À identifier › » opens 4k) / « Terminé ». Cards: the date («
    Modifier » edits it in a [datetime-local] input), the place, the note edited
    in place. The place: the mini-map ({!Widgets.Mini_map}) when the observation
    has a position and the theme loaded, tapping it opens 4b centred on the
    observation ({!State.focus_map}); under it the label, else the derived name,
    then the coordinates (["48.0633, 7.0081"]). The accuracy is never written.
    Actions: « Changer d'espèce › » (5c; « Identifier › » → 4k when unlinked), «
    Voir dans le journal › », « Supprimer l'observation › » (confirmation, then
    the observation and its photos are soft-deleted and the modal closes). A
    failed save shows a line under the header. Follows {!App.saved} in place: an
    open input or editor stays open, and so does the dialog unless the photo
    count changed. *)

val v : App.t -> Herbier_domain.Ids.Observation_id.t -> Screen.t
