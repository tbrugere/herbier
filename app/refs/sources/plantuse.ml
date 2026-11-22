module Json = Herbier_net.Json
module Source = Herbier_domain.Reference.Source

let titles name =
  match String.trim name with
  | "" -> []
  | name -> (
      match List.filter (( <> ) "") (String.split_on_char ' ' name) with
      | a :: b :: _ :: _ -> [name; a ^ " " ^ b]
      | _ -> [name])

let page ~titles =
  match List.filter (( <> ) "") (List.map String.trim titles) with
  | [] -> None
  | titles ->
      Some
        (Request.make Source.Plantuse ~base:Source_url.plantuse_wiki
           ~path:["api.php"]
           ~query:
             [
               ("action", "query");
               ("prop", "revisions");
               ("rvprop", "content");
               ("rvslots", "main");
               ("redirects", "1");
               ("titles", String.concat "|" titles);
               ("format", "json");
               ("formatversion", "2");
               ("origin", "*");
             ])

type page = {title : string; wikitext : string} [@@deriving eq, show]

type answer = {
  normalized : (string * string) list;
  redirects : (string * string) list;
  pages : page list;
}
[@@deriving eq, show]

let pairs name query =
  List.filter_map
    (fun json ->
      match (Json.string_member "from" json, Json.string_member "to" json) with
      | Some from, Some target -> Some (from, target)
      | _ -> None)
    (Decode.list name query)

let content json =
  match Decode.list "revisions" json with
  | revision :: _ ->
      Option.bind
        (Option.bind (Json.member "slots" revision) (Json.member "main"))
        (Json.string_member "content")
  | [] -> None

(* A page that exists without a readable content is an error, not a missing
   page: Missing would replace a stored page. *)
let page_of_json i json =
  match
    ( Json.string_member "title" json,
      Decode.flag "missing" json,
      Decode.flag "invalid" json )
  with
  | Some title, false, false -> (
      match content json with
      | Some wikitext -> Ok (Some {title; wikitext})
      | None ->
          Decode.unexpected
            (Printf.sprintf "/query/pages/%d/revisions/0/slots/main/content" i)
            "string")
  | _ -> Ok None

let pages_of_json pages =
  let open Decode.Syntax in
  List.fold_right
    (fun (i, json) acc ->
      let* acc = acc in
      let+ page = page_of_json i json in
      Option.to_list page @ acc)
    (List.mapi (fun i json -> (i, json)) pages)
    (Ok [])

let answer_of_json json =
  let open Decode.Syntax in
  match Decode.api_error json with
  | Some e -> Error e
  | None -> (
      match Json.member "query" json with
      | Some (`Assoc _ as query) -> (
          match Json.member "pages" query with
          | Some (`List pages) ->
              let+ pages = pages_of_json pages in
              {
                normalized = pairs "normalized" query;
                redirects = pairs "redirects" query;
                pages;
              }
          | Some _ | None -> Decode.unexpected "/query/pages" "array")
      | Some _ | None -> Decode.unexpected "/query" "object")

let resolve pairs title =
  Option.value ~default:title (List.assoc_opt title pairs)

let pick ~titles answer =
  List.find_map
    (fun title ->
      let title = String.trim title in
      let normalized =
        match List.assoc_opt title answer.normalized with
        | Some n -> n
        | None -> String.map (function '_' -> ' ' | c -> c) title
      in
      let target = resolve answer.redirects normalized in
      List.find_opt (fun (p : page) -> String.equal p.title target) answer.pages)
    titles

let find ~name answer =
  Option.bind name (fun name -> pick ~titles:(titles name) answer)

let page_url = Source_url.plantuse

type uses = {summary : string list; text : string option} [@@deriving eq, show]

let fold = Herbier_domain.Fold.fold

let dedup items =
  List.rev
    (List.fold_left
       (fun acc item ->
         match List.exists (fun seen -> fold seen = fold item) acc with
         | true -> acc
         | false -> item :: acc)
       [] items)

