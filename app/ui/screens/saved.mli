(** 4e Enregistré: confirmation after 4d. A [moss] ✓, « Enregistré », «
    Observation ajoutée à X » (or « Observation à identifier ») and its place ·
    coordinates · time (with the day when it is not today); the photos' previews
    with the [ochre] « ↑ en attente » badge while they wait for Drive; a card
    per destination saying where the photos go (each photo's own target): the
    Drive one is {!Herbier_ui_model.Drive_text.saved_card} of
    {!App.drive_access}, {!State.network}'s [online], {!State.account}'s
    [wifi_only] and {!App.upload_queue}'s [queued] (it follows them without a
    reload); « Ajouter une note à cette observation » (4h); « Corriger la
    position sur la carte » (5b, back returns here); « Noter une autre plante »
    (4d again) and « Voir la fiche X ». ✕ / back returns to where 4d was opened
    from. Reloaded on {!App.saved}, so the badges and the card follow the
    queue's commits while it is open. *)

val v : App.t -> Herbier_domain.Ids.Observation_id.t -> Screen.t
