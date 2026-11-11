(** Giving an observation its plant, from my collection.

    [Identify] is 4k: « À IDENTIFIER · i / n » with « Suivante › », the
    observation's card, a search over my collection whose rows link the
    observation when tapped, « Coller un lien » (shown, inert), and « Nom libre
    », which creates a 4g plant named by the search text and links to it. After
    a link the next unidentified observation replaces this one; after the last,
    the modal closes.

    [Change] is 5c: « Actuellement X », the same search (the current plant
    greyed and inert), « Nom libre », and « Remettre “À identifier” ». When the
    plant left behind has no other observation, a dialog asks « Garder la fiche
    / Supprimer la fiche » (deleting soft-deletes it and its tag links); then
    the modal closes.

    Neither follows {!App.saved}: the observation and its plant are read on
    entry; the search queries the store as the text changes. *)

type mode = Identify | Change

val v : App.t -> mode -> Herbier_domain.Ids.Observation_id.t -> Screen.t
