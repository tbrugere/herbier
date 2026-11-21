(** 5e Visionneuse (dark modal). Every photo of the plant (cover first), or of
    the observation when it has no plant, in a horizontal [scroll-snap] track;
    each one [contain]ed and pinch-zoomable ({!Widgets.Viewer_zoom}). Top: ✕, «
    i / n », ⋯. Bottom: provenance badge
    ({!Herbier_ui_model.Drive_text.viewer_badge}) and « COUVERTURE » when it is
    the cover, the plant's name, the observation's date · time · place, «
    original introuvable » under it for an original gone from Drive, and the
    chips « Voir l'observation » (4h), « Ouvrir dans Google Drive ↗ » (a link to
    {!Herbier_photos.Drive.view_url}, shown only for an original in Drive,
    {!Herbier_ui_model.Drive_text.viewer_drive}) and « Retirer d'Herbier »
    (confirmation; soft-deletes the photo row only, and clears the plant's cover
    when it named that photo: an original in Drive is never touched). ⋯, shown
    only for a photo of a plant, offers « Définir comme couverture » and, when
    the plant has another observation, « Déplacer vers une autre observation »
    (one of the plant's others). Reloads on {!App.saved}, keeping the photo in
    view; closes when no photo is left. *)

val v : App.t -> Herbier_domain.Ids.Photo_id.t -> Screen.t

val reference :
  App.t ->
  Herbier_domain.Ids.Plant_id.t ->
  Herbier_domain.Reference.Organ.t ->
  Screen.t
(** 5e read-only for 4f's organ photos: the slides of
    {!Herbier_ui_model.Ref_photos.slides} for the plant's stored references and
    ref_images, starting at [organ]. Same track ([scroll-snap] swipe,
    {!Widgets.Viewer_zoom} pinch), ✕ and « i / n » as {!v}; bottom: the organ
    label and the credit line; no ⋯, no badge, no chips, no « Voir l'observation
    ». Each slide shows the thumbnail; when {!State.network} is online, the full
    image ([full_url]) is loaded in an [img] over it and shown once loaded (an
    error keeps the thumbnail). Reloads on {!App.saved} and when the network
    comes back, keeping the organ in view; a reload that changes no slide
    renders nothing anew (the zoom stays) unless the network has come back since
    the rendering; no slide (thumbnails freed, plant gone or unlinked) → {!v}'s
    « gone » notice. A read error is logged to the console ([visionneuse]); on
    the first load it shows the same notice, and a later one keeps what is
    shown. *)
