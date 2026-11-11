(** 4a Collection: title and counter, search, tag chips, the 2-column grid of
    plant cards. Search and tag chips filter the grid by patching it, so only
    the cards that arrive, leave or change are rendered. The tag chips set
    {!State.filters} (shared with Carte and Journal); the search text is this
    screen's own.

    Reads the store when entered and the plants again on every filter change;
    the counter is the whole collection, not the filtered grid, and the
    observation counts are those read on entry. A failed read shows in the
    counter (on entry) or in a line above the grid (on a filter change). With no
    plant, 4n replaces the search, chips and grid. "Tags ›" opens 4l; a card
    opens its fiche (4f). Covers are the "no photo" state; "Coller un lien" does
    nothing; the first-plant button opens Noter (4d). *)

val v : App.t -> Screen.t
(** Reloads (counter, tags, grid) whenever {!App.saved} fires. *)
