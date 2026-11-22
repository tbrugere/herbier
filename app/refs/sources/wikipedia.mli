(** Wikipedia REST page summary (architecture §6: fr, fallback en, the fallback
    being the pipeline's choice). Requests are [Source.Wikipedia]; [http.ml]
    adds [Api-User-Agent]. The browser follows the redirect of a redirect title
    ([Arnica_montana] to ["Arnica des montagnes"]). *)

val summary : lang:string -> title:string -> Request.t option
(** ["https://<lang>.wikipedia.org/api/rest_v1/page/summary/<t>"] where [<t>] is
    the trimmed [title] with spaces turned into ['_'], then
    {!Herbier_net.Url.encode}d as one segment (["AC/DC"] gives ["AC%2FDC"]).
    [None] when [lang] fails {!Herbier_domain.Link.valid_wikipedia_lang} (the
    rule [Link.Wikipedia] is classified with: not ["FR"], ["fr.m"], [""],
    ["www"]), or when the trimmed title is blank, ["."] or [".."]. *)

type kind =
  | Standard
  | Disambiguation
  | Other of string
      (** [type]: ["standard"], ["disambiguation"], anything else as given
          (["no-extract"], ["mainpage"]). *)

type thumbnail = {source : string; width : int; height : int}
(** [source] is the URL as sent, unchecked (scheme and host): a caller checks it
    before using it as [src] or downloading it. *)

type t = {
  kind : kind;
  title : string;  (** The resolved title, spaces not underscores. *)
  lang : string option;
  description : string option;  (** Wikidata short description. *)
  extract : string option;  (** Plain-text intro. *)
  wikibase_item : Qid.t option;
  page_url : string option;
      (** [content_urls.desktop.page], unchecked (scheme and host): a caller
          checks it before using it as [href]. *)
  thumbnail : thumbnail option;  (** All three fields, or [None]. *)
}

val equal : t -> t -> bool
val pp : Format.formatter -> t -> unit

val summary_of_json : Yojson.Safe.t -> (t, Decode.error) result
(** Required [type] and [title]. A 404 never reaches here: [http.ml] returns
    [Status] for it. *)

(** {1 The uses section}

    The whole article as plain text, through the action API's TextExtracts
    ([prop=extracts], [explaintext], [exsectionformat=wiki]: [== Title ==]
    heading lines, templates rendered, references dropped, one paragraph per
    line), for the « Utilisations » row of 4f. *)

val extract : lang:string -> title:string -> Request.t option
(** ["https://<lang>.wikipedia.org/w/api.php"] with, in this order:
    [action=query], [prop=extracts|info], [inprop=url], [explaintext=1],
    [exsectionformat=wiki], [redirects=1],
    [titles=<the trimmed title, '_' turned into ' '>], [format=json],
    [formatversion=2], [origin=*]. [None] under the conditions of {!summary}
    (invalid [lang], blank, ["."] or [".."] title). *)

type article = {
  title : string;  (** The resolved title, as given. *)
  lang : string option;  (** [pagelanguage]. *)
  url : string option;
      (** [fullurl], unchecked (scheme and host): a caller checks it before
          using it as [href]. *)
  text : string;  (** [extract]. *)
}

val equal_article : article -> article -> bool
val pp_article : Format.formatter -> article -> unit

val article_of_json : Yojson.Safe.t -> (article option, Decode.error) result
(** A root [error] object → [Api_error]; a required [query] object
    ([Unexpected "/query" "object"]) holding a required [pages] array
    ([Unexpected "/query/pages" "array"]). Its first element: [missing] or
    [invalid] true → [Ok None] (no such article); else required string [title]
    and [extract] ([Unexpected "/query/pages/0/title"] / [".../extract"]). An
    empty [pages] array → [Ok None]. *)

val uses_title : lang:string -> string -> bool
(** Whether a section title names uses: the title {!Herbier_domain.Fold.fold}ed
    and split into words on the bytes that are not letters. ["fr"]: a word is
    ["usage"], ["usages"], ["utilisation"], ["utilisations"], ["emploi"] or
    ["emplois"] (« Usages et propriétés », « Autres usages », « Utilisation »;
    not « Propriétés médicinales »). Any other [lang]: a word is ["use"],
    ["uses"] or ["usage"] (« Uses », « Medicinal use », « Use in herbal medicine
    »; not « Relationship to humans », « Cultivation », « Users »). *)

val uses_line : article -> (string * string) option
(** [(section title as written, line)]. The sections of [text]
    ({!Wiki_text.sections}) read as a tree (a section owns the deeper ones that
    follow it); in document order, the first section whose title passes
    {!uses_title} ([lang] = the article's, else ["fr"]) and holds a line of at
    least 40 code points once trimmed, read as: its own body first, else its
    subsections recursively, those passing {!uses_title} first, then the others,
    those titled « Historique », « Histoire » or « History » last. The title
    returned is the section the line is in (« Phytothérapie » under « Usages en
    médecine humaine »). The 40 code points skip captions, list stubs and
    one-word lines. A heuristic: the section is picked by its title. *)

val in_uses :
  lang:string -> Wiki_text.section list -> (Wiki_text.section * bool) list
(** Each section with whether {!uses_line} may read its body: its title passes
    {!uses_title}, or it lies under one that does. *)

val has_uses : article -> bool
(** [uses_line a <> None]: the fetch's "fr has it, no en call" test, the same
    rule the projection reads. *)
