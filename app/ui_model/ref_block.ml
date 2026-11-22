module Projection = Herbier_refs.Projection
module Reference = Herbier_domain.Reference

type link = {label : string; url : string}

type plantuse_uses = {
  chips : string list;
  line : string option;
  url : string;
  credit : string;
}

type wikipedia_uses = {paragraph : string; url : string; credit : string}

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

let en_france (p : Projection.t) =
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
      let cited = List.concat_map snd chips in
      Some
        (En_france
           {
             chips = List.map fst chips;
             places =
               Option.bind p.fr_protection (fun (c : _ Projection.cited) ->
                   Ref_text.fr_places c.value);
             sources = Ref_text.sources_line (Ref_text.in_source_order cited);
           })

let uses (p : Projection.t) =
  let plantuse =
    Option.map
      (fun (c : Projection.Uses.plantuse Projection.cited) ->
        {
          chips = c.value.summary;
          line = c.value.text;
          url = c.value.url;
          credit = Ref_text.plantuse_credit;
        })
      p.plantuse_uses
  and wikipedia =
    Option.map
      (fun (c : Projection.Uses.wikipedia Projection.cited) ->
        {
          paragraph = c.value.paragraph;
          url = c.value.url;
          credit =
            Ref_text.wikipedia_uses_credit ~lang:c.value.lang
              ~section:c.value.section;
        })
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
      links p.links;
    ]
