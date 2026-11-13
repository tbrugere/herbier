module Reference = Herbier_domain.Reference
module Source = Reference.Source
module Link = Herbier_domain.Link
module Gbif = Sources.Gbif
module Wikidata = Sources.Wikidata
module Wikipedia = Sources.Wikipedia

type t = {source : Source.t; url : string}

let link_order =
  [
    Source.Gbif;
    Plantnet;
    Wikipedia;
    Powo;
    Taxref;
    Tela;
    Inat;
    Eppo;
    Wikidata;
    Ipni;
  ]

(* The URL builders are Source_url's, whose parser is Herbier_domain.Link;
   the link_classification test of test_projection checks that every
   derived link classifies back to its source. Wikidata's ids are checked
   here first. *)

let all_chars f s = s <> "" && String.for_all f s

let powo_url powo =
  match Source_url.is_ipni_lsid powo with
  | true -> Some (Source_url.powo powo)
  | false -> None

let eppo_url eppo =
  match
    all_chars (function 'A' .. 'Z' | '0' .. '9' -> true | _ -> false) eppo
  with
  | true -> Some (Source_url.eppo eppo)
  | false -> None

(* Link.classify reads ids as positive ints, so a derived link is built
   only from one. *)
let positive url = function
  | Some n when n > 0 -> Some (url n)
  | Some _ | None -> None

let wikipedia_url (summary : Wikipedia.t) =
  match (summary.kind, summary.page_url) with
  | Standard, Some url when String.starts_with ~prefix:"https://" url -> (
      match Link.classify url with
      | Wikipedia _ -> Some url
      | Gbif _ | Plantnet _ | Plantnet_observation _ | Plantuse _ | Inpn _
      | Tela _ | Powo _ | Inat _ | Text _ ->
          None)
  | (Standard | Disambiguation | Other _), _ -> None

let derived ~taxon ~entity ~summary source =
  let from_entity f = Option.bind entity f in
  match (source : Source.t) with
  | Gbif -> Option.map (fun (t : Gbif.Taxon.t) -> Gbif.species_url t.key) taxon
  | Wikipedia -> Option.bind summary wikipedia_url
  | Powo ->
      from_entity (fun (e : Wikidata.Entity.t) -> Option.bind e.powo powo_url)
  | Taxref ->
      from_entity (fun (e : Wikidata.Entity.t) ->
          positive Source_url.taxref e.taxref)
  | Tela ->
      from_entity (fun (e : Wikidata.Entity.t) ->
          positive Source_url.tela e.tela)
  | Inat ->
      from_entity (fun (e : Wikidata.Entity.t) ->
          positive Source_url.inat e.inat)
  | Eppo ->
      from_entity (fun (e : Wikidata.Entity.t) -> Option.bind e.eppo eppo_url)
  | Plantnet | Wikidata | Ipni -> None

let classified_source : Link.t -> Source.t option = function
  | Gbif _ -> Some Gbif
  | Plantnet _ | Plantnet_observation _ | Plantuse _ -> Some Plantnet
  | Wikipedia _ -> Some Wikipedia
  | Inpn _ -> Some Taxref
  | Tela _ -> Some Tela
  | Powo _ -> Some Powo
  | Inat _ -> Some Inat
  | Text _ -> None

(* Hosts of the sources Link.classify has no constructor for. *)
let prefixes : Source.t -> string list = function
  | Eppo -> ["https://gd.eppo.int/"]
  | Wikidata -> ["https://www.wikidata.org/"; "https://m.wikidata.org/"]
  | Ipni -> ["https://www.ipni.org/"; "https://ipni.org/"]
  | Gbif | Plantnet | Wikipedia | Powo | Taxref | Tela | Inat -> []

let stored_url_ok source url =
  String.starts_with ~prefix:"https://" url
  && String.for_all (fun c -> c > ' ' && c <> '\x7f') url
  &&
  match classified_source (Link.classify url) with
  | Some s -> Source.equal s source
  | None ->
      List.exists
        (fun prefix -> String.starts_with ~prefix url)
        (prefixes source)

let links ~plant_refs ~taxon ~entity ~summary =
  List.filter_map
    (fun source ->
      let stored =
        List.find_opt
          (fun (r : Reference.Plant_ref.t) ->
            Source.equal r.source source
            && Option.is_none r.deleted_at
            && stored_url_ok source r.url)
          plant_refs
      in
      match stored with
      | Some r -> Some {source; url = r.url}
      | None ->
          Option.map
            (fun url -> {source; url})
            (derived ~taxon ~entity ~summary source))
    link_order
