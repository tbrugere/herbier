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
    camera, even one still opening.

    Identification (6a, 6e; architecture §12):
    - The Identifier button (Pl@ntNet's glyph on a paper disc) sits in the name
      field; [aria-disabled] and inert unless {!Record_plan.identify_enabled} (a
      key, online, a photo in the row), with {!Record_plan.identify_line} under
      the field. A tap opens {!Identify} (caller [Noter]) over the row's photos.
    - With « Identifier dès la photo » on, the session's first photos open it at
      once ({!Record_plan.auto_open}; again after « Reprendre la photo »).
    - « Continuer sans attendre » and ← keep the photos and let the request
      finish: the same ask ({!Record_plan.reuses}) gets that request's answer
      again, with no new request, once it is a 200 or a 404
      ({!Record_plan.keep_answer}); any other error is asked again. Nothing in
      4d names a key not exposed: it is 6g's generic error.
    - « Choisir » shows the 6e card in place of the field and the suggestions
      (the owner plant's name, else Pl@ntNet's first French name; the Latin name
      and « Pl@ntNet <n> % »; ✕ back to an empty field), resolves the species on
      GBIF in the background ({!App.resolve_choice}) and says when the
      observation goes to a plant of the collection.
    - « + <organe> » hides the layer over the viewfinder until the next shot or
      gallery pick (added to the row and given to the layer), « Annuler » or
      back.
    - Saving uses {!Record_plan.target} with the choice: an owner plant gets the
      observation; else a new plant linked to the resolved taxon, or to
      Pl@ntNet's own GBIF key while GBIF has not answered or could not be
      reached ({!Choice.taxon}; {!App.create_linked}, the reference fetch after
      the commit); else a free-name plant. It never waits for GBIF nor for
      Pl@ntNet. *)

val v : App.t -> Screen.t
