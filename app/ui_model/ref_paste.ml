module Link = Herbier_domain.Link
module Source = Herbier_domain.Reference.Source
module Plant_ref = Herbier_domain.Reference.Plant_ref

type t =
  | Species of int
  | Plant_ref of {source : Source.t; external_id : string; url : string}
  | Not_a_reference
  | Unrecognised
[@@deriving eq]

module Source_url = Herbier_refs.Source_url

let plant_ref source external_id url = Plant_ref {source; external_id; url}

(* URLs are rebuilt from the classified id: [Link.classify] does not return
   the matched span, and a rebuilt URL drops tracking queries. *)
let of_text text =
  match Link.classify text with
  | Link.Gbif key -> Species key
  | Link.Plantnet name ->
      plant_ref Source.Plantnet name (Source_url.plantnet name)
  | Link.Wikipedia {lang; title} ->
      plant_ref Source.Wikipedia
        (lang ^ ":" ^ title)
        (Source_url.wikipedia ~lang title)
  | Link.Inpn cd ->
      plant_ref Source.Taxref (string_of_int cd) (Source_url.taxref cd)
  | Link.Tela nn ->
      plant_ref Source.Tela (string_of_int nn) (Source_url.tela nn)
  | Link.Powo id -> plant_ref Source.Powo id (Source_url.powo id)
  | Link.Inat id ->
      plant_ref Source.Inat (string_of_int id) (Source_url.inat id)
  | Link.Plantuse _ | Link.Plantnet_observation _ -> Not_a_reference
  | Link.Text _ -> Unrecognised

let removable (r : Plant_ref.t) =
  match r.source with
  | Source.Gbif -> false
  | Source.Wikidata | Wikipedia | Powo | Ipni | Taxref | Tela | Eppo | Inat
  | Plantnet ->
      true

let label (r : Plant_ref.t) =
  Ref_text.source_name r.source ^ " · " ^ r.external_id
