(** GBIF API v1 (architecture §6, §7): the backbone taxonomy and the Pl@ntNet
    occurrence images. Every request is [Source.Gbif], base
    ["https://api.gbif.org/v1"], and sends no custom header ([http.ml]).

    Decoders follow the field rules of {!Decode}; in a list, an element that
    fails its own required fields is dropped, the list itself never fails
    because of one element. *)

val backbone_dataset : string
(** ["d7dddbf4-2cf0-4f39-9b2a-bb099caae36c"] *)

val plantnet_dataset : string
(** ["7a3679ef-5582-4aaa-81f0-8c2545cafc81"] *)

val species_url : int -> string
(** ["https://www.gbif.org/species/<key>"]: the species' page on the GBIF
    website, a URL [Link.classify] reads as [Gbif key]. *)

(** {1 Requests} *)

val species : key:int -> Request.t
(** [/species/<key>] *)

val match_name : name:string -> Request.t option
(** [/species/match?name=<name>&kingdom=Plantae]; [name] as given, author
    included (["Digitalis purpurea L."]). [None] when [name] is blank (GBIF
    answers a blank name with an [EXACT] match on [Plantae]).

    With [kingdom=Plantae] an unknown name comes back as [Higher_rank] on
    [Plantae] (key 6), never [No_match]: a caller reads [Higher_rank], and a
    [Matched] whose [rank] is above species, as "no species match". *)

val suggest : q:string -> Request.t
(** [/species/suggest?q=<q>&datasetKey=<backbone>&rank=SPECIES&highertaxonKey=6&limit=10]
*)

val vernacular_search : q:string -> Request.t
(** [/species/search?q=<q>&datasetKey=<backbone>&highertaxonKey=6&qField=VERNACULAR&limit=20]
*)

val vernacular_names : key:int -> Request.t
(** [/species/<key>/vernacularNames?limit=1000] *)

val distributions : key:int -> Request.t
(** [/species/<key>/distributions?limit=1000] *)

val occurrence_count : key:int -> Request.t
(** [/occurrence/count?taxonKey=<key>] *)

val plantnet_media : key:int -> Request.t
(** [/occurrence/search?datasetKey=<plantnet>&taxonKey=<key>&mediaType=StillImage&limit=50]
*)

(** {1 Payloads} *)

module Status : sig
  type t =
    | Accepted
    | Doubtful
    | Synonym
    | Other of string
        (** GBIF's taxonomic status: ["ACCEPTED"], ["DOUBTFUL"]; ["SYNONYM"] and
            every ["*_SYNONYM"] (HETEROTYPIC, HOMOTYPIC, PROPARTE) are
            [Synonym]; any other non-blank string is [Other] as given. *)
end

module Taxon : sig
  type t = {
    key : int;
    scientific_name : string;  (** With authorship. *)
    canonical_name : string option;  (** Without authorship. *)
    authorship : string option;
    rank : string option;  (** As given: ["SPECIES"], ["GENUS"]… *)
    status : Status.t option;
    accepted_key : int option;  (** Set on synonyms. *)
    family : string option;
    vernacular_name : string option;
        (** GBIF's one display name, often English. *)
  }
end

type 'a page = {
  results : 'a list;
  dropped : Decode.error list;
      (** The errors of the [results] elements that were dropped, in order: one
          per element that failed its own required fields, so a page where every
          element failed tells why. *)
  end_of_records : bool;
  count : int option;
}
(** GBIF's paging envelope: [results] (required array), [endOfRecords] (missing
    means [false]), [count] (optional). *)

val species_of_json : Yojson.Safe.t -> (Taxon.t, Decode.error) result
(** [/species/<key>]: required [key] (int) and [scientificName]; [status] from
    [taxonomicStatus]; [accepted_key] from [acceptedKey]; [authorship] blank
    (GBIF sends [""]) is [None]. *)

type match_ =
  | No_match
      (** [matchType] ["NONE"]: only without a kingdom filter, so never for a
          {!match_name} request. *)
  | Higher_rank of Taxon.t
      (** ["HIGHERRANK"]: only a genus, family or kingdom matched (nonsense
          input matches [Plantae], key 6). *)
  | Matched of {taxon : Taxon.t; fuzzy : bool; confidence : int option}
      (** ["EXACT"] ([fuzzy = false]) or ["FUZZY"] ([true]). *)

