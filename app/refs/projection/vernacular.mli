(** The vernacular names of a taxon: GBIF's and Wikidata's names as votes,
    grouped per language. *)

module Lang : sig
  type t = Fr | En | De | It

  val all : t list
  val to_string : t -> string
end

type t = {lang : Lang.t; names : string list}
type vote

val gbif_votes : Sources.Gbif.Vernacular.t Sources.Gbif.page -> vote list
val wikidata_votes : Sources.Wikidata.Entity.t -> vote list

val vernacular : vote list -> t list Cited.t option
(** Per language of {!Lang.all}, the 3 most voted spellings (case-insensitive
    groups, ties by first vote); [None] when no language has a name. *)
