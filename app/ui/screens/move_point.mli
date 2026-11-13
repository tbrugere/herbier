(** 5b Déplacer le point (modal, no tab bar). A full-screen interactive MapLibre
    map ({!Herbier_geo_io.Map}, [interactive:true]) above a drawer; the point is
    the map's centre, shown by a fixed pin (DOM, not a map layer, whose foot is
    exactly the centre of the map element) while the map slides under it.

    Top: ✕ (back, nothing saved), the pill « Glissez la carte sous le point »,
    and [my_location] (flies to the device's fix at
    [max zoom Move_plan.initial_zoom]; a failure shows {!Map_sheet.notice_text}
    of {!Map_sheet.position_failure} in the pill, until the next fix; a fix that
    arrives before the map exists is flown to once it does). The pill and the
    drawer's line are [role="status"] live regions. The origin ghost: the stored
    position ({!Herbier_geo_io.Map.set_origin}); none when the observation had
    no position.

    Drawer: {!Move_plan.title} (20/800) and {!Move_plan.meta}, both following
    the camera after each [moveend]; the « Chercher un lieu » field, whose
    submit (Enter or its « OK ») runs {!Herbier_geo_io.Geocoder.search}
    [~near:centre] — only the latest query's reply is shown; when « Photon en
    ligne » is off ([Place_name.can_search] of {!State.place_sources}) it shows
    « Activez « Photon en ligne » dans Réglages pour chercher un lieu. » without
    a request (checked before the network, and again as [~allow] when the
    request leaves the geocoder's queue: a refused one shows the same line);
    offline ({!State.network}) « Hors ligne : la recherche attend le réseau. »
    without a request; a {!Herbier_geo_io.Geocoder.transient} error « Réseau
    indisponible, réessayez. », any other « Recherche impossible » (both
    logged); no result « Aucun lieu trouvé »; each result is a row (name, then
    [context] in [t-meta]) whose tap flies to its point at
    {!Move_plan.search_zoom}, closes the list and becomes [picked] for the
    title. The picked name is a preview only: « Valider » never stores it (the
    place is named by [place_label], or by reverse geocoding of the new point).
    Buttons: « Point d'origine » (bordered; hidden without origin) flies back to
    the origin at {!Move_plan.initial_zoom} and clears [picked]; « Valider »
    (moss; disabled until the map exists, while the camera moves, while
    {!Move_plan.can_validate} is false — the drawer's line then says « Zoomez
    pour placer le point précisément. » — and while saving) re-reads the
    observation, applies {!Move_plan.apply} with the centre of the last
    [moveend] (the camera the drawer shows) and saves [Observations.upsert] of
    it through {!App.save}, then [Route.back]; [None] from [apply] goes back
    without saving; a failed save, or an observation gone meanwhile, keeps the
    screen with a line.

    Entry camera: the origin at {!Move_plan.initial_zoom}; without origin, the
    4b camera of {!State.map_view} when set (else the world view) and a position
    request whose fix is flown to only while the user has not moved the camera
    since entry (a gesture, a search result, « Point d'origine » or « Ma
    position »; a resize of the map does not count; its failure is only logged).
    An observation that is not live shows {!Loaded.notice} « Cette observation
    n'est plus dans l'herbier. ». Missing theme tokens or a map that cannot be
    created show {!Map_sheet.broken_text} and keep « Valider » disabled.
    Releasing the bindings removes the map (also when its creation resolves
    afterwards). Never raises. *)

val v : App.t -> Herbier_domain.Ids.Observation_id.t -> Screen.t
