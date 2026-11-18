(** 4f / 4g Fiche espèce (modal), 4g until it has a reference: a hero paging
    through my photos, cover first (stripes without one), with ← and ✎ (→ 5a),
    the « local » badge, the latest observation's place and date, the name and
    the scientific name (or « nom libre — espèce non liée »); the tags and
    « + tag »; « Mes observations · n », each row opening 4h; « Mes notes »,
    edited in place and saved when the field is left or the fiche closed; the
    reference block: without a gbif_key, the 4g text and two 52 px buttons (6k):
    « Identifier » (moss, glyph 20) and « Chercher un nom » (bordered, → 4i for
    this plant), both disabled offline with 4g's offline text; « Identifier »
    also disabled without a key (the Réglages line) or without a photo (its
    line). « Identifier » opens the identification layer over the fiche (caller
    [Free_name id]) on the photos of {!Herbier_ui_model.Free_name.sent} (newest
    observation with photos, first five), with no note; « + <organe> » there
    picks a gallery photo and saves it on that observation. A proposal's « Lier
    » resolves it through GBIF ({!App.resolve_choice}), then {!App.link} [~name]
    (Pl@ntNet's first French name; the free name becomes an alias); the fiche
    reloads on {!App.saved} and the 4f block replaces 4g's. The fiche left
    before GBIF answers links nothing. When the layer closes, the focus goes
    back to « Identifier » (busy while GBIF resolves). GBIF knowing no such
    species, or GBIF unavailable without a Pl@ntNet id, links nothing and says
    so under the hero. A key not exposed is the layer's generic « Pl@ntNet n'a
    pas répondu »: the fiche adds no text about it. With a gbif_key (4f) a
    header « Référence · mis à jour il y a … » (« mise à jour… » while
    {!App.fetching}, « · hors-ligne » added offline) with ↻ ({!App.refresh};
    inert while fetching or offline), then the « Noms » row (vernacular names
    per language, family and sources) of the stored references, or «
    Récupération de la référence… » while a fetch runs and there is nothing to
    show yet, or « Référence indisponible pour l'instant. » when there is
    nothing to show and no fetch runs. Opening the fiche calls
    {!App.refresh_if_due} once.

    « + tag » puts a tag of that name on the plant, creating it when no tag has
    that name ({!Plant_form.add_tag}'s matching). On {!App.saved} the fiche
    reloads and updates what it shows in place, an open field staying open. A
    failed save says so under the hero. A plant that is not (or no longer) live,
    or a fiche that could not be read, shows a short notice under ←. *)

val v : App.t -> Herbier_domain.Ids.Plant_id.t -> Screen.t
