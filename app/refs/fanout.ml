module Reference = Herbier_domain.Reference
module Source = Reference.Source
module Status = Reference.Status
module Gbif = Sources.Gbif
module Wikidata = Sources.Wikidata
module Wikipedia = Sources.Wikipedia

let sources = [Source.Gbif; Source.Plantnet; Source.Wikidata; Source.Wikipedia]

type row = {source : Source.t; status : Status.t; payload : Yojson.Safe.t}

let equal_row a b =
  a.source = b.source
  && a.status = b.status
  && Yojson.Safe.equal a.payload b.payload

let empty = `Assoc []

let accepted decode = function
  | Step.Body json -> (
      match decode json with Ok v -> Some (json, v) | Error _ -> None)
  | Step.Absent | Step.Failed _ -> None

let body decode response = Option.map fst (accepted decode response)

let gbif ~key =
  let open Step.Syntax in
  let* species = Step.get (Gbif.species ~key) in
  match species with
  | Step.Absent ->
      Step.return
        [{source = Source.Gbif; status = Status.Missing; payload = empty}]
  | Step.Body _ | Step.Failed _ ->
      let species = body Gbif.species_of_json species in
      let* vernacular_names = Step.get (Gbif.vernacular_names ~key) in
      let* distributions = Step.get (Gbif.distributions ~key) in
      let+ occurrence_count = Step.get (Gbif.occurrence_count ~key) in
      let vernacular_names = body Gbif.vernacular_names_of_json vernacular_names
      and distributions = body Gbif.distributions_of_json distributions
      and occurrence_count =
        body Gbif.occurrence_count_of_json occurrence_count
      in
      let succeeded =
        List.length
          (List.filter Option.is_some
             [species; vernacular_names; distributions; occurrence_count])
      in
      let status =
        match succeeded with
        | 0 -> Status.Failed
        | 4 -> Status.Complete
        | _ -> Status.Partial
      in
      [
        {
          source = Source.Gbif;
          status;
          payload =
            Payload.gbif ~species ~vernacular_names ~distributions
              ~occurrence_count;
        };
      ]

let plantnet ~key =
  let open Step.Syntax in
  let+ media = Step.get (Gbif.plantnet_media ~key) in
  let status, media =
    match accepted Gbif.plantnet_media_of_json media with
    | None -> (Status.Failed, None)
    | Some (json, {Gbif.results = []; _}) -> (Status.Missing, Some json)
    | Some (json, {Gbif.results = _ :: _; _}) -> (Status.Complete, Some json)
  in
  [{source = Source.Plantnet; status; payload = Payload.plantnet ~media}]

let wikipedia_row status summary =
  {source = Source.Wikipedia; status; payload = Payload.wikipedia ~summary}

(* fr, else en (architecture §6); a request is tried only after the
   previous one answered that the page does not exist. *)
let rec summaries = function
  | [] -> Step.return (wikipedia_row Status.Missing None)
  | request :: rest -> (
      let open Step.Syntax in
      let* response = Step.get request in
      match response with
      | Step.Absent -> summaries rest
      | Step.Body _ | Step.Failed _ -> (
          match body Wikipedia.summary_of_json response with
          | Some summary ->
              Step.return (wikipedia_row Status.Complete (Some summary))
          | None -> Step.return (wikipedia_row Status.Failed None)))

let summary_requests (entity : Wikidata.Entity.t) =
  List.filter_map
    (fun lang ->
      Option.bind
        (List.find_opt
           (fun (l : Wikidata.Entity.sitelink) -> String.equal l.lang lang)
           entity.sitelinks)
        (fun (l : Wikidata.Entity.sitelink) ->
          Wikipedia.summary ~lang ~title:l.title))
    ["fr"; "en"]

let wikidata_row status ~search ~entity =
  {source = Source.Wikidata; status; payload = Payload.wikidata ~search ~entity}

let wiki ~key =
  let open Step.Syntax in
  let no_item search entity =
    Step.return
      [
        wikidata_row Status.Missing ~search ~entity;
        wikipedia_row Status.Missing None;
      ]
  in
  match Wikidata.search ~property:Gbif_key ~value:(string_of_int key) with
  | None -> no_item None None
  | Some request -> (
      let* search = Step.get request in
      match accepted Wikidata.search_of_json search with
      | None ->
          Step.return
            [
              wikidata_row Status.Failed ~search:None ~entity:None;
              wikipedia_row Status.Failed None;
            ]
      | Some (search, []) -> no_item (Some search) None
      | Some (search, qid :: _) -> (
          let* entity = Step.get (Wikidata.entity qid) in
          match accepted Wikidata.entity_of_json entity with
          | None ->
              Step.return
                [
                  wikidata_row Status.Partial ~search:(Some search) ~entity:None;
                  wikipedia_row Status.Failed None;
                ]
          | Some (entity, None) -> no_item (Some search) (Some entity)
          | Some (json, Some decoded) ->
              let+ wikipedia = summaries (summary_requests decoded) in
              [
                wikidata_row Status.Complete ~search:(Some search)
                  ~entity:(Some json);
                wikipedia;
              ]))

let branches ~gbif_key:key = [gbif ~key; plantnet ~key; wiki ~key]

let live_row previous source =
  List.find_opt
    (fun (r : Reference.t) -> r.source = source && Option.is_none r.deleted_at)
    previous

let merge ~previous row =
  `Assoc
    (List.filter_map
       (fun part ->
         let member =
           match Payload.get part row.payload with
           | Some _ as v -> v
           | None -> Payload.get part previous
         in
         Option.map (fun v -> (Payload.name part, v)) member)
       (Payload.parts row.source))

let decide ~previous rows =
  List.filter_map
    (fun row ->
      match (row.status, live_row previous row.source) with
      | Status.Failed, Some _ -> None
      | Status.Partial, Some (p : Reference.t) ->
          Some {row with payload = merge ~previous:p.payload row}
      | (Status.Failed | Status.Partial | Status.Complete | Status.Missing), _
        ->
          Some row)
    rows

let days n = Ptime.Span.of_int_s (n * 86_400)
let max_age = days 90
let retry_after = days 1
let older_than ~now span t = Ptime.Span.compare (Ptime.diff now t) span > 0

let due ~now references =
  List.exists
    (fun source ->
      match live_row references source with
      | None -> true
      | Some (r : Reference.t) -> (
          older_than ~now max_age r.fetched_at
          ||
          match r.status with
          | Status.Failed | Status.Partial ->
              older_than ~now retry_after r.fetched_at
          | Status.Complete | Status.Missing -> false))
    sources
