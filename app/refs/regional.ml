module Reference = Herbier_domain.Reference
module Source = Reference.Source
module Status = Reference.Status
module Gbif = Sources.Gbif
module Wikidata = Sources.Wikidata
module Tela = Sources.Tela
module Inpn = Sources.Inpn

type input = {name : string option; taxref : int option; settled : bool}
[@@deriving eq, show]

let this_row rows source =
  List.find_opt (fun (r : Fanout.row) -> Source.equal r.source source) rows

let decoded part decode payload =
  Option.bind (Payload.get part payload) (fun json ->
      Result.to_option (decode json))

let this_payload rows source =
  Option.map (fun (r : Fanout.row) -> r.payload) (this_row rows source)

let stored_payload previous source =
  Option.map
    (fun (r : Reference.t) -> r.payload)
    (Fanout.live_row previous source)

let this_status rows source =
  Option.map (fun (r : Fanout.row) -> r.status) (this_row rows source)

let stored_status previous source =
  Option.map
    (fun (r : Reference.t) -> r.status)
    (Fanout.live_row previous source)

let is_missing = function
  | Some Status.Missing -> true
  | Some (Status.Complete | Status.Partial | Status.Failed) | None -> false

(* This fetch's decoded part, else the stored row's. *)
let latest ~previous rows source part decode =
  match Option.bind (this_payload rows source) (decoded part decode) with
  | Some _ as v -> v
  | None -> Option.bind (stored_payload previous source) (decoded part decode)

let input ~previous rows =
  let species =
    latest ~previous rows Source.Gbif Payload.Gbif_species Gbif.species_of_json
  in
  let entity =
    latest ~previous rows Source.Wikidata Payload.Wikidata_entity
      Wikidata.entity_of_json
  in
  {
    name = Option.bind species Gbif.Taxon.without_authorship;
    taxref =
      Option.bind (Option.join entity) (fun (e : Wikidata.Entity.t) -> e.taxref);
    settled =
      (Option.is_some species || is_missing (this_status rows Source.Gbif))
      && (Option.is_some entity
         ||
         match this_status rows Source.Wikidata with
         | Some _ as s -> is_missing s
         | None -> is_missing (stored_status previous Source.Wikidata));
  }

let accepted decode = function
  | Step.Body json -> (
      match decode json with Ok v -> Some (json, v) | Error _ -> None)
  | Step.Absent | Step.Failed _ -> None

(* Where the Tela bridge stopped. [Unmatched]: no BDTFX name or taxon
   (BDTFX said so, or there was no name to ask about once GBIF and Wikidata
   had answered). [Names_failed]: the names call failed, or could not be made
   since GBIF or Wikidata has not answered yet. Without a P3186, a failure
   leaves the TaxRef id unknown and the taxref row is retried. *)
type bridge =
  | Unmatched of {names : Yojson.Safe.t option}
  | Names_failed
  | Taxon_failed of {names : Yojson.Safe.t}
  | Found of {names : Yojson.Safe.t; json : Yojson.Safe.t; taxon : Tela.taxon}

let bridge (input : input) =
  let open Step.Syntax in
  match
    Option.bind input.name (fun n ->
        Option.map (fun r -> (n, r)) (Tela.names ~name:n))
  with
  | None -> (
      match input.settled with
      | true -> Step.return (Unmatched {names = None})
      | false -> Step.return Names_failed)
  | Some (name, request) -> (
      let* response = Step.get request in
      match (response, accepted Tela.names_of_json response) with
      | Step.Absent, _ -> Step.return (Unmatched {names = None})
      | (Step.Body _ | Step.Failed _), None -> Step.return Names_failed
      | (Step.Body _ | Step.Failed _), Some (names, entries) -> (
          match Tela.pick ~name entries with
          | None -> Step.return (Unmatched {names = Some names})
          | Some picked -> (
              let+ response = Step.get (Tela.taxon ~nn:picked.nn) in
              match (response, accepted Tela.taxon_of_json response) with
              | Step.Absent, _ -> Unmatched {names = Some names}
              | (Step.Body _ | Step.Failed _), None -> Taxon_failed {names}
              | (Step.Body _ | Step.Failed _), Some (json, taxon) ->
                  Found {names; json; taxon})))

let tela_row status ?names ?taxon ?baseflor () : Fanout.row =
  {source = Source.Tela; status; payload = Payload.tela ~names ~taxon ~baseflor}

let taxref_row status ?name ?statuses ?red_list ?protections () : Fanout.row =
  {
    source = Source.Taxref;
    status;
    payload = Payload.taxref ~name ~status:statuses ~red_list ~protections;
  }

let tela_reached = function
  | Unmatched {names} -> tela_row Status.Missing ?names ()
  | Names_failed -> tela_row Status.Failed ()
  | Taxon_failed {names} -> tela_row Status.Partial ~names ()
  | Found {names; json; taxon = _} ->
      tela_row Status.Missing ~names ~taxon:json ()

let baseflor = function
  | (Unmatched _ | Names_failed | Taxon_failed _) as b ->
      Step.return (tela_reached b)
  | Found {names; json; taxon} -> (
      let open Step.Syntax in
      let+ response = Step.get (Tela.baseflor ~nn:taxon.id) in
      match (response, accepted Tela.baseflor_of_json response) with
      | Step.Absent, _ -> tela_row Status.Complete ~names ~taxon:json ()
      | (Step.Body _ | Step.Failed _), Some (body, _) ->
          tela_row Status.Complete ~names ~taxon:json ~baseflor:body ()
      | (Step.Body _ | Step.Failed _), None ->
          tela_row Status.Partial ~names ~taxon:json ())

let inpn ~id =
  let open Step.Syntax in
  let* response = Step.get (Inpn.name ~cd_nom:id) in
  match (response, accepted Inpn.name_of_json response) with
  | Step.Absent, _ -> Step.return (taxref_row Status.Missing ())
  | (Step.Body _ | Step.Failed _), None ->
      Step.return (taxref_row Status.Failed ())
  | (Step.Body _ | Step.Failed _), Some (name, {Inpn.cd_ref; _}) ->
      let* status = Step.get (Inpn.status ~cd_ref) in
      let* red_list = Step.get (Inpn.red_list ~cd_ref) in
      let+ protections = Step.get (Inpn.protections ~cd_ref) in
      let body decode r = Option.map fst (accepted decode r) in
      let statuses = body Inpn.status_of_json status
      and red_list = body Inpn.red_list_of_json red_list
      and protections = body Inpn.protections_of_json protections in
      let row =
        match (statuses, red_list, protections) with
        | Some _, Some _, Some _ -> Status.Complete
        | _ -> Status.Partial
      in
      taxref_row row ~name ?statuses ?red_list ?protections ()

let program (input : input) =
  let open Step.Syntax in
  let* bridge = bridge input in
  let id =
    match (input.taxref, bridge) with
    | (Some _ as id), _ -> id
    | None, Found {taxon; _} -> taxon.cd_nom
    | None, (Unmatched _ | Names_failed | Taxon_failed _) -> None
  in
  match id with
  | None ->
      let taxref =
        match (input.settled, bridge) with
        | true, (Unmatched _ | Found _) -> Status.Missing
        | false, _ | _, (Names_failed | Taxon_failed _) -> Status.Failed
      in
      Step.return [taxref_row taxref (); tela_reached bridge]
  | Some id ->
      let* tela = baseflor bridge in
      let+ taxref = inpn ~id in
      [taxref; tela]