val match_of_json : Yojson.Safe.t -> (match_, Decode.error) result
(** [/species/match]: required [matchType] among [EXACT|FUZZY|HIGHERRANK|NONE]
    (anything else is [Unexpected] at ["/matchType"]); for all but NONE,
    required [usageKey] and [scientificName]; [status] from [status];
    [accepted_key] from [acceptedUsageKey]. *)

val suggest_of_json : Yojson.Safe.t -> (Taxon.t list, Decode.error) result
(** [/species/suggest]: root array (else [Unexpected] at [""]); per element
    [key], [scientificName], [status], [family]…; order kept. GBIF sends no
    [authorship] there: it is the rest of [scientificName] after the words of
    [canonicalName] (a hybrid sign or a rank marker such as [subsp.] between
    them skipped), [None] when they do not match. *)

module Vernacular : sig
  type t = {
    name : string;  (** As given: may be a comma-joined list (TAXREF). *)
    language : string option;  (** ISO 639-3 as given: ["fra"], ["deu"]. *)
    source : string option;
    country : string option;
  }
end

val vernacular_search_of_json :
  Yojson.Safe.t -> ((Taxon.t * Vernacular.t list) page, Decode.error) result
(** [/species/search?qField=VERNACULAR]: each result is a taxon (fields as in
    {!species_of_json}, status from [taxonomicStatus]) with its embedded
    [vernacularNames] array ([[]] when missing). *)

val vernacular_names_of_json :
  Yojson.Safe.t -> (Vernacular.t page, Decode.error) result
(** [/species/<key>/vernacularNames]: rows without a non-blank [vernacularName]
    are dropped. No splitting, no dedup (the projection's job). *)

module Distribution : sig
  type t = {
    location_id : string option;  (** ["TDWG:AGE"], or a country name. *)
    locality : string option;
    country : string option;
    status : string option;  (** ["PRESENT"]… *)
    establishment_means : string option;
        (** ["INTRODUCED"]…; WCVP natives have none. *)
    threat_status : string option;
    source : string option;
        (** ["The World Checklist of Vascular Plants (WCVP)"]… *)
  }
end

val distributions_of_json :
  Yojson.Safe.t -> (Distribution.t page, Decode.error) result
(** Rows with none of [locationId], [locality] and [country] are dropped. A row
    with only a [country] (GRIIS introductions, national red lists with their
    [threatStatus]) is kept. *)

val occurrence_count_of_json : Yojson.Safe.t -> (int, Decode.error) result
(** [/occurrence/count]: the body is a bare JSON integer [>= 0]; anything else
    is [Unexpected] at [""]. *)

module Image : sig
  type t = {
    occurrence_key : string;
        (** Decimal digits as sent: occurrence keys exceed 2^31 (5110295086),
            which a js_of_ocaml [int] cannot hold. *)
    url : string;
        (** Media [identifier], https on any host: not checked against a host
            list, so a caller checks it before using it as [src] or downloading
            it. *)
    organ : Herbier_domain.Reference.Organ.t option;
        (** [Organ.of_string] of [organ_label]. *)
    organ_label : string option;
        (** The lower-cased word after the last [": "] of the media [title]
            (["leaf"], ["bark"], ["other"]). *)
    licence : string;  (** ["cc-by-sa"]. *)
    attribution : string;  (** ["Iris Selcho"]. *)
    observation_url : string option;
        (** Media [source], else the occurrence [references], unchecked (scheme
            and host): a caller checks it before using it as [href]. *)
  }
end

val plantnet_media_of_json :
  Yojson.Safe.t -> (Image.t page, Decode.error) result
(** [/occurrence/search] on the Pl@ntNet dataset: one [Image.t] per element of
    each occurrence's [media] array, in order. An occurrence without a [key]
    ([`Int] or [`Intlit] of digits) is dropped, with an [Unexpected] at
    ["/results/<i>/key"] in [dropped]. A media row is kept only if [type] is
    ["StillImage"], [identifier] starts with ["https://"], a licence is found
    and an attribution is found:
    - [licence]: the text inside the trailing parentheses of the media [license]
      (["Iris Selcho (cc-by-sa)"] gives ["cc-by-sa"]), lower-cased, when it
      starts with ["cc"]; no such suffix drops the row;
    - [attribution]: [rightsHolder], else [creator], else the part of [license]
      before the last ["("], trimmed (none in ["(cc-by)"]); all blank drops the
      row.

    The page's [count] is the dataset's total for the taxon, not the number of
    images. *)
