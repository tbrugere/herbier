(** 5a Modifier la fiche (modal), and the same form for a new plant.

    « Annuler » goes back without saving; « Enregistrer » (inactive while the
    name is blank) saves the name, the aliases and the tags in one {!App.save},
    creating the tags typed with « + tag » that match none ({!Plant_form}), then
    goes back to the fiche — for a new plant, replaces the form with the new
    fiche. A failed save says so under the header and keeps the form.

    In [Edit] mode the footer « Supprimer la plante et ses n observations › »
    (« … et son observation › », « Supprimer la plante › ») asks for
    confirmation, then soft-deletes, at one instant, the plant, its live
    observations, their photos and the plant's tag links
    ({!Herbier_store.Cascade.plant}), and replaces the route with Collection.
    The originals stay in Google Photos; the outbox carries each deletion. *)

type mode = Edit of Herbier_domain.Ids.Plant_id.t | New

val v : App.t -> mode -> Screen.t
