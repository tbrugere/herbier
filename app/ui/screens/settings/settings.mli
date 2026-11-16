(** 4m Réglages (tab). The account card follows {!State.account}'s [auth]: « Se
    connecter » when signed out, the address and « Changer » when signed in
    (both {!Herbier_sync.Auth.sign_in}, the current session kept until a new one
    is made), no button while the session is read or when the build has no
    sign-in; a failed attempt leaves one line under the card until the next tap
    (none for a dismissed chooser). Signed in, its meta is
    {!Herbier_ui_model.Drive_text.account_meta} (the address: this is the sync
    account; Drive has its own, chosen under « Dossier Drive »). Opening the
    screen runs {!App.check_drive_access}. « Où vont mes photos » (Google Drive
    or Herbier only; no Google Photos row, architecture §5) goes through
    {!App.set_storage}; choosing « Dans Herbier seulement » while originals wait
    on this phone ({!Herbier_ui_model.Drive_text.pending_count} of
    {!App.upload_queue} > 0) first asks, in a dialog built at the tap for that
    count ({!Herbier_ui_model.Drive_text.stop_dialog}): « Les envoyer quand même
    » (the setting only), « Ne pas les envoyer » ({!App.stop_drive_uploads},
    then the setting only when it succeeded) or « Annuler ». A failed write
    leaves one line under the radios (« Le réglage n’a pas pu être enregistré.
    », or « Les photos en attente n’ont pas pu être retirées : rien n’a changé.
    ») until the next successful choice. Below them, while the storage is Drive
    or originals wait on this phone, {!Folder_button} (« Dossier Drive »: the
    Drive account and folder, the Drive prompt and « Autoriser »); the Drive
    radio's title names {!App.drive_folder}. « Envoyer seulement en Wi-Fi » is
    written to the local [settings] table and kept in {!State.account}. « File
    d'envoi » follows {!App.upload_queue}:
    {!Herbier_ui_model.Drive_text.queue_title},
    {!Herbier_ui_model.Drive_text.queue_status} (hidden when [None]),
    {!Herbier_ui_model.Drive_text.last_sent} (read again when the queue
    changes), and « Envoyer maintenant » ({!App.send_now}), [aria-disabled]
    unless {!Herbier_ui_model.Drive_text.send_enabled}; below its card,
    {!Pending} (no retry or discard action). « Données hors-ligne » is
    {!Offline_row}. « Copie compressée hors-ligne » is always on, the preview
    being the only local copy. « Noms de lieux »: an intro line (own places
    first, then the sources below, then « Lieu inconnu »), then one switch per
    [Place_name.order] source (« IGN hors-ligne », « IGN en ligne », « Photon en
    ligne »), each with what it sends to whom, off by default; a tap goes
    through {!App.set_place_source}, whose {!App.place_error} shows below the
    switches (hidden when [None]). Under « IGN hors-ligne »: one row per
    {!App.packs} (« <code> · <name> », its size and commune count or « Fichier
    illisible », and « Supprimer » through {!App.delete_pack}, inert while that
    delete runs), {!Pack_text.no_pack} when there is none and the switch is on,
    then « Ajouter un département » (inert while {!App.downloading}; it controls
    the picker list, [aria-controls]): it fetches {!App.departements} once per
    screen (« Chargement… », an error and « Réessayer »), then focuses a search
    field over the départements not downloaded yet, filtered with
    [Herbier_domain.Fold.matches] on « <code> <name> »; a tap downloads it
    ({!App.download_pack}). While {!App.downloading} is [Some d], on this screen
    or one opened again meanwhile, the list and field are hidden and a status
    line says « Téléchargement de <d.name>… ». Success closes the picker; an
    error goes to the status line under the list (out of the scrolled list) and
    the list comes back. The IGN attribution ends the block. A tap on « Ajouter
    un département » while the picker is open closes it. *)

val v : App.t -> Screen.t

val drive_sheet : App.t -> Screen.t
(** {!Drive_sheet.v}: 4m « Dossier Drive »'s sheet ([Route.Modal Drive_folder]).
*)
