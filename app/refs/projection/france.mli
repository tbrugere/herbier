(** The taxon in metropolitan France, from INPN: its TaxRef status, whether it
    is protected and its national red-list category. *)

type protection = Not_protected | National | Local of string list
type red_list = {category : string; description : string option}

val equal_protection : protection -> protection -> bool
val pp_protection : Format.formatter -> protection -> unit
val equal_red_list : red_list -> red_list -> bool
val pp_red_list : Format.formatter -> red_list -> unit

val status : Sources.Inpn.status list -> string Cited.t option
(** The first entry's [status]; [None] for [[]]. *)

val protection : Sources.Inpn.article list -> protection Cited.t
(** Only articles of type ["PROTECTION"] count, and those whose location is
    overseas ([overseas = Some true]) do not: one of scope ["NATIONAL"] →
    [National]; else those of scope ["REGIONAL"] then ["DEPARTMENTAL"] → [Local]
    of their location names (regions first, then départements, each group in
    payload order, duplicates dropped; an article without a location adds no
    name, so [Local []] is possible); none → [Not_protected]. *)

val red_list : Sources.Inpn.red_list_entry list -> red_list Cited.t option
(** The first entry; [None] for [[]]. *)