let summary wikitext =
  Wiki_text.templates ~name:"Encadré" wikitext
  |> List.concat_map (fun params ->
      match
        Option.map
          (fun t -> fold (Wiki_text.strip t))
          (List.assoc_opt "titre" params)
      with
      | Some "resume des usages" ->
          Option.fold ~none:[] ~some:Wiki_text.bullets
            (List.assoc_opt "texte" params)
      | Some _ | None -> [])
  |> dedup

(* Non-overlapping occurrences. *)
let count sub line =
  let rec go i acc =
    match Wiki_text.find line sub i with
    | Some j -> go (j + String.length sub) (acc + 1)
    | None -> acc
  in
  go 0 0

let braces line = count "{{" line - count "}}" line

(* A table row line without its leading '|': cells split on "||", each one
   without its attributes ("style=… | text" → "text"), joined with spaces. *)
let cells line =
  let cell = function
    | attributes :: (_ :: _ as text) when String.contains attributes '=' ->
        String.concat "|" text
    | pieces -> String.concat "|" pieces
  in
  let close current acc =
    match current with [] -> acc | _ :: _ -> cell (List.rev current) :: acc
  in
  let current, acc =
    List.fold_left
      (fun (current, acc) -> function
        | "" -> ([], close current acc) | piece -> (piece :: current, acc))
      ([], []) (Wiki_text.pieces line)
  in
  String.concat " " (List.map String.trim (List.rev (close current acc)))

type state = Text | In_template of int | In_gallery

let starts prefixes line =
  List.exists (fun prefix -> String.starts_with ~prefix line) prefixes

(* Each line is [Some text] to keep, [None] for a dropped or blank line,
   which separates paragraphs. *)
let prose_lines body =
  let step (state, acc) line =
    let t = String.trim line in
    match state with
    | In_template depth -> (
        match depth + braces t with
        | d when d > 0 -> (In_template d, None :: acc)
        | _ -> (Text, None :: acc))
    | In_gallery -> (
        match count "</gallery>" t with
        | 0 -> (In_gallery, None :: acc)
        | _ -> (Text, None :: acc))
    | Text -> (
        match () with
        | () when String.starts_with ~prefix:"{{" t -> (
            match braces t with
            | d when d > 0 -> (In_template d, None :: acc)
            | _ -> (Text, None :: acc))
        | () when String.starts_with ~prefix:"<gallery" t -> (
            match count "</gallery>" t with
            | 0 -> (In_gallery, None :: acc)
            | _ -> (Text, None :: acc))
        | () when starts ["*"; "#"; "{|"; "|}"; "|-"; "!"] t ->
            (Text, None :: acc)
        | () when String.starts_with ~prefix:"|" t ->
            (Text, Some (cells (String.sub t 1 (String.length t - 1))) :: acc)
        | () when t = "" -> (Text, None :: acc)
        | () -> (Text, Some t :: acc))
  in
  List.rev
    (snd (List.fold_left step (Text, []) (String.split_on_char '\n' body)))

let paragraphs lines =
  let close current acc =
    match current with
    | [] -> acc
    | _ :: _ -> String.concat " " (List.rev current) :: acc
  in
  let current, acc =
    List.fold_left
      (fun (current, acc) -> function
        | Some l -> (l :: current, acc) | None -> ([], close current acc))
      ([], []) lines
  in
  List.rev (close current acc)

let text wikitext =
  let _lead, sections = Wiki_text.sections wikitext in
  sections
  |> List.filter (fun (s : Wiki_text.section) ->
      s.level = 2 && fold s.title = "usages")
  |> List.concat_map (fun (s : Wiki_text.section) ->
      paragraphs (prose_lines s.body))
  |> List.find_map (fun p ->
      match Wiki_text.strip p with
      | "" -> None
      | p -> Some (Wiki_text.first_sentences ~n:2 p))

let uses (p : page) = {summary = summary p.wikitext; text = text p.wikitext}
