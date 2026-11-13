(** Giving an observation or a plant its species: my collection and GBIF's
    reference search (4i, 4k, 5c).

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

    In both, « Référence · GBIF » ({!Ref_results}) lists GBIF's species for the
    same text: a species a plant of mine has links the observation to it (« Lier
    › »); another one's « + » creates a plant linked to it (named by its French
    name, else its Latin one) and moves the observation there, in one save.

    [Search] is 4i: my collection, whose rows open the fiche (« Ouvrir »), and
    the reference section, whose « Ouvrir › » opens the plant that has the
    species and whose « + » creates a linked plant and replaces the route with
    its fiche. Offline or after a failed search, « Créer avec un nom libre »
    creates a free-name plant (4g) instead.

    [Link_plant] is 4i for one plant (4g « Lier », 5a « Changer › »): the
    reference section alone, prefilled with the plant's Latin name, else its
    display name; « + » links the plant ({!App.link}: a free-name plant takes
    the row's name, its old name becoming an alias) and goes back.

    [Intercept] is 4j, the sheet for a link or share from another app
    ({!Intake}): « HERBIER · LIEN … RECONNU » and ✕, then the species the link
    names ({!Herbier_refs_io.Resolver.resolve}, its French name from
    {!Herbier_refs_io.Resolver.named}), « Première observation ici » (dated now,
    at the GPS fix when one arrived, « Enlever » / « Remettre »), the recent
    tags ({!Herbier_ui_model.Intercept.recent_tags}) and « Ajouter à ma
    collection », which creates the linked plant with that observation and tags
    in one save. When a live plant already has the species: « Déjà dans ma
    collection » and « Ajouter cette observation », which adds them to that
    plant. Offline it says so and resolves when the network returns; a failed
    lookup offers « Réessayer ». Free text, an observation link or a link naming
    no species replace 4j with 4i prefilled, and so does « Pas la bonne espèce ?
    Chercher »; for a link from another app, the automatic fallback (not «
    Chercher ») tells {!Intake.fell_back}. After the save, the fiche when «
    Ouvrir la fiche après » is on; else, and on ✕, the route goes back and, for
    a link from another app ([outside]), the app is minimized, so the app the
    link came from shows again.

    A row's « + » first reads the accepted taxon of a synonym
    ({!Herbier_refs_io.Resolver.chosen}) and decides again on it. None follows
    {!App.saved}: what is shown is read on entry; the searches run as the text
    changes. *)

type mode =
  | Identify of Herbier_domain.Ids.Observation_id.t  (** 4k *)
  | Change of Herbier_domain.Ids.Observation_id.t  (** 5c *)
  | Search of string  (** 4i, prefilled with this query *)
  | Link_plant of Herbier_domain.Ids.Plant_id.t  (** 4i for one plant *)
  | Intercept of {text : string; outside : bool}
      (** 4j, the text of a link or share; [outside]: from another app *)

val v : App.t -> mode -> Screen.t
