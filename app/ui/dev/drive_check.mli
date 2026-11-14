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
    [Photos_io.Drive.put_original] with [Auth.drive_token ~interactive:true] and
    [Auth.drop_drive_token], then [Created]/[Already_there] with the file id and
    webViewLink (each request is a « drive: … » console line); « Renvoyer le
    même » (same photo id and bytes: must log [Already_there]); « Vérifier »
    ([Photos_io.Drive.presence] of the last file id); « Jeton invalide »:
    [put_original] with a token source that always answers ["ya29.invalid"] and
    a counting [drop_token]: two 401s, one drop, then [Drive Unauthorized]. *)

val el : (App.t, string) result -> Brr.El.t
(** A fresh element on the app's {!App.auth}; without an app (a desktop browser,
    where the store does not open), the app's error string and « Plugin seul »
    alone, which logs [Unavailable "googleAuthorization"]. *)
