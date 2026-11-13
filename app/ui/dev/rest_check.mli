(** Dev-only page [#dev/rest]: the PostgREST transport on the device. Shows the
    backend URL ({!Herbier_sync.Backend.supabase_url}), a token field (empty:
    {!Herbier_sync.Auth.access_token}; else a pasted access token, e.g. from
    scripts/local-session.sh), and the buttons « Envoyer une étiquette » (upsert
    of a throwaway, already soft-deleted [tags] row named ["dev-rest <time>"]),
    « Tirer les étiquettes » ({!Herbier_sync_core.Net.Rest.Make.select_since} on
    [tags], since none, then since one minute ago: row count and last
    [updated_at]) and « Jeton invalide » (an upsert with the token ["invalid"]).
    Each request logs its method, path and decoded query, then [ok] or
    {!Herbier_sync_core.Net.Rest.Make.error_to_string}. A button is disabled
    while its run is in flight. The upsert writes to whichever backend the build
    targets (the URL shown), production included if a dev build points there.
    Never prints a token; the field is a password field. *)

val el : (App.t, string) result -> Brr.El.t
(** A fresh element on the app's {!App.auth}, or the app's error string when it
    did not start. *)
