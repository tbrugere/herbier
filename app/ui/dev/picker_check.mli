(** Dev-only page [#dev/picker]: Google Picker in this WebView
    (notes/google-picker-webview.md). Shows the build's
    {!Herbier_sync.Backend.google_cloud_project_number} (« non défini » when
    unset). Fields « App id (essai) » (prefilled with that number, else a dummy
    one) and « Clé API (essai) » (type password, empty, never logged or stored),
    so a dev build can try values without rebuilding. Buttons, each logging
    [ok …] or {!Herbier_bindings.Google_picker.error_to_string}: « Charger
    api.js »; « Ouvrir (jeton Drive, sans clé) » and « … avec clé »
    ([Auth.drive_token ~interactive:true] for {!State.account}'s Drive account,
    then the Picker); « Ouvrir (jeton factice, sans clé) » and « … avec clé »
    (token ["ya29.invalid"]: needs no Google account). Logs every callback
    action in order, the picked folder as [picked <mime> <name length> chars],
    and, 3 s after a Picker is shown, the host of each [<iframe>] on the page
    (no query: it carries the token). « Fermer » runs
    {!Herbier_bindings.Google_picker.dismiss}. *)

val el : (App.t, string) result -> Brr.El.t
(** A fresh element; without an app (a desktop browser), the dummy-token buttons
    alone. *)
