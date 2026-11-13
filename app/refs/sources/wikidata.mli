(** Wikidata action API (architecture §6, §7): the cross-id hub. Every request
    is [Source.Wikidata], base ["https://www.wikidata.org/w/api.php"], with
    [format=json] and [origin=*] (anonymous CORS) as its last two parameters;
    [http.ml] adds the [Api-User-Agent] header. *)

module Property : sig
  type t = Gbif_key | Powo | Inat | Taxref | Tela

  val to_string : t -> string
  (** ["P846"], ["P5037"], ["P3151"], ["P3186"] (TaxRef cd_nom), ["P3105"]
      (BDTFX nn). *)
end

val search : property:Property.t -> value:string -> Request.t option
(** [?action=query&list=search&srsearch=haswbstatement:"<P>=<value>"&format=json&origin=*]
    (the quotes keep a POWO URN's colons inside the statement). [None] when
    [value] is empty or contains a ['"'] or ASCII whitespace (the set
    [String.trim] strips). *)

val entity : Qid.t -> Request.t
(** [?action=wbgetentities&ids=<qid>&props=claims|sitelinks&sitefilter=frwiki|enwiki|dewiki|itwiki&format=json&origin=*]
*)

val search_of_json : Yojson.Safe.t -> (Qid.t list, Decode.error) result
(** [query.search[].title] that are Qids, in order (others dropped); [[]] for no
    hit. A root [error] is read as in {!entity_of_json}; otherwise a missing
    [/query/search] array is [Unexpected]. *)

module Entity : sig
  type name = {lang : string; text : string}

  type sitelink = {lang : string; title : string}
  (** [lang] is the wiki prefix: ["fr"] for [frwiki]. *)

  type t = {
    qid : Qid.t;
    gbif_key : int option;  (** P846. *)
    powo : string option;  (** P5037, ["urn:lsid:ipni.org:names:802077-1"]. *)
    ipni : string option;  (** P961. *)
    taxref : int option;  (** P3186 (TaxRef cd_nom). *)
    tela : int option;  (** P3105 (BDTFX nn). *)
    eppo : string option;  (** P3031. *)
    inat : int option;  (** P3151. *)
    common_names : name list;  (** P1843, every value, in order. *)
    sitelinks : sitelink list;  (** fr, en, de, it present, in that order. *)
  }

  val equal : t -> t -> bool
  val pp : Format.formatter -> t -> unit
end

val entity_of_json : Yojson.Safe.t -> (Entity.t option, Decode.error) result
(** The single entity under [entities] (keyed by the requested id; with a
    redirect, [id] is the target). [Ok None] when it carries ["missing"]. A root
    [error] object with a string [code] is [Api_error] (["no-such-entity"] for
    [Q0]); any other root [error] is [Unexpected] at ["/error"]. No [entities]
    object, an empty one, or an entity whose [id] is not a Qid, is [Unexpected].
    The [qid] is the entity's own [id].

    Claims: only a [mainsnak] with [snaktype = "value"]; statements whose [rank]
    is not ["preferred"] or ["normal"] (["deprecated"], missing) are ignored;
    for a single-valued field the first ["preferred"] statement wins, else the
    first ["normal"] one. The numeric ids (P846, P3186, P3105, P3151) are
    external-id strings in the payload: a value that is not all digits or does
    not fit an [int] makes that field [None] (an [int] is 32-bit under
    js_of_ocaml). *)
