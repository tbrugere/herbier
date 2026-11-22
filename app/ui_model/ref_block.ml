module Projection = Herbier_refs.Projection
module Reference = Herbier_domain.Reference

type link = {label : string; url : string}
type plantuse_uses = {chips : string list; line : string option; url : string}
type wikipedia_uses = {paragraph : string; url : string}

type uses =
  | Plantuse_only of plantuse_uses
  | Wikipedia_only of wikipedia_uses
  | Both of plantuse_uses * wikipedia_uses

let uses_parts = function
  | Plantuse_only p -> (Some p, None)
  | Wikipedia_only w -> (None, Some w)
  | Both (p, w) -> (Some p, Some w)

type row =
  | Names of {
      french : string list;
      others : Projection.vernacular list;
      family : string option;
      sources : string;
    }
  | Life_form of {text : string; sources : string}
  | Origin of {
      native : string option;
      introduced : string option;
      sources : string;
    }
  | En_france of {chips : string list; places : string option; sources : string}
  | Red_list of {label : string; chip : string; sources : string}
  | Flowering of {months : int list; text : string; sources : string}
  | Habitat of {phrase : string option; chips : string list; sources : string}
  | Toxicity of {text : string; sources : string}
  | Uses of uses
  | Organ_photos of {
      photos : (Reference.Organ.t * string) list;
      credits : string;
      sources : string;
    }

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
  Ref_text.in_source_order cited

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
      let french, others =
        List.partition
          (fun (v : Projection.vernacular) ->
            match v.lang with
            | Projection.Lang.Fr -> true
            | Projection.Lang.En | Projection.Lang.De | Projection.Lang.It ->
                false)
          languages
      in
      Some
        (Names
           {
             french =
               List.concat_map
                 (fun (v : Projection.vernacular) -> v.names)
                 french;
             others;
             family;
             sources = Ref_text.names_source_line ~family (names_sources p);
           })

let origin (c : Projection.origin Projection.cited) =
  match
    ( Ref_text.origin_line (Ref_text.origin_names c.value.native),
      Ref_text.origin_line (Ref_text.origin_names c.value.introduced) )
  with
  | None, None -> None
  | native, introduced ->
      Some (Origin {native; introduced; sources = sources c})

(* The row and the sources of its chips. *)
let en_france_cited (p : Projection.t) =
  let status =
    Option.bind p.fr_status (fun (c : _ Projection.cited) ->
        Option.map (fun chip -> (chip, c.sources)) (Ref_text.fr_status c.value))
  and red_list =
    Option.bind p.fr_red_list (fun (c : _ Projection.cited) ->
        Option.map
          (fun chip -> (chip, c.sources))
          (Ref_text.fr_red_list c.value))
  in
  (* INPN answers « not protected » for any taxon it knows, even one absent
     from metropolitan France: alone, it is no data about France. *)
  let protection =
    Option.bind p.fr_protection (fun (c : _ Projection.cited) ->
        match (c.value, status, red_list) with
        | Projection.Not_protected, None, None -> None
        | (Projection.Not_protected | National | Local _), _, _ ->
            Some (Ref_text.fr_protection c.value, c.sources))
  in
  match List.filter_map Fun.id [status; protection; red_list] with
  | [] -> None
  | chips ->
      let cited = Ref_text.in_source_order (List.concat_map snd chips) in
      Some
        ( En_france
            {
              chips = List.map fst chips;
              places =
                Option.bind p.fr_protection (fun (c : _ Projection.cited) ->
                    Ref_text.fr_places c.value);
              sources = Ref_text.sources_line cited;
            },
          cited )

let en_france p = Option.map fst (en_france_cited p)

let uses (p : Projection.t) =
  let plantuse =
    Option.map
      (fun (c : Projection.Uses.plantuse Projection.cited) ->
        {chips = c.value.summary; line = c.value.text; url = c.value.url})
      p.plantuse_uses
  and wikipedia =
    Option.map
      (fun (c : Projection.Uses.wikipedia Projection.cited) ->
        {paragraph = c.value.paragraph; url = c.value.url})
      p.wikipedia_uses
  in
  match (plantuse, wikipedia) with
  | None, None -> None
  | Some p, None -> Some (Uses (Plantuse_only p))
  | None, Some w -> Some (Uses (Wikipedia_only w))
  | Some p, Some w -> Some (Uses (Both (p, w)))

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
             sources = Ref_text.source_name Reference.Source.Plantnet;
           })

