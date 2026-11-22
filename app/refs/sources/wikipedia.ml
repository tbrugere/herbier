module Json = Herbier_net.Json

(* [lang] becomes part of a host name: only a plain language code passes.
   A title "." or ".." would be a dot segment, which URL resolution removes,
   reaching another endpoint; MediaWiki forbids both titles. *)
let checked_title ~lang ~title =
  match (Herbier_domain.Link.valid_wikipedia_lang lang, String.trim title) with
  | false, _ | true, ("" | "." | "..") -> None
  | true, title -> Some title

let summary ~lang ~title =
  Option.map
    (fun title ->
      Request.make Herbier_domain.Reference.Source.Wikipedia
        ~base:("https://" ^ lang ^ ".wikipedia.org/api/rest_v1/page/summary")
        ~path:[String.map (function ' ' -> '_' | c -> c) title]
        ~query:[])
    (checked_title ~lang ~title)

type kind = Standard | Disambiguation | Other of string [@@deriving eq, show]

type thumbnail = {source : string; width : int; height : int}
[@@deriving eq, show]

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
[@@deriving eq, show]

let kind_of_string = function
  | "standard" -> Standard
  | "disambiguation" -> Disambiguation
  | s -> Other s

let thumbnail json =
  Option.bind (Json.member "thumbnail" json) (fun thumb ->
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
        (Option.bind (Json.member "content_urls" json) (Json.member "desktop"))
        (Decode.string "page");
    thumbnail = thumbnail json;
  }

let extract ~lang ~title =
  Option.map
    (fun title ->
      Request.make Herbier_domain.Reference.Source.Wikipedia
        ~base:("https://" ^ lang ^ ".wikipedia.org/w")
        ~path:["api.php"]
        ~query:
          [
            ("action", "query");
            ("prop", "extracts|info");
            ("inprop", "url");
            ("explaintext", "1");
            ("exsectionformat", "wiki");
            ("redirects", "1");
            ("titles", String.map (function '_' -> ' ' | c -> c) title);
            ("format", "json");
            ("formatversion", "2");
            ("origin", "*");
          ])
    (checked_title ~lang ~title)

type article = {
  title : string;
  lang : string option;
  url : string option;
  text : string;
}
[@@deriving eq, show]

let article_of_json json =
  let open Decode.Syntax in
  match Decode.api_error json with
  | Some e -> Error e
  | None -> (
      match Json.member "query" json with
      | Some (`Assoc _ as query) -> (
          match Json.member "pages" query with
          | Some (`List []) -> Ok None
          | Some (`List (page :: _)) -> (
              match
                Decode.flag "missing" page || Decode.flag "invalid" page
              with
              | true -> Ok None
              | false ->
                  let at = "/query/pages/0" in
                  let* title = Decode.required_string ~at "title" page in
                  let+ text =
                    match Json.member "extract" page with
                    | Some (`String text) -> Ok text
                    | Some _ | None ->
                        Decode.unexpected (at ^ "/extract") "string"
                  in
                  Some
                    {
                      title;
                      lang = Decode.string "pagelanguage" page;
                      url = Decode.string "fullurl" page;
                      text;
                    })
          | Some _ | None -> Decode.unexpected "/query/pages" "array")
      | Some _ | None -> Decode.unexpected "/query" "object")

let words s =
  let b = Buffer.create 16 in
  let flush acc =
    match Buffer.contents b with
    | "" -> acc
    | w ->
        Buffer.clear b;
        w :: acc
  in
  List.rev
    (flush
       (String.fold_left
          (fun acc c ->
            match c with
            | 'a' .. 'z' | '\x80' .. '\xff' ->
                Buffer.add_char b c;
                acc
            | _ -> flush acc)
          [] s))

let uses_words = function
  | "fr" ->
      ["usage"; "usages"; "utilisation"; "utilisations"; "emploi"; "emplois"]
  | _ -> ["use"; "uses"; "usage"]

let uses_title ~lang title =
  let wanted = uses_words lang in
  List.exists
    (fun w -> List.mem w wanted)
    (words (Herbier_domain.Fold.fold title))

let long_line line =
  match String.trim line with
  | l when Wiki_text.code_points l >= 40 -> Some l
  | _ -> None

type node = {section : Wiki_text.section; children : node list}

(* The flat sections as a tree: a section owns the deeper ones that follow it,
   up to the next one of its level or above. *)
let rec forest level = function
  | (section : Wiki_text.section) :: rest when section.level > level ->
      let children, rest = forest section.level rest in
      let siblings, rest = forest level rest in
      ({section; children} :: siblings, rest)
  | rest -> ([], rest)

let history_title title =
  List.exists
    (fun w -> List.mem w ["historique"; "histoire"; "history"])
    (words (Herbier_domain.Fold.fold title))

(* A uses heading often has no text of its own, only subsections: read them,
   uses ones first, then the others, a history last (past uses, not the
   plant's). *)
let rec uses_in ~lang node =
  match
    List.find_map long_line (String.split_on_char '\n' node.section.body)
  with
  | Some line -> Some (node.section.title, line)
  | None ->
      let uses, others =
        List.partition (fun n -> uses_title ~lang n.section.title) node.children
      in
      let past, others =
        List.partition (fun n -> history_title n.section.title) others
      in
      List.find_map (uses_in ~lang) (uses @ others @ past)

let rec find_uses ~lang nodes =
  List.find_map
    (fun node ->
      match uses_title ~lang node.section.title with
      | true -> uses_in ~lang node
      | false -> find_uses ~lang node.children)
    nodes

let uses_line a =
  let lang = Option.value ~default:"fr" a.lang in
  let _lead, sections = Wiki_text.sections a.text in
  find_uses ~lang (fst (forest 1 sections))

let in_uses ~lang sections =
  let step (under, acc) (s : Wiki_text.section) =
    match under with
    | Some level when s.level > level -> (under, (s, true) :: acc)
    | Some _ | None -> (
        match uses_title ~lang s.title with
        | true -> (Some s.level, (s, true) :: acc)
        | false -> (None, (s, false) :: acc))
  in
  List.rev (snd (List.fold_left step (None, []) sections))

let has_uses a = Option.is_some (uses_line a)
