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
    sends nothing. Writes nothing to storage. *)

val el : unit -> Brr.El.t
