(** A proposal chosen in the identification layer (6e) and how it becomes a GBIF
    taxon (architecture §12 « The choice and the GBIF id »). Pure; nothing here
    raises or logs. *)

module Plantnet := Herbier_identify.Plantnet
module Taxon := Herbier_refs.Sources.Gbif.Taxon

type resolution =
  | Resolved of Taxon.t
      (** GBIF's taxon, after {!Herbier_refs.Resolve.resolve}'s one-hop synonym
          rule *)
  | Unknown
      (** GBIF answered and has no species for it: the id unknown (404) and the
          name match not at species rank, or no id and no species match *)
  | Unavailable of string
      (** a GBIF call failed (network, timeout, status, undecodable body): its
          message, for the console only *)

val equal_resolution : resolution -> resolution -> bool

type t = {
  proposal : Plantnet.proposal;
  resolution : resolution option;  (** [None]: GBIF has not answered yet *)
}

val equal : t -> t -> bool

val v : Plantnet.proposal -> t
(** [{proposal; resolution = None}]. *)

val resolved : t -> resolution -> t
(** [{t with resolution = Some r}]. *)

val first_link : Plantnet.proposal -> Herbier_domain.Link.t
(** [gbif = Some k] → [Gbif k]; [None] → [Plantnet p.scientific_name] (the Latin
    name with its author, as a Pl@ntNet species link carries it; GBIF's name
    match). *)

val resolve : Plantnet.proposal -> resolution Herbier_refs.Step.t
(** {!Herbier_refs.Resolve.resolve} of {!first_link}, then:
    - [Taxon t] → [Resolved t];
    - [Unresolved {why = No_species; _}] on [Gbif k] → a second program,
      [Resolve.resolve (Plantnet p.scientific_name)] (an id unknown to GBIF
      falls back on the name match), whose [Taxon t] → [Resolved t],
      [No_species] (or [Observation_link], or [Candidates _]) → [Unknown],
      [Unavailable m] → [Unavailable m];
    - [Unresolved {why = No_species; _}] on [Plantnet _] → [Unknown] (no second
      call);
    - [Unresolved {why = Unavailable m; _}] (either link) → [Unavailable m], no
      name match after a failed id lookup (the network is down: a second call
      would fail too);
    - [Candidates _], [Unresolved {why = Observation_link; _}] (not produced for
      these links) → [Unknown].

    At most two GBIF programs; never raises. *)

val plantnet_taxon : Plantnet.proposal -> Taxon.t option
(** The taxon from Pl@ntNet's own answer, for a save made before GBIF answers:
    [gbif = None] → [None]; [Some k] →
    [{key = k; scientific_name = p.scientific_name; canonical_name = Some
     p.name; authorship = (if p.author = "" then None else Some p.author); rank
     = None; status = None; accepted_key = None; family = p.family;
     vernacular_name = None}]. *)

val taxon : t -> Taxon.t option
(** The taxon a save links: [Some (Resolved t)] → [Some t]; [Some Unknown] →
    [None] (GBIF knows no such species: the plant is a free name); [None]
    (pending) or [Some (Unavailable _)] → {!plantnet_taxon} [t.proposal]. *)

val keys : t -> int list
(** The GBIF keys that mean "this species", in this order, each once: the
    proposal's [gbif], then, when [Resolved r], [r.key] and [r.accepted_key].
    [[]] when none. *)

val owner :
  plants:Herbier_domain.Plant.t list -> t -> Herbier_domain.Plant.t option
(** The first of [plants] (given order) with {!Owned.has_key} [~keys:(keys t)]
    (live, [gbif_key] in {!keys}); [None] when none matches. Unlike 6c's
    {!Owned.find} (the proposal's id alone), a resolved choice also matches on
    GBIF's key and accepted key. *)

val new_name : Plantnet.proposal -> string
(** A new plant's display name: the first of [common_names], else [name] (the
    Latin name without author). *)

val label : owner:Herbier_domain.Plant.t option -> Plantnet.proposal -> string
(** 6e's name: [Some p] → [p.display_name]; [None] → {!new_name}. *)
