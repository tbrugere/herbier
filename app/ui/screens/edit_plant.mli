(** 5a Modifier la fiche (modal), and the same form for a new plant.

    « Annuler » goes back without saving; « Enregistrer » (inactive while the
    name is blank) saves the name, the aliases and the tags in one {!App.save},
    creating the tags typed with « + tag » that match none ({!Plant_form}), then
    goes back to the fiche — for a new plant, replaces the form with the new
    fiche. A failed save says so under the header and keeps the form.

    In [Edit] mode two cards save at once, apart from « Enregistrer »: « Espèce
    de référence » shows the Latin name and « Changer › », or « nom libre —
    espèce non liée » and « Lier › », which open 4i for the plant (inactive
    offline; refused, with a line under the header, while the form has unsaved
    changes); « Liens de référence » lists the plant's links
    ({!Ref_paste.label}), each but GBIF's with a ✕ that removes it, and « +
    Coller un lien (POWO, INPN…) » stores a pasted link ({!Ref_paste.of_text})
    or says why it cannot. A plant keeps one link per source: a paste for a
    source it already has replaces that link and says « Remplace … ».

    In [Edit] mode the footer « Supprimer la plante et ses n observations › »
    (« … et son observation › », « Supprimer la plante › ») asks for
    confirmation, then soft-deletes, at one instant, the plant, its live
    observations, their photos and the plant's tag links
    ({!Herbier_store.Cascade.plant}), and replaces the route with Collection.
    Originals sent to Google Drive stay there; the outbox carries each deletion.
*)

type mode = Edit of Herbier_domain.Ids.Plant_id.t | New

val v : App.t -> mode -> Screen.t