let rows (p : Projection.t) ~organ_photos:shown =
  let en_france = en_france p in
  let red_list_label =
    match en_france with
    | Some _ -> "Liste rouge mondiale"
    | None -> "Liste rouge"
  in
  List.filter_map Fun.id
    [
      names p;
      Option.map
        (fun (c : _ Projection.cited) ->
          Life_form {text = c.value; sources = sources c})
        p.life_form;
      Option.bind p.origin origin;
      en_france;
      Option.bind p.red_list (fun (c : _ Projection.cited) ->
          Option.map
            (fun chip ->
              Red_list {label = red_list_label; chip; sources = sources c})
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
      uses p;
      organ_photos shown;
    ]

type source = {
  name : string;
  url : string option;
  licence : string option;
  note : string option;
}

type footer = {sources : source list; links : link list}

let cited_sources = function
  | None -> []
  | Some (c : _ Projection.cited) -> c.sources

(* The sources a shown row cites; Wikipedia's « Utilisations » part has a line
   of its own (see [footer]). *)
let row_sources (p : Projection.t) = function
  | Names _ -> names_sources p
  | Life_form _ -> cited_sources p.life_form
  | Origin _ -> cited_sources p.origin
  | En_france _ -> Option.fold ~none:[] ~some:snd (en_france_cited p)
  | Red_list _ -> cited_sources p.red_list
  | Flowering _ -> cited_sources p.flowering_months
  | Habitat _ -> cited_sources p.habitat
  | Toxicity _ -> cited_sources p.toxicity
  | Uses uses -> (
      match uses_parts uses with
      | Some _, _ -> cited_sources p.plantuse_uses
      | None, _ -> [])
  | Organ_photos _ -> [Reference.Source.Plantnet]

let link_of (p : Projection.t) source =
  List.find_map
    (fun (l : Projection.link) ->
      match Reference.Source.equal l.source source with
      | true -> Some l.url
      | false -> None)
    p.links

let photo_licences shown =
  List.fold_left
    (fun acc ((i : Reference.Image.t), _) ->
      match String.trim i.licence with
      | "" -> acc
      | l -> (
          let l = Herbier_identify.Proposal.licence_label l in
          match List.mem l acc with true -> acc | false -> l :: acc))
    [] shown
  |> List.rev
  |> function
  | [] -> None
  | ls -> Some (String.concat ", " ls)

let source_line (p : Projection.t) ~shown source =
  let licence =
    match source with
    | Reference.Source.Wikipedia | Plantuse -> Some Ref_text.quoted_licence
    | Plantnet -> photo_licences shown
    | Gbif | Wikidata | Powo | Ipni | Taxref | Tela | Eppo | Inat -> None
  and url =
    match source with
    | Reference.Source.Plantuse -> (
        match p.plantuse_uses with
        | Some c -> Some c.value.url
        | None -> link_of p source)
    | _ -> link_of p source
  in
  {name = Ref_text.source_name source; url; licence; note = None}

let section_url url section =
  url ^ "#" ^ String.map (function ' ' -> '_' | c -> c) section

let uses_line (c : Projection.Uses.wikipedia Projection.cited) =
  {
    name = Ref_text.wikipedia_section ~lang:c.value.lang ~section:c.value.section;
    url = Some (section_url c.value.url c.value.section);
    licence = Some Ref_text.quoted_licence;
    note = Some Ref_text.auto_extract;
  }

let footer (p : Projection.t) ~organ_photos:shown =
  let shown_rows = rows p ~organ_photos:shown in
  let used = List.concat_map (row_sources p) shown_rows in
  let wiki_uses =
    List.find_map
      (function
        | Uses uses -> (
            match (uses_parts uses, p.wikipedia_uses) with
            | (_, Some _), (Some _ as c) -> c
            | (_, Some _), None | (_, None), _ -> None)
        | _ -> None)
      shown_rows
  in
  let lines =
    List.concat_map
      (fun source ->
        let plain =
          match List.exists (Reference.Source.equal source) used with
          | true -> [source_line p ~shown source]
          | false -> []
        and extract =
          match (source, wiki_uses) with
          | Reference.Source.Wikipedia, Some c -> [uses_line c]
          | _ -> []
        in
        plain @ extract)
      Projection.link_order
  in
  let in_a_line source =
    List.exists (Reference.Source.equal source) used
    || Reference.Source.equal source Reference.Source.Wikipedia
       && Option.is_some wiki_uses
  in
  let links =
    List.filter_map
      (fun (l : Projection.link) ->
        match in_a_line l.source with
        | true -> None
        | false -> Some {label = Ref_text.link_label l.source; url = l.url})
      p.links
  in
  match (lines, links) with
  | [], [] -> None
  | sources, links -> Some {sources; links}
