(** 4c Journal: every observation, newest first, grouped by local day under a
    header with the day's place. Filters: one chip per year present (filled =
    active; none active = every year), « À identifier · n », and the tag chips;
    all of them are {!State.filters}, shared with Collection. With tags active,
    only observations of plants carrying all of them are listed.

    A chip whose filter is on stays while no observation matches it, so it can
    be turned off. Reloads on {!App.saved}; a failed read shows in the counter.
    A row opens 4h, or 4k when it is « À identifier »; a long press on a row
    asks to delete the observation ({!List_delete}); rows show no photo count. A
    day's place is a button, « <place> ◎ », when at least one of its shown
    observations has a position: it opens 4b framing them ({!State.focus_map}).
    A day with a place name but no position shows the name alone, without ◎. *)

val v : App.t -> Screen.t
