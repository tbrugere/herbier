(** 4h Observation (modal). Header ← / « OBSERVATION » and the plant's name ›
    (its fiche; « À identifier › » opens 4k) / « Terminé ». Under the photo
    mosaic, while the observation is « À identifier »
    ({!Herbier_ui_model.Observation_plan.identifiable}): « Identifier avec
    Pl@ntNet » (as 4k's 6i: disabled offline, without a photo or without a key,
    with the offline or no-photo line, no key line), opening the identification
    layer ({!Identify}) with « Lier » / « + Créer »; a chosen proposal is
    resolved through GBIF, then saved by {!Choice_save} (the observation onto a
    plant of mine, or onto a new free-name or linked plant), the button busy
    until then and a note or date edited meanwhile saved after it; 4h stays and
    shows the plant's name. Then the Drive card while some Drive-bound photo is
    not sent ({!Herbier_ui_model.Drive_text.observation_card}). Cards: the date
    (« Modifier » edits it in a [datetime-local] input), the place, the note
    edited in place. The place: the mini-map ({!Widgets.Mini_map}) when the
    observation has a position and the theme loaded, tapping it opens 5b; under
    it the label, else the derived name, else « Lieu inconnu », then the
    coordinates (["48.0633, 7.0081"]), and « Déplacer » (« Placer sur la carte »
    without position) opening 5b. The accuracy is never written. Actions: «
    Changer d'espèce › » (5c; « Chercher un nom › » → 4k when unlinked), « Voir
    dans le journal › », « Supprimer l'observation › » (confirmation, then the
    observation and its photos are soft-deleted and the modal closes). A failed
    save shows a line under the header. Follows {!App.saved} in place: an open
    input or editor stays open, and so does the dialog unless the photo count
    changed. *)

val v :
  ?arrival:Herbier_ui_model.Observation_plan.arrival ->
  App.t ->
  Herbier_domain.Ids.Observation_id.t ->
  Screen.t
(** [arrival] defaults to [Opened]. [Recorded {identify}] (4d's Enregistrer):
    the URL is rewritten at once to [#observation/<id>] ({!Route.canonicalize}:
    no history entry, no rebuild), so a reload or a history walk shows a plain
    4h; once the data is in, the identification layer opens when
    {!Herbier_ui_model.Observation_plan.opens_layer} (checked again as it
    opens), else the toast {!Herbier_ui_model.Observation_plan.toast} shows for
    {!Herbier_ui_model.Observation_plan.toast_ms}. Only the first rendering does
    this: one made again (the observation gone, then back) is a plain 4h. *)
