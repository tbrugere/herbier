(** Where a taxon is native or introduced, and its IUCN status, from GBIF's
    distributions (WCVP and the IUCN Red List). *)

type area = {code : string option; name : string}
(** One WCVP area: [code] = the distribution's [location_id] after ["TDWG:"]
    when it starts with that prefix and has at least one character after it,
    else [None]; [name] = its [locality] as GBIF gives it (English). *)

val equal_area : area -> area -> bool

type t = {native : area list; introduced : area list}

val origin : Sources.Gbif.Distribution.t Sources.Gbif.page -> t Cited.t option

val red_list :
  Sources.Gbif.Distribution.t Sources.Gbif.page -> string Cited.t option
