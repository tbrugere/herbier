(** A classified link or text → the GBIF taxon it names (architecture §7): the
    gbif_key and the immediate partial snapshot (names, family), as a {!Step.t}.
    Pure; never raises. *)

module Taxon := Sources.Gbif.Taxon

type unresolved =
  | No_species
      (** The sources answered: no species for this id or name (unknown key,
          match at a rank above species, no Wikidata item with a GBIF key, no
          summary, a disambiguation page). *)
  | Observation_link
      (** A Pl@ntNet observation URL: it names no species, and Pl@ntNet's API
          needs a key; the caller falls back to the search (4i). *)
  | Unavailable of string
      (** A call failed (network, timeout, status, undecodable body): try again
          later. *)

type outcome =
  | Taxon of Taxon.t  (** The accepted taxon: [key] is the gbif_key. *)
  | Candidates of Taxon.t list  (** Free text: choices for 4i (may be [[]]). *)
  | Unresolved of {query : string; why : unresolved}
      (** [query]: what 4i is prefilled with: the name of a Pl@ntNet or Pl@ntUse
          link, the title of a Wikipedia one, the text of a [Text], [""] for the
          id links and observations. *)

val equal_outcome : outcome -> outcome -> bool

val species_ranks : string list
(** [["SPECIES"; "SUBSPECIES"; "VARIETY"; "SUBVARIETY"; "FORM"; "SUBFORM";
     "INFRASPECIFIC_NAME"]]: a name match at another rank is no species. *)

val resolve : Herbier_domain.Link.t -> outcome Step.t
(** Per constructor:
    - [Gbif k] → [Gbif.species ~key:k]; any rank accepted (an explicit key).
    - [Plantnet name], [Plantuse name] → [Gbif.match_name ~name]: [Matched]
      (exact or fuzzy) with [rank = None] or in {!species_ranks} → its taxon;
      [Higher_rank], [No_match], another rank → [No_species]; a blank name (no
      request) → [No_species] without a call.
    - [Wikipedia {lang; title}] → [Wikipedia.summary ~lang ~title] →
      [wikibase_item] → [Wikidata.entity] → [gbif_key] → [Gbif.species]. No
      request (invalid title), a summary of kind [Disambiguation] (no further
      call), no item, entity [None], no P846 → [No_species].
    - [Inpn cd] / [Tela nn] / [Powo id] / [Inat id] →
      [Wikidata.search ~property:(Taxref | Tela | Powo | Inat)] → first Qid →
      entity → P846 → [Gbif.species]. Search [[]] → [No_species]; no search
      request (a POWO id with a quote or whitespace) → [No_species] without a
      call.
    - [Plantnet_observation _] →
      [Unresolved {query = ""; why = Observation_link}], no call.
    - [Text s] → {!candidates} [~q:s] → [Candidates]; its [Error why] →
      [Unresolved {query = s; why}]. Blank [s] → [Candidates []] without a call.

    Synonyms: a taxon (from [species] or a match) with [status = Some Synonym]
    and [accepted_key = Some a] with [a <> key] is replaced by
    [Gbif.species ~key:a] (one hop, never more). An [Absent] answer in a link's
    lookup → [No_species]; a [Failed] one or an undecodable body →
    [Unavailable msg]. [query] as documented on {!outcome}. *)

module Candidate : sig
  type t = {
    taxon : Taxon.t;
    french : string list;
        (** The French names GBIF's vernacular search gave for [taxon.key]: of
            that key's first result in the vernacular page, the
            [vernacularNames] rows of language ["fra"], each [name] split on
            [','], pieces trimmed, blank ones dropped, deduplicated by
            [String.lowercase_ascii] keeping the first spelling, payload order.
            [[]] when the vernacular page did not list the key, or when that
            call failed. *)
  }

  val equal : t -> t -> bool
end

val search : q:string -> (Candidate.t list, unresolved) result Step.t
(** 4i / 4k / 5c reference search: the calls, order, key dedup and failure rules
    of {!candidates}, each taxon with its French names. When only the vernacular
    call fails, suggest's taxa come back with [french = []] for every row and
    the failure is not reported. A blank [q] → [Ok []] without a call. *)

val chosen : Taxon.t -> (Taxon.t, unresolved) result Step.t
(** The taxon to store when a search row is chosen. [status = Some Synonym]
    (whatever [accepted_key]: GBIF's suggest omits [acceptedKey]) →
    [Gbif.species ~key] then the one-hop synonym rule of {!resolve}: the
    accepted taxon. [Absent] → [Error No_species]; [Failed] or an undecodable
    body → [Error (Unavailable msg)]. Any other status, or [None] → [Ok t]
    without a call. *)

val candidates : q:string -> (Taxon.t list, unresolved) result Step.t
(** [Gbif.suggest ~q] then [Gbif.vernacular_search ~q]: suggest's taxa, then the
    vernacular results' taxa whose key is not already listed (each key once),
    order kept. A call fails when it answers [Absent], [Failed] or an
    undecodable body. One call failing → the other's taxa, unless they are [[]]
    (then the failure); both failing → the first failure. A failure is always
    [Unavailable msg]. *)
