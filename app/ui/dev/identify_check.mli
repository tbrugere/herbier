(** Dev-only page [#dev/identify] (docs/notes/plantnet-webview.md). Sends
    Pl@ntNet identify requests from this WebView (origin https://localhost) with
    a key pasted on the page: the app never stores, logs or shows it back
    (autocomplete off is only a hint to the system's autofill). Fields « Clé API
    (essai) » (type password, empty at each visit) and « Flore » (prefilled
    ["all"]). Buttons, one request at a time (all disabled while one is in
    flight, each request aborted after 60 s): « Flores (gratuit) »
    ([GET /v2/projects?lang=fr]); « 1 aperçu » (one gallery photo, its device
    preview, [organs=auto]); « Aperçu q0.7 et q0.9 » (one gallery photo: its
    preview, then, when that answered 2xx, a q0.9 encode of the same original at
    the same size; two requests, two credits); « 5 aperçus » (up to five gallery
    photos, their previews, one request). The photos are sent as
    [photo-<i>.jpg], never under their gallery name. Each answer logs one line,
    [<label>: HTTP <status> in <ms> ms, <n> photo(s), <bytes> bytes sent,
     <chars> chars answered] or [<label>: failed (<JS error>) after <ms> ms],
    and its body verbatim in a [<pre data-answer="<label>">] inside a
    [<details>] (labels [projects], [one], [q07], [q09], [five]); the body is
    shown verbatim, not decoded. Without a key, a click logs « pas de clé » and
    sends nothing. Writes nothing to storage.

    Below, a block « Identify_io » goes through the app's identification
    ({!App.identify}, {!App.floras}: the 30 s transport, the offline gate, the
    flora cache, the console lines), with the same two fields read as typed (a
    key of spaces reaches {!App.identify}, which answers [no key] and sends
    nothing) and one {!App.channel} for the page: « Flores (Identify_io) » logs
    [flores : <n>], [flores : hors-ligne : rien envoyé] or
    [flores : erreur : <error>] (a second click answers from the session's list,
    with no new console line); « Identifier 1 photo (Identify_io) » sends one
    gallery photo's preview, in memory ([Preview], [organs=auto]); « Identifier
    le dernier aperçu stocké » sends the newest live photo's stored preview
    ([Stored]; « aucune photo stockée » and nothing sent when there is none).
    These two are never disabled while a request runs, so two quick taps send
    two requests and the first answer shows « réponse dépassée ». An answer
    shows [flore : <flora|?>, reste : <remaining|?>, incertain : <bool>], then
    an [<ol data-proposals>] with one [<li data-score="<score>">] per proposal
    in Pl@ntNet's order:
    [<percent> % · <scientific name> · <family|—> · <common names> · GBIF
     <id|—>], its closest images as
    [<img src=<small> alt="<scientific name>, <organ>" title=<credit>
     loading=lazy>] and its « +N »; an error shows [erreur : <error>], offline «
    hors-ligne : rien envoyé », a stored preview that cannot be read « aperçu
    illisible : <photo id>, rien envoyé ». *)

val el : (App.t, string) result -> Brr.El.t
(** Without an app (a desktop browser), the Identify_io block shows the app's
    error and its buttons are disabled; the spike still works. *)
