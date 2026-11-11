(* [lang] becomes part of a host name: only a plain language code passes.
   A title "." or ".." would be a dot segment, which URL resolution removes,
   reaching another endpoint; MediaWiki forbids both titles. *)
let summary ~lang ~title =
  match (Herbier_domain.Link.valid_wikipedia_lang lang, String.trim title) with
  | false, _ | true, ("" | "." | "..") -> None
  | true, title ->
      Some
        (Request.make Herbier_domain.Reference.Source.Wikipedia
           ~base:("https://" ^ lang ^ ".wikipedia.org/api/rest_v1/page/summary")
           ~path:[String.map (function ' ' -> '_' | c -> c) title]
           ~query:[])

type kind = Standard | Disambiguation | Other of string
type thumbnail = {source : string; width : int; height : int}

type t = {
  kind : kind;
  title : string;
  lang : string option;
  description : string option;
  extract : string option;
  wikibase_item : Qid.t option;
  page_url : string option;
  thumbnail : thumbnail option;
}

let kind_of_string = function
  | "standard" -> Standard
  | "disambiguation" -> Disambiguation
  | s -> Other s

let thumbnail json =
  Option.bind (Decode.member "thumbnail" json) (fun thumb ->
      match
        ( Decode.string "source" thumb,
          Decode.int "width" thumb,
          Decode.int "height" thumb )
      with
      | Some source, Some width, Some height -> Some {source; width; height}
      | _ -> None)

let summary_of_json json =
  let open Decode.Syntax in
  let* kind = Decode.required_string "type" json in
  let+ title = Decode.required_string "title" json in
  {
    kind = kind_of_string kind;
    title;
    lang = Decode.string "lang" json;
    description = Decode.string "description" json;
    extract = Decode.string "extract" json;
    wikibase_item =
      Option.bind (Decode.string "wikibase_item" json) Qid.of_string;
    page_url =
      Option.bind
        (Option.bind
           (Decode.member "content_urls" json)
           (Decode.member "desktop"))
        (Decode.string "page");
    thumbnail = thumbnail json;
  }
