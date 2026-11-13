(** Where a taxon is native or introduced, and its IUCN status, from GBIF's
    distributions (WCVP and the IUCN Red List). *)

type t = {native : string list; introduced : string list}

val origin : Sources.Gbif.Distribution.t Sources.Gbif.page -> t Cited.t option

val red_list :
  Sources.Gbif.Distribution.t Sources.Gbif.page -> string Cited.t option
