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
