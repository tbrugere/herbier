(** 4d Noter (dark full-screen modal). The back camera fills the screen; on top,
    ✕ (asks before dropping photos already taken), the « hors-ligne · n en
    attente » pill when offline, and the GPS pill (« Position acquise » once a
    fix arrives; asked for at opening, never awaited). Below: the thumbnail row
    (each with ✕; the dashed « galerie » box opens the system picker), the
    optional name with suggestions (my collection first, then « Vues ici » from
    observations within 500 m of the fix), and [↻ flip camera]
    [Enregistrer (n photos)] [● shutter].

    Saving never waits for the network: the plant (an existing one when the name
    matches, else a new 4g plant; none → « À identifier »), the observation
    (dated and placed by the first photo's EXIF; without an EXIF date, now;
    without an EXIF position, the fix only for a photo taken within 10 min,
    {!Record_plan.when_where}), then each photo's preview and [pending] row
    ({!App.save_photos}), all local; the controls wait meanwhile. Then 4e
    replaces 4d. A failure keeps 4d with a message: the observation's, or « n
    photos non enregistrées » with those photos still in the row, Enregistrer
    retrying them on the same observation. Releasing the screen stops the
    camera, even one still opening. *)

val v : App.t -> Screen.t
