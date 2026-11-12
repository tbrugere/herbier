module Projection = Herbier_refs.Projection
module Reference = Herbier_domain.Reference

type link = {label : string; url : string}

type row =
  | Names of {languages : Projection.vernacular list; sources : string}
  | Life_form of {text : string; sources : string}
  | Origin of {
      native : string option;
      introduced : string option;
      sources : string;
    }
  | Red_list of {chip : string; sources : string}
  | Flowering of {months : int list; text : string; sources : string}
  | Habitat of {phrase : string option; chips : string list; sources : string}
  | Toxicity of {text : string; sources : string}
  | Organ_photos of {
      photos : (Reference.Organ.t * string) list;
      credits : string;
      sources : string;
    }
  | Links of link list

let sources (c : _ Projection.cited) = Ref_text.sources_line c.sources

let names_sources (p : Projection.t) =
  let cited =
    List.concat
      [
        Option.fold ~none:[]
          ~some:(fun (c : _ Projection.cited) -> c.sources)
          p.vernacular;
        Option.fold ~none:[]
          ~some:(fun (c : _ Projection.cited) -> c.sources)
          p.taxon;
      ]
  in
  List.filter (fun s -> List.mem s cited) Reference.Source.all

let names (p : Projection.t) =
  let family =
    Option.bind p.taxon (fun (c : _ Projection.cited) ->
        c.value.Herbier_refs.Sources.Gbif.Taxon.family)
  in
  let languages =
    Option.fold ~none:[]
      ~some:(fun (c : _ Projection.cited) -> c.value)
      p.vernacular
  in
  match (languages, family) with
  | [], None -> None
  | _ ->
      Some
        (Names
           {
             languages;
             sources = Ref_text.names_source_line ~family (names_sources p);
           })

let origin (c : Projection.origin Projection.cited) =
  match
    ( Ref_text.origin_line c.value.native,
      Ref_text.origin_line c.value.introduced )
  with
  | None, None -> None
  | native, introduced ->
      Some (Origin {native; introduced; sources = sources c})

let organ_photos = function
  | [] -> None
  | shown ->
      Some
        (Organ_photos
           {
             photos =
               List.map
                 (fun ((i : Reference.Image.t), path) -> (i.organ, path))
                 shown;
             credits = Ref_text.credits (List.map fst shown);
             sources =
               Ref_text.source_name Reference.Source.Plantnet
               ^ " · disponibles hors-ligne";
           })

let links = function
  | [] -> None
  | links ->
      Some
        (Links
           (List.map
              (fun (l : Projection.link) ->
                {label = Ref_text.link_label l.source; url = l.url})
              links))

let rows (p : Projection.t) ~organ_photos:shown =
  List.filter_map Fun.id
    [
      names p;
      Option.map
        (fun (c : _ Projection.cited) ->
          Life_form {text = c.value; sources = sources c})
        p.life_form;
      Option.bind p.origin origin;
      Option.bind p.red_list (fun (c : _ Projection.cited) ->
          Option.map
            (fun chip -> Red_list {chip; sources = sources c})
            (Ref_text.red_list c.value));
      Option.map
        (fun (c : _ Projection.cited) ->
          Flowering
            {
              months = c.value;
              text = Ref_text.months_text c.value;
              sources = sources c;
            })
        p.flowering_months;
      Option.map
        (fun (c : Projection.habitat Projection.cited) ->
          Habitat
            {
              phrase = c.value.phrase;
              chips = c.value.chips;
              sources = sources c;
            })
        p.habitat;
      Option.map
        (fun (c : _ Projection.cited) ->
          Toxicity {text = c.value; sources = sources c})
        p.toxicity;
      organ_photos shown;
      links p.links;
    ]
