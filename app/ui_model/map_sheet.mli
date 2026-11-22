(** 4b's sheet, shown only for a selected place, and the map's status pill:
    texts, snap points, photo lookup. Pure (no store, no Brr), tested natively
    in [test/ui/]. *)

module Observation := Herbier_domain.Observation
module Photo := Herbier_domain.Photo
module Observation_id := Herbier_domain.Ids.Observation_id

val snaps : available:float -> top:float -> float list
(** Visible heights for {!Widgets.Sheet}: [[0.; mid; high]], where [0.] is the
    closed sheet (no place selected), [mid] the one a selection opens,
    [mid = Float.min 360. (available *. 0.5)] and
    [high = Float.max (mid +. 1.) (available -. top -. 36.)], then made strictly
    ascending: [mid] is raised to [1.] when below it. [available] is the
    screen's height above the tab bar and [top] the height the floating search
    and chips take from its top (safe-area inset included), both in px, so the
    fully raised sheet stops 36 px below the chips. Always three strictly
    ascending values, also for negative values or [nan] (treated as [0.]). *)

val title : Herbier_domain.Places.cluster -> string
(** {!Journal_day.place} of the members (« Lieu inconnu » for an unnamed place),
    or ["Lieu"] when [None]. *)

val detail : Herbier_domain.Places.cluster -> string option
(** The line under {!title}: {!Journal_day.place_detail} of the members. *)

val summary : Observation.t list -> string
(** The shown members: ["rayon 500 m · 6 observations · 4 plantes"] (distinct
    [plant_id]s), French plural rules of {!Fr_text.plural}; the plants part is
    left out when no member has a plant: ["rayon 500 m · 1 observation"]. *)

(** A message the map's status pill shows, under the search and the chips. *)
type notice =
  | Loading  (** before the first data *)
  | Read_failed
  | Search_failed  (** the plant search failed: places match by name only *)
  | Position_unavailable
  | Location_denied
  | Location_off

val notice_text : notice -> string
(** ["Chargement…"], ["Lecture impossible"], ["Recherche impossible"],
    ["Position indisponible"], ["Localisation non autorisée"],
    ["Localisation désactivée"]. *)

val position_failure : string option -> notice
(** The notice for a rejected [@capacitor/geolocation] call, from its error
    [code]: ["OS-PLUG-GLOC-0003"] (permission refused) is [Location_denied],
    ["OS-PLUG-GLOC-0007"] and ["OS-PLUG-GLOC-0017"] (location off) are
    [Location_off], anything else [Position_unavailable]. *)

(** Why there is no map, shown for good. *)
type broken = Missing_tokens of string list | Map_unavailable

val broken_text : broken -> string
(** ["Jetons absents : --map-point, --paper"], ["Carte indisponible"]. *)

val rename_value : Herbier_domain.Places.cluster -> string
(** The field's initial text: [s] when [Places.label] is [Named s], else [""].
*)

val photos_by_observation : Photo.t list -> Observation_id.t -> Photo.t list
(** Index built once (one pass): an observation's photos ordered by [taken_at]
    ascending, then id ascending; [[]] for none. *)

val row_meta : this_year:int -> date:Ptime.date -> photos:int -> string
(** ["12 juin · 2 photos"], ["12 juin · 1 photo"], ["12 juin"] when
    [photos = 0]; the date is {!Fr_date.day_month} when its year is [this_year],
    {!Fr_date.full_date} otherwise (["3 décembre 2025 · 1 photo"]). *)
