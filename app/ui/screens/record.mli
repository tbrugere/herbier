(** 4d Noter (dark full-screen modal). The back camera fills the screen; on top,
    ✕ (asks before dropping photos already taken), the « hors-ligne · n en
    attente » pill when offline, and the GPS pill (« Position acquise » once a
    fix arrives; asked for at opening, never awaited). Below: the thumbnail row
    (each with ✕; the dashed « galerie » box opens the system picker), the
    optional name with suggestions (my collection first, then « Vues ici » from
    observations within 500 m of the fix), and the controls row [⇄ flip camera]
    [● shutter, photo_camera] [✓ Enregistrer].

    Enregistrer is [disabled] until {!Shot_row.can_save} (a photo in the row and
    no capture pending); a shutter tap shows a striped placeholder at once, in
    the click listener ({!Shot_row.begin_capture}), replaced by the preview,
    removed on a failed capture (logged). While 4d is up, the volume-down key
    does what a shutter tap does ({!Herbier_bindings.Cap_volume_key}: one shot
    per press, the volume left alone); released with the screen.

    Saving never waits for the network: the plant (an existing one when the name
    matches, else a new 4g plant; none → « À identifier »), the observation
    (dated and placed by the first photo's EXIF; without an EXIF date, now;
    without an EXIF position, the fix only for a photo taken within 10 min,
    {!Record_plan.when_where}), then each photo's preview and [pending] row
    ({!App.save_photos}), all local; the controls wait meanwhile. Then 4h of the
    new observation replaces 4d (route [Recorded], [identify] =
    {!Record_plan.identify_after_save}; 4h decides whether the layer opens,
    {!Herbier_ui_model.Observation_plan.opens_layer}). A failure keeps 4d with a
    message: the observation's, or « n photos non enregistrées » with those
    photos still in the row, Enregistrer retrying them on the same observation.
    Releasing the screen stops the camera, even one still opening. *)

val v : App.t -> Screen.t
