(** Dev-only page [#dev/auth]: the account on the device. Shows where this build
    signs in ({!Herbier_sync.Backend}: the URL, the key's first 16 characters,
    whether the Google client id is set and its first 12), the live
    {!Herbier_sync.Auth.status} and the access token's expiry (local time and
    seconds left when drawn), redrawn when a 1 s poll sees either change or on «
    Actualiser », and the buttons « Se connecter », « Rafraîchir maintenant », «
    Expirer » ({!Herbier_sync.Auth.debug_expire}), « Se déconnecter », each
    logging [ok] or {!Herbier_sync.Auth.error_to_string}. Never prints a token.
*)

val status_to_string : Herbier_sync.Auth.status -> string
(** ["Unconfigured"], ["Restoring"], ["Signed_out"], ["Signed_in <email>"]
    (["(no address)"] without one); #dev/sync shows it too. *)

val el : (App.t, string) result -> Brr.El.t
(** A fresh element on the app's {!App.auth} (the one main started), or the
    app's error string when it did not start. The poll runs until the page is
    left (the router reloads it). *)
