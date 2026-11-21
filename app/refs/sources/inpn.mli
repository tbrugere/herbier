(** INPN open data ([odata-inpn.mnhn.fr], undocumented HAL+JSON; the official
    TaxRef API redirects to the web UI): TaxRef status in metropolitan France,
    protection articles, the national red list. Requests are [Source.Taxref],
    base ["https://odata-inpn.mnhn.fr"]; no custom header. Statuses hang on the
    valid TaxRef id: {!name} turns any cd_nom into it first.

    Decoders follow the field rules of {!Decode}. A page without results has no
    [_embedded] member: it decodes to [[]]. A page whose [page.totalElements] is
    above 0 but which yields no element (its [_embedded] array renamed, or every
    element unreadable) is an error: INPN's API is undocumented, and a changed
    shape must not read as "no data". *)

val base : string
(** ["https://odata-inpn.mnhn.fr"] *)

val metropolitan_france : string
(** ["TERFXFR"] *)

(** {1 Requests} *)

val name : cd_nom:int -> Request.t
(** [taxa/names/<cd_nom>]. 404 for an unknown id. *)

val status : cd_ref:int -> Request.t
(** [taxa/<cd_ref>/biogeographicStatuses?locationId=TERFXFR]. *)

val red_list : cd_ref:int -> Request.t
(** [taxa/redLists/entries?taxrefId=<cd_ref>&scopes=NATIONAL&scopeLocationId=TERFXFR].
*)

val protections : cd_ref:int -> Request.t
(** [taxa/protections/articles?taxrefIds=<cd_ref>&embed=SCOPE_LOCATION&size=100]:
    one page of 100 articles, the rest dropped (the most regulated plants seen,
    such as Narcissus pseudonarcissus, have 36). *)

(** {1 Payloads} *)

type name = {taxref_id : int; valid : bool option; cd_ref : int}

val equal_name : name -> name -> bool
val pp_name : Format.formatter -> name -> unit

val name_of_json : Yojson.Safe.t -> (name, Decode.error) result
(** Required int [taxrefId]. [cd_ref] = the digits after the last ["/taxa/"] of
    [_links.taxon.href] (up to the first non-digit); when that href is missing
    or has no digits there, [taxrefId], unless [valid] is [false] (a synonym's
    valid taxon is unknown): then [Unexpected "/_links/taxon/href"]. *)

type status = {status : string; simplified : string option}
(** [biogeographicStatus] (["PRESENT"], ["INVASIVE"], …),
    [simplifiedBiogeographicStatus]. *)

val equal_status : status -> status -> bool
val pp_status : Format.formatter -> status -> unit

val status_of_json : Yojson.Safe.t -> (status list, Decode.error) result
(** [_embedded.biogeographicStatuses], payload order; no [_embedded] (an empty
    page) → [Ok []]; an element without a string [biogeographicStatus] is
    dropped. Root not an object → [Unexpected "" "object"]; [_embedded] without
    the array → [Unexpected "/_embedded/biogeographicStatuses" "array"], as is
    an empty result when [page.totalElements] is above 0. *)

type red_list_entry = {
  category : string;  (** ["LC"] … *)
  description : string option;  (** [categoryDescription] *)
  trend : string option;
}

val equal_red_list_entry : red_list_entry -> red_list_entry -> bool
val pp_red_list_entry : Format.formatter -> red_list_entry -> unit

val red_list_of_json :
  Yojson.Safe.t -> (red_list_entry list, Decode.error) result
(** [_embedded.redListEntries]; the same empty, dropped (no string [category]),
    shape and root rules. *)

type location = {
  id : string option;  (** [locationId] *)
  name : string;
  level : string option;  (** ["REGION"], ["DEPARTMENT"], … *)
  overseas : bool option;
}

type article = {
  scope : string;  (** ["NATIONAL"], ["REGIONAL"], ["DEPARTMENTAL"], … *)
  kind : string;  (** [type]: ["PROTECTION"], ["REGULATION"], … *)
  category : string option;
  location : location option;
      (** [_embedded.scopeLocation]; [None] without a string [name]. *)
}

val equal_location : location -> location -> bool
val pp_location : Format.formatter -> location -> unit
val equal_article : article -> article -> bool
val pp_article : Format.formatter -> article -> unit

val protections_of_json : Yojson.Safe.t -> (article list, Decode.error) result
(** [_embedded.protectionArticles]; the same empty, shape and root rules; an
    element without string [scope] and [type] is dropped. *)
