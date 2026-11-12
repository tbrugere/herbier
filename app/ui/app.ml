module Db = Herbier_store.Db
module Plants = Herbier_store.Plants
module References = Herbier_store.References
module Plant_id = Herbier_domain.Ids.Plant_id
module Source = Herbier_domain.Reference.Source

(* A plant's running thumbnail sync, and whether another was asked for
   meanwhile. *)
type thumb_sync = Running | Rerun_requested

type t = {
  db : Db.t;
  state : State.t;
  theme : (Theme.t, Theme.error) result;
  saved : unit React.event;
  send_saved : unit -> unit;
  generations : (Plant_id.t * int) list ref;
      (* style: mutable because a fetch's saves are checked against the
         plant's current generation when each branch ends, outside any
         reaction; nothing outside this module sees it. *)
  running : (Plant_id.t * int) list ref;
      (* style: mutable for the same reason: a fetch settles in a future's
         callback, outside any reaction. The fetches started and not settled
         or superseded, by generation; [fetching] is set from it. *)
  fetching : Plant_id.t list React.signal;
  set_fetching : Plant_id.t list -> unit;
  thumbs : (Plant_id.t * thumb_sync) list ref;
      (* style: mutable for the same reason: a thumbnail sync settles in a
         future's callback. The plants with a sync running. *)
}

let create ~db ~state ~theme =
  let saved, send = React.E.create () in
  let fetching, set_fetching =
    React.S.create ~eq:(List.equal Plant_id.equal) []
  in
  {
    db;
    state;
    theme;
    saved;
    send_saved = (fun () -> send ());
    generations = ref [];
    running = ref [];
    fetching;
    set_fetching = (fun ids -> set_fetching ids);
    thumbs = ref [];
  }

let db t = t.db
let state t = t.state
let theme t = t.theme
let saved t = t.saved

(* [saved] fires from its own reaction on the result, so a subscriber that
   raises cannot keep the caller's future from being determined. *)
let save t edits =
  let r = Db.edit t.db edits in
  Fut.await r (function Ok 0 | Error _ -> () | Ok _ -> t.send_saved ());
  r

let save_photos t ~(observation : Herbier_domain.Observation.t) shots =
  let target = (React.S.value (State.account t.state)).storage in
  let one (s : Herbier_photos.Capture.shot) =
    Herbier_photos.Preview.save t.db ~preview:s.preview
      ~observation_id:observation.id
      ~taken_at:(Option.value s.exif.taken_at ~default:(Ptime_clock.now ()))
      ~original_target:target s.original
  in
  let step (saved, failed) s =
    Fut.map
      (function
        | Ok (_ : Herbier_domain.Photo.t) -> (saved + 1, failed)
        | Error e ->
            Brr.Console.(
              error
                [str "photo"; str (Herbier_photos.Preview.error_to_string e)]);
            (saved, s :: failed))
      (one s)
  in
  Fut.map
    (fun (saved, failed) ->
      (match saved with 0 -> () | _ -> t.send_saved ());
      List.rev failed)
    (List.fold_left
       (fun acc s -> Fut.bind acc (fun r -> step r s))
       (Fut.return (0, []))
       shots)

(* References (architecture §6). *)

type link_error = Plant_gone | Store of Db.error

let fetching t = t.fetching
let log parts = Brr.Console.(log [str (String.concat " " parts)])
let online t = (React.S.value (State.network t.state)).online

let generation t id =
  Option.value ~default:0
    (List.find_map
       (fun (p, g) ->
         match Plant_id.equal p id with true -> Some g | false -> None)
       !(t.generations))

let publish_running t =
  let ids =
    List.fold_left
      (fun acc (id, _) ->
        match List.exists (Plant_id.equal id) acc with
        | true -> acc
        | false -> id :: acc)
      [] !(t.running)
  in
  t.set_fetching (List.rev ids)

(* A new generation makes every save of an earlier fetch of the plant
   refused: since Db serialises operations, a branch save queued before
   this point lands first, and one attempted after it is dropped. The
   earlier fetch no longer counts as running, so it holds no ↻ back. *)
let supersede t id =
  let g = generation t id + 1 in
  t.generations :=
    (id, g)
    :: List.filter (fun (p, _) -> not (Plant_id.equal p id)) !(t.generations);
  t.running :=
    List.filter (fun (p, _) -> not (Plant_id.equal p id)) !(t.running);
  publish_running t;
  g

let report_line label report =
  "refs: report"
  :: label
  :: List.map
       (fun (source, outcome) ->
         Source.to_string source
         ^ " "
         ^ Herbier_refs_io.Pipeline.outcome_to_string outcome)
       report

let without id = List.filter (fun (p, _) -> not (Plant_id.equal p id))

let thumbs_line label report =
  String.concat " "
    ("refs: thumbs"
    :: label
    :: List.concat_map
         (fun (organ, outcome) ->
           [
             Herbier_domain.Reference.Organ.to_string organ;
             Herbier_refs_io.Organ_thumbs.outcome_to_string outcome;
           ])
         report)

(* One sync per plant at a time; one asked for while it runs (a fetch that
   ended meanwhile may have changed the wanted images) runs once it ends. *)
let rec sync_thumbs t id =
  match
    (online t, List.exists (fun (p, _) -> Plant_id.equal p id) !(t.thumbs))
  with
  | false, _ -> ()
  | true, true -> t.thumbs := (id, Rerun_requested) :: without id !(t.thumbs)
  | true, false ->
      t.thumbs := (id, Running) :: !(t.thumbs);
      let label = Plant_id.to_string id in
      Fut.await (Herbier_refs_io.Organ_thumbs.sync t.db ~plant:id)
        (fun result ->
          let again =
            List.find_map
              (fun (p, s) ->
                match Plant_id.equal p id with true -> Some s | false -> None)
              !(t.thumbs)
          in
          t.thumbs := without id !(t.thumbs);
          (match result with
          | Error e ->
              Brr.Console.(
                error
                  [str "refs: thumbs"; str label; str (Db.error_to_string e)])
          | Ok [] -> ()
          | Ok report -> (
              let failed = function
                | _, Herbier_refs.Organ_photos.Failed _ -> true
                | ( _,
                    Herbier_refs.Organ_photos.(
                      Present | Updated | Downloaded | Removed) ) ->
                    false
              in
              let line = thumbs_line label report in
              (match List.exists failed report with
              | true -> Brr.Console.(error [str line])
              | false -> log [line]);
              match Herbier_refs_io.Organ_thumbs.changed report with
              | true -> t.send_saved ()
              | false -> ()));
          match again with
          | Some Rerun_requested -> sync_thumbs t id
          | Some Running | None -> ())

let start_fetch t id gbif_key =
  let g = supersede t id in
  t.running := !(t.running) @ [(id, g)];
  publish_running t;
  let label = Plant_id.to_string id in
  log ["refs: fetch"; label; string_of_int gbif_key];
  let save edits =
    match generation t id = g with true -> Some (save t edits) | false -> None
  in
  Fut.await (Herbier_refs_io.Pipeline.fetch t.db ~save ~plant:id ~gbif_key)
    (fun result ->
      t.running :=
        List.filter
          (fun (p, h) -> not (Plant_id.equal p id && Int.equal h g))
          !(t.running);
      publish_running t;
      (match result with
      | Error e ->
          Brr.Console.(
            error [str "refs: read"; str label; str (Db.error_to_string e)])
      | Ok report -> (
          let not_saved = function
            | _, Herbier_refs_io.Pipeline.Not_saved _ -> true
            | ( _,
                Herbier_refs_io.Pipeline.(
                  Written _ | Kept | Skipped | Not_fetched) ) ->
                false
          in
          let line = String.concat " " (report_line label report) in
          match List.exists not_saved report with
          | true -> Brr.Console.(error [str line])
          | false -> log [line]));
      (* Whatever the report: a thumbnail that failed before is retried. *)
      sync_thumbs t id)

let is_fetching t id =
  List.exists (Plant_id.equal id) (React.S.value t.fetching)

let read_error e =
  Brr.Console.(error [str "refs: read"; str (Db.error_to_string e)])

let refresh t id =
  match (online t, is_fetching t id) with
  | false, _ | true, true -> ()
  | true, false ->
      Fut.await
        (Db.find t.db (Plants.get id))
        (function
          | Error e -> read_error e
          | Ok None -> ()
          | Ok (Some (p : Herbier_domain.Plant.t)) -> (
              match (p.gbif_key, is_fetching t id) with
              | Some key, false -> start_fetch t id key
              | None, _ | Some _, true -> ()))

(* The plant first: an unlinked one needs no look at its rows. *)
let refresh_if_due t id =
  match online t with
  | false -> ()
  | true ->
      let open Fut.Syntax in
      Fut.await
        (let* plant = Db.find t.db (Plants.get id) in
         match plant with
         | Error e -> Fut.return (Error e)
         | Ok None -> Fut.return (Ok None)
         | Ok (Some (p : Herbier_domain.Plant.t)) -> (
             match p.gbif_key with
             | None -> Fut.return (Ok None)
             | Some key ->
                 let+ rows = Db.all t.db (References.of_plant id) in
                 Result.map (fun rows -> Some (key, rows)) rows))
        (function
          | Error e -> read_error e
          | Ok None -> ()
          | Ok (Some (key, rows)) -> (
              match
                Herbier_refs.Fanout.due ~now:(Ptime_clock.now ()) rows
                && (not (is_fetching t id))
                && online t
              with
              | true -> start_fetch t id key
              | false -> (
                  (* A running fetch syncs when it ends. *)
                  match is_fetching t id with
                  | true -> ()
                  | false -> sync_thumbs t id)))

let link t id (taxon : Herbier_refs.Sources.Gbif.Taxon.t) =
  let open Fut.Syntax in
  let* plant = Db.find t.db (Plants.get id) in
  match plant with
  | Error e -> Fut.return (Error (Store e))
  | Ok None -> Fut.return (Error Plant_gone)
  | Ok (Some plant) -> (
      let at = Ptime_clock.now () in
      (* Every fetched source, not the rows read now: a branch of the old
         key's fetch may still save before [supersede] below. *)
      let removes =
        match Plant_link.retires_references plant taxon with
        | false -> []
        | true ->
            List.map
              (fun source -> References.remove ~plant:id ~source ~at)
              Herbier_refs.Fanout.sources
      in
      let edits =
        Plants.upsert (Plant_link.apply ~at plant taxon)
        :: References.link ~plant:id ~source:Source.Gbif
             ~external_id:(string_of_int taxon.key)
             ~url:(Herbier_refs.Sources.Gbif.species_url taxon.key)
             ~at
        :: removes
      in
      let was_fetching = is_fetching t id in
      let (_ : int) = supersede t id in
      let+ saved = save t edits in
      match saved with
      | Error e ->
          (* Nothing changed, but the old key's fetch was dropped. *)
          (match was_fetching with true -> refresh t id | false -> ());
          Error (Store e)
      | Ok (_ : int) ->
          (* Offline, the next fiche opening fetches: the plant is due. *)
          (match online t with
          | true -> start_fetch t id taxon.key
          | false -> ());
          Ok ())
