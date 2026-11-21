module Reference = Herbier_domain.Reference
module Fetch_state = Reference.Fetch_state
module Plant = Herbier_domain.Plant
module Plant_id = Herbier_domain.Ids.Plant_id

type trigger =
  | Linked
  | Refresh
  | Opened of Reference.t list
  | Reconnected of {states : Fetch_state.t list; back_online : bool}

type action = Fetch | Sync_thumbs | Nothing [@@deriving eq, show]

let failed_retry_after = Ptime.Span.of_int_s (10 * 60)

let unfinished ?(back_online = false) ~now states =
  let state source =
    List.find_opt
      (fun (s : Fetch_state.t) -> Reference.Source.equal s.source source)
      states
  in
  List.exists
    (fun source ->
      match state source with
      | None -> true
      | Some {status = Failed; fetched_at; _} ->
          back_online
          || Ptime.Span.compare (Ptime.diff now fetched_at) failed_retry_after
             > 0
      | Some {status = Complete | Partial | Missing; _} -> false)
    Fanout.sources

let decide trigger ~online ~running ~now =
  match (online, trigger, running) with
  | false, (Linked | Refresh | Opened _ | Reconnected _), _ -> Nothing
  | true, Linked, _ -> Fetch
  | true, (Refresh | Opened _ | Reconnected _), true -> Nothing
  | true, Refresh, false -> Fetch
  | true, Opened rows, false -> (
      match
        Fanout.due ~now rows
        || unfinished ~now (List.filter_map Fetch_state.of_reference rows)
      with
      | true -> Fetch
      | false -> Sync_thumbs)
  | true, Reconnected {states; back_online}, false -> (
      match unfinished ~back_online ~now states with
      | true -> Fetch
      | false -> Nothing)

let pending ~back_online ~now ~plants ~states =
  let states_of id =
    List.filter (fun (s : Fetch_state.t) -> Plant_id.equal s.plant_id id) states
  in
  plants
  |> List.filter_map (fun (p : Plant.t) ->
      match (p.deleted_at, p.gbif_key) with
      | None, Some key when unfinished ~back_online ~now (states_of p.id) ->
          Some (p, key)
      | _ -> None)
  |> List.sort (fun ((a : Plant.t), _) ((b : Plant.t), _) ->
      match Ptime.compare b.updated_at a.updated_at with
      | 0 -> Plant_id.compare a.id b.id
      | c -> c)
  |> List.map (fun ((p : Plant.t), key) -> (p.id, key))
