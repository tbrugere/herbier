(** 4m Réglages (tab). The account card follows {!State.account}'s [auth]: « Se
    connecter » when signed out, the address and « Changer » when signed in
    (both {!Herbier_sync.Auth.sign_in}, the current session kept until a new one
    is made), no button while the session is read or when the build has no
    sign-in; a failed attempt leaves one line under the card until the next tap
    (none for a dismissed chooser). « Où vont mes photos » (Google Drive or
    Herbier only; no Google Photos row, architecture §5) and « Envoyer seulement
    en Wi-Fi » are written to the local [settings] table and kept in
    {!State.account}. The « File d'envoi » count follows {!State.network}. The
    other rows are static: « Données hors-ligne », and the inert « Libérer » and
    « Envoyer maintenant »; « Copie compressée hors-ligne » is always on, the
    preview being the only local copy. « Noms de lieux »: an intro line (own
    places first, then the sources below, then « Lieu inconnu »), then one
    switch per [Place_name.order] source (« IGN hors-ligne », « IGN en ligne »,
    « Photon en ligne »), each with what it sends to whom, off by default; a tap
    goes through {!App.set_place_source}, whose {!App.place_error} shows below
    the switches (hidden when [None]). Under « IGN hors-ligne »: one row per
    {!App.packs} (« <code> · <name> », its size and commune count or « Fichier
    illisible », and « Supprimer » through {!App.delete_pack}, inert while that
    delete runs), {!Pack_text.no_pack} when there is none and the switch is on,
    then « Ajouter un département » (inert while {!App.downloading}; it controls
    the picker list, [aria-controls]): it fetches {!App.departements} once per
    screen (« Chargement… », an error and « Réessayer »), then focuses a search
    field over the départements not downloaded yet, filtered with
    [Herbier_store.Search.matches] on « <code> <name> »; a tap downloads it
    ({!App.download_pack}). While {!App.downloading} is [Some d], on this screen
    or one opened again meanwhile, the list and field are hidden and a status
    line says « Téléchargement de <d.name>… ». Success closes the picker; an
    error goes to the status line under the list (out of the scrolled list) and
    the list comes back. The IGN attribution ends the block. A tap on « Ajouter
    un département » while the picker is open closes it. *)

val v : App.t -> Screen.t
