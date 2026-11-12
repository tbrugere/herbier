(** The pure part of 5b « Déplacer le point »: what the drawer says and what «
    Valider » writes. No Brr, no React, no clock; tested natively in [test/ui/].
    Never raises. *)

module Observation := Herbier_domain.Observation
module Places := Herbier_domain.Places

val initial_zoom : float
(** [17.]: the camera on entry when the observation has a position, and after «
    Point d'origine » / « Ma position ». *)

val search_zoom : float
(** [16.]: the camera after a « Chercher un lieu » result is picked. *)

val min_zoom : float
(** [12.]: below it « Valider » is disabled (a point placed from a continent
    view is meaningless). *)

val can_validate : zoom:float -> bool
(** [zoom >= min_zoom]; [false] for [nan]. *)

val normalise : Places.point -> Places.point option
(** What gets stored for a map centre: [lon] wrapped into -180 (included) to 180
    (excluded) (whatever the source of the point: [190.] → [-170.], [-190.] →
    [170.], [540.] → [-180.], [180.] → [-180.]), [lat] clamped to [[-90, 90]],
    then both rounded to 6 decimals (about 0.1 m;
    [Float.round (x *. 1e6) /. 1e6]). [None] when a coordinate is not finite.
    The result always satisfies the server's [observations_lat_range] /
    [observations_lon_range] checks. *)

val distance_text : float -> string option
(** « déplacé de … » for a distance in metres:
    - [None] when not finite, or [Float.round d < 1.] (no visible move);
    - [Float.round d < 1000.] → ["déplacé de 96 m"] (whole metres);
    - below 9 950 m → kilometres with one decimal, French comma, the decimal
      dropped when 0: [1049.] → ["déplacé de 1 km"], [1250.] →
      ["déplacé de 1,3 km"] (round half away from zero on tenths:
      [Float.round (d /. 100.)]), [999.6] → ["déplacé de 1 km"];
    - from 9 950 m → whole kilometres: [12_400.] → ["déplacé de 12 km"]. *)

val meta : origin:Places.point option -> Places.point -> string
(** The drawer's second line: the point as {!Places.point_text} (of
    {!normalise}; the raw point when [normalise] gives [None]), then [" · " ^ s]
    when [origin = Some o] and [distance_text (Places.distance_m o p) = Some s]:
    ["48.0633, 7.0081 · déplacé de 96 m"]; ["48.0633, 7.0081"] at the origin or
    without origin. *)

val title :
  origin:Places.point option ->
  origin_name:string option ->
  picked:(string * Places.point) option ->
  Places.point ->
  string
(** The drawer's title for the current centre [p]:
    - [picked = Some (name, q)] (the last « Chercher un lieu » result) and
      [Places.within q p] → [name];
    - else [origin = Some o], [origin_name = Some n] and [Places.within o p] →
      [n];
    - else ["Lieu sans nom"]. *)

val apply : Observation.t -> Places.point -> at:Ptime.t -> Observation.t option
(** What « Valider » saves, for the map centre [p]. [None] (nothing to save)
    when {!normalise} [p] is [None], or when the observation has a position
    whose own {!normalise}d point equals the normalised [p] ([Float.equal] on
    both). Otherwise [Some o'] with:
    - [position = Some {lat; lon; accuracy_m = None}], [lat]/[lon] from
      {!normalise} (the accuracy is cleared, architecture §2);
    - [place_derived = None] (computed for the old point; [App.save] runs
      [geocode_pending], which fills it again for the new one);
    - [place_label] kept when [Places.position_point] of the observation is
      [Some from] and [Places.within from] holds for the normalised [p] (still
      the same place), else [None];
    - [updated_at = at]; every other field unchanged ([id], [plant_id], [at],
      [note], [created_at], [deleted_at]). *)
