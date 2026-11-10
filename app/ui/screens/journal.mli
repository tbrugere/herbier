(** 4c Journal: every observation, newest first, grouped by local day under a
    header with the day's place. Filters: one chip per year present (filled =
    active; none active = every year), « À identifier · n », and the tag chips;
    all of them are {!State.filters}, shared with Collection. With tags active,
    only observations of plants carrying all of them are listed.

    A chip whose filter is on stays while no observation matches it, so it can
    be turned off. Reloads on {!App.saved}; a failed read shows in the counter.
    Rows and the day's ◎ are not interactive; rows show no photo count. *)

val v : App.t -> Screen.t
