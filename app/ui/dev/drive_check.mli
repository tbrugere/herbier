(** Dev-only page [#dev/drive] (architecture §10, spike 4). Shows
    {!Herbier_sync.Auth}'s status and
    {!Herbier_sync_core.Auth.Drive_consent.scope}; each button logs [ok …] or
    the error string (never a token, only its length): « Autoriser Drive »
    ([Auth.drive_token ~interactive:true]); « Jeton silencieux »
    ([~interactive:false]); « Plugin seul »
    ([Cap_google_authorization.authorize ~account:None ~interactive:false], past
    the account gate: proves the native wiring on a device with no Google
    account); « Envoyer un fichier test »: a field « Espèce » (default «
    Digitalis purpurea »; the folder name as typed, trimmed, « À identifier »
    when blank), a 64×64 JPEG drawn on a canvas ([Canvas_jpeg]), a fresh
    [Photo_id], its sha256 ([Photos_io.Preview.sha256_hex]),
    [Photos_io.Drive.put_original] with [Auth.drive_token ~interactive:true],
    [Auth.drop_drive_token], run through [Photos_io.Drive_root.run], then «
    root: keep | store | forget » (no id; « <label>: root folder: <error> » and
    nothing sent when the setting read fails), then [Created]/[Already_there]
    with the file id and webViewLink (each request is a « drive: … » console
    line); « Renvoyer le même » (same photo id and bytes: must log
    [Already_there]); « Vérifier » ([Photos_io.Drive.presence] of the last file
    id); « Jeton invalide »: [put_original ~root:None] with a token source that
    always answers ["ya29.invalid"] and a counting [drop_token]: two 401s, one
    drop, then [Drive Unauthorized] (its root change ignored). A line « Dossier
    racine : <id> » (« aucun » when unset or blank, « illisible : <error> » when
    the read fails), re-read after each step; « Oublier le dossier » runs
    [Drive_root.forget] (« forget root: ok »).

    The health check and 5e's Drive rows: « Vérifier les originaux »
    ([Photos_io.Health.run ~force:true] on {!App.health}, then the stored
    [Drive_health_checked_at]); « Original envoyé (factice) » / « Original
    introuvable »: {!mark_original}, to reach 5e's rows on a device with no
    Drive. Its writes go through {!App.save}, so they sync: use it against the
    local Supabase stack only. *)

type mark = Uploaded | Missing

val mark_original : App.t -> mark -> (string, string) result Fut.t
(** On the newest live Drive-bound photo, through {!App.save}:
    [Photos.set_upload ~state:Uploaded ~drive_file_id:(Some "herbier-dev-file")],
    or [~state:Original_missing] keeping its file id (["herbier-dev-file"] when
    it has none). [Ok "<photo id> <state>"]; no such photo or a store error →
    [Error]. Also [herbierDev.markOriginal] ({!Hooks.install_app}). *)

val el : (App.t, string) result -> Brr.El.t
(** A fresh element on the app's {!App.auth}; without an app (a desktop browser,
    where the store does not open), the app's error string and « Plugin seul »
    alone, which logs [Unavailable "googleAuthorization"]. *)
