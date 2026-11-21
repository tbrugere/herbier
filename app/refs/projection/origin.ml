module Source = Herbier_domain.Reference.Source
module Gbif = Sources.Gbif

type area = {code : string option; name : string} [@@deriving eq]
type t = {native : area list; introduced : area list}

let tdwg = "TDWG:"

let code_of = function
  | Some id
    when String.length id > String.length tdwg
         && String.starts_with ~prefix:tdwg id ->
      Some
        (String.sub id (String.length tdwg)
           (String.length id - String.length tdwg))
  | Some _ | None -> None

(* Two rows name one area when their codes match; a row without a code (a
   country name in locationId) can only be matched by its locality. *)
let same_area a b =
  match (a.code, b.code) with
  | Some x, Some y -> String.equal x y
  | Some _, None | None, Some _ | None, None -> String.equal a.name b.name

let dedup_first items =
  List.rev
    (List.fold_left
       (fun acc x ->
         match List.exists (same_area x) acc with
         | true -> acc
         | false -> x :: acc)
       [] items)

(* GBIF's distribution statuses that say the taxon occurs there; ABSENT,
   EXCLUDED and DOUBTFUL do not. *)
let present = function
  | None | Some ("PRESENT" | "COMMON" | "RARE" | "IRREGULAR") -> true
  | Some _ -> false

type means = Native | Introduced

(* WCVP leaves native rows without establishmentMeans. UNCERTAIN, or a value
   GBIF may add, is neither. *)
let means = function
  | None | Some "NATIVE" -> Some Native
  | Some ("INTRODUCED" | "NATURALISED" | "INVASIVE" | "MANAGED") ->
      Some Introduced
  | Some _ -> None

let origin (page : Gbif.Distribution.t Gbif.page) =
  let rows =
    List.filter_map
      (fun (d : Gbif.Distribution.t) ->
        match
          (d.source, d.locality, present d.status, means d.establishment_means)
        with
        | ( Some "The World Checklist of Vascular Plants (WCVP)",
            Some locality,
            true,
            Some m ) ->
            Some ({code = code_of d.location_id; name = locality}, m)
        | _ -> None)
      page.results
  in
  let native, introduced =
    List.partition
      (fun (_, m) -> match m with Native -> true | Introduced -> false)
      rows
  in
  match
    (dedup_first (List.map fst native), dedup_first (List.map fst introduced))
  with
  | [], [] -> None
  | native, introduced -> Some (Cited.v [Source.Gbif] {native; introduced})

let red_list (page : Gbif.Distribution.t Gbif.page) =
  List.find_map
    (fun (d : Gbif.Distribution.t) ->
      match (d.source, d.country, d.threat_status) with
      | Some "The IUCN Red List of Threatened Species", None, Some status ->
          Some (Cited.v [Source.Gbif] status)
      | _ -> None)
    page.results
