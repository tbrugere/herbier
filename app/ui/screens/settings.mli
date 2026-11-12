(** 4m Réglages (tab). « Où vont mes photos » (Google Drive or Herbier only; no
    Google Photos row, architecture §5) and « Envoyer seulement en Wi-Fi » are
    written to the local [settings] table and kept in {!State.account}. The «
    File d'envoi » count follows {!State.network}. The other rows are static:
    the account card, « Données hors-ligne », and the inert « Libérer » and «
    Envoyer maintenant »; « Copie compressée hors-ligne » is always on, the
    preview being the only local copy. « Noms de lieux »: an intro line (own
    places first, then the sources below, then « Lieu inconnu »), then one
    switch per [Place_name.order] source (« IGN en ligne », « Photon en ligne
    »), each with what it sends to whom, off by default; a tap goes through
    {!App.set_place_source}, whose {!App.place_error} shows below the switches
    (hidden when [None]). *)

val v : App.t -> Screen.t
