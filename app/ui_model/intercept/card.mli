(** 4j's card: its texts, the recent tags and the first observation. Documented
    as [Intercept]'s values of the same names. *)

module Plant := Herbier_domain.Plant
module Tag := Herbier_domain.Tag

val name : Herbier_refs.Resolve.Candidate.t -> existing:Plant.t option -> string
val meta : Herbier_refs.Sources.Gbif.Taxon.t -> string
val place_line : Gps.t -> string
val recent_count : int
val session_s : float

val recent_tags :
  now:Ptime.t ->
  tags:Tag.t list ->
  links:Tag.Plant_tag.t list ->
  except:Herbier_domain.Ids.Tag_id.t list ->
  (Tag.t * bool) list

val observation :
  id:Herbier_domain.Ids.Observation_id.t ->
  at:Ptime.t ->
  plant:Herbier_domain.Ids.Plant_id.t ->
  Gps.t ->
  Herbier_domain.Observation.t
