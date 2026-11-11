(** 4m Réglages (tab). « Où vont mes photos » (Google Drive or Herbier only; no
    Google Photos row, architecture §5) and « Envoyer seulement en Wi-Fi » are
    written to the local [settings] table and kept in {!State.account}. The «
    File d'envoi » count follows {!State.network}. The other rows are static:
    the account card, « Données hors-ligne », and the inert « Libérer » and «
    Envoyer maintenant »; « Copie compressée hors-ligne » is always on, the
    preview being the only local copy. *)

val v : App.t -> Screen.t
