(** 4f / 4g Fiche espèce (modal), 4g until it has a reference: a hero paging
    through my photos, cover first (stripes without one), with ← and ✎ (→ 5a),
    the « local » badge, the latest observation's place and date, the name and
    the scientific name (or « nom libre — espèce non liée »); the tags and
    « + tag »; « Mes observations · n », each row opening 4h; « Mes notes »,
    edited in place and saved when the field is left or the fiche closed; the
    reference block reduced to the 4g text, its button inert.

    « + tag » puts a tag of that name on the plant, creating it when no tag has
    that name ({!Plant_form.add_tag}'s matching). On {!App.saved} the fiche
    reloads and updates what it shows in place, an open field staying open. A
    failed save says so under the hero. A plant that is not (or no longer) live,
    or a fiche that could not be read, shows a short notice under ←. *)

val v : App.t -> Herbier_domain.Ids.Plant_id.t -> Screen.t
