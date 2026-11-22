module Link = Herbier_domain.Link
module Wikipedia = Sources.Wikipedia
module Plantuse = Sources.Plantuse

type wikipedia = {
  paragraph : string;
  section : string;
  lang : string;
  title : string;
  url : string;
}
[@@deriving eq, show]

let classified_lang url =
  match Link.classify url with
  | Wikipedia {lang; _} -> Some lang
  | Gbif _ | Plantnet _ | Plantnet_observation _ | Plantuse _ | Inpn _ | Tela _
  | Powo _ | Inat _ | Text _ ->
      None

let checked_url url =
  match (String.starts_with ~prefix:"https://" url, classified_lang url) with
  | true, Some _ -> Some url
  | false, _ | true, None -> None

let wikipedia (a : Wikipedia.article) =
  Option.map
    (fun (section, paragraph) ->
      let url = Option.bind a.url checked_url in
      let lang =
        match (a.lang, Option.bind url classified_lang) with
        | Some lang, _ when Link.valid_wikipedia_lang lang -> lang
        | _, Some lang -> lang
        | (Some _ | None), None -> "fr"
      in
      {
        paragraph;
        section;
        lang;
        title = a.title;
        url = Option.value url ~default:(Source_url.wikipedia ~lang a.title);
      })
    (Wikipedia.uses_line a)

type plantuse = {
  summary : string list;
  text : string option;
  title : string;
  url : string;
}
[@@deriving eq, show]

let plantuse (page : Plantuse.page) =
  match Plantuse.uses page with
  | {summary = []; text = None} -> None
  | {summary; text} ->
      Some
        {summary; text; title = page.title; url = Plantuse.page_url page.title}
