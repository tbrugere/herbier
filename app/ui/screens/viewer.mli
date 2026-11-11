(** 5e Visionneuse (dark modal). Every photo of the plant (cover first), or of
    the observation when it has no plant, in a horizontal [scroll-snap] track;
    each one [contain]ed and pinch-zoomable ({!Widgets.Viewer_zoom}). Top: ✕, «
    i / n », ⋯. Bottom: provenance badge and « COUVERTURE » when it is the
    cover, the plant's name, the observation's date · time · place, and the
    chips « Voir l'observation » (4h) and « Retirer d'Herbier » (confirmation;
    soft-deletes the photo row only, and clears the plant's cover when it named
    that photo: an original in Drive is never touched). ⋯, shown only for a
    photo of a plant, offers « Définir comme couverture » and, when the plant
    has another observation, « Déplacer vers une autre observation » (one of the
    plant's others). Reloads on {!App.saved}, keeping the photo in view; closes
    when no photo is left. *)

val v : App.t -> Herbier_domain.Ids.Photo_id.t -> Screen.t
