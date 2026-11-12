(** 4b Carte: the observations on a full-screen MapLibre map
    ({!Herbier_geo.Map}) under a floating search bar, the « ◎ » button and the
    shared filter chips ({!Filter_chips}).

    Places are {!Herbier_domain.Places.cluster} of every live observation; the
    filters and the search only choose which places, and which of their members,
    are shown ({!Map_filter}). Below {!Herbier_geo.Style.detail_zoom} one point
    per place, merged by MapLibre when they overlap on screen; from it the
    observations themselves. Tapping a group frames it; tapping a point selects
    its place and raises the sheet, which lists the place's shown observations
    (a row opens 4h, or 4k when « À identifier ») and offers « Renommer »,
    written to [place_label] on every member of the place. The sheet is docked
    on the tab bar; the camera and the selected place are kept in
    {!State.map_view} across navigation. Reloads on {!App.saved}. *)

val v : App.t -> Screen.t
