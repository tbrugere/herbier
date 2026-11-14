(** Dev-only page [#dev/uploader] (architecture §5, §10 spike 1 part 3): the
    originals' upload job and queue, on the emulator, without Google.

    « Plugin »: a sink base URL (default [http://localhost:8787/upload], the
    [scripts/upload-sink.mjs] server reached through [adb reverse]) and a size
    in bytes (default 2 MB); « Écrire un fichier » writes that many random bytes
    at [originals/dev-<n>] and logs their SHA-256; « Envoyer (Wi-Fi seulement) »
    / « Envoyer (tout réseau) » run
    [Cap_uploader.enqueue ~id:"dev-<n>" ~url:(base ^ "/dev-<n>")] on the last
    file written; « Annuler » cancels it; the job list (state, attempts, status,
    body) follows [Cap_uploader.on_change] and « Rafraîchir ».

    « File »: the app's queue ({!App.uploads}): each row's photo id, photo
    state, job state, attempts, last error and whether it holds a session (never
    its URL); « Passe silencieuse » / « Passe interactive » run a pass. *)

val el : (App.t, string) result -> Brr.El.t
(** Without an app (a desktop browser), the plugin part alone (its calls log
    [Unavailable "uploader"]). *)
