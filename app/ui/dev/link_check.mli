(** Dev-only page [#dev/link]: the resolver and the link action on the device
    (architecture §7).
    - « Exemples » resolves fixed links of every kind one after the other and
      logs [Link.to_string] → outcome (key, scientific name, family; candidates
      count and first keys; unresolved reason and query);
    - « Lien ou texte » + « Résoudre » shows the outcome of a pasted input;
      « Chercher » opens 4i ([#chercher/<text>]) prefilled with it;
    - a select of the live plants + « Lier » (enabled on a taxon) calls
      {!App.link}, then opens the plant's fiche (4f). *)

val el : (App.t, string) result -> Brr.El.t
(** A fresh element, or the app's error string when it did not start. « Lier »
    writes to [herbier] (plant, plant ref, reference rows); nothing else does.
*)
