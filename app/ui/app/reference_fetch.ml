module Plant_link = Herbier_ui_model.Plant_link
module Db = Herbier_store_io.Db
module Plants = Herbier_store.Plants
module References = Herbier_store.References
module Plant_id = Herbier_domain.Ids.Plant_id
module Source = Herbier_domain.Reference.Source

type link_error = Plant_gone | Store of Db.error

let fetching (t : Core.t) = t.fetching

let generation (t : Core.t) id =
  Option.value ~default:0
    (List.find_map
       (fun (p, g) ->
         match Plant_id.equal p id with true -> Some g | false -> None)
       !(t.generations))

let publish_running (t : Core.t) =
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
let supersede (t : Core.t) id =
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
   ended meanwhile may have changed the wanted images) runs once it ends.
   None starts during « Libérer »: its files would go with the directory
   (the next fiche entry asks again). *)
let rec sync_thumbs (t : Core.t) id =
  match
    ( Core.online t && not !(t.freeing),
      List.exists (fun (p, _) -> Plant_id.equal p id) !(t.thumbs) )
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
              | false -> Core.log [line]);
              match Herbier_refs_io.Organ_thumbs.changed report with
              | true -> t.send_saved ()
              | false -> ()));
          match again with
          | Some Rerun_requested -> sync_thumbs t id
          | Some Running | None -> ())

let start_fetch (t : Core.t) id gbif_key =
  let g = supersede t id in
  t.running := !(t.running) @ [(id, g)];
  publish_running t;
  let label = Plant_id.to_string id in
  Core.log ["refs: fetch"; label; string_of_int gbif_key];
  let save edits =
    match generation t id = g with
    | true -> Some (Core.commit t edits)
    | false -> None
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
          | false -> Core.log [line]));
      (* Whatever the report: a thumbnail that failed before is retried. *)
      sync_thumbs t id)

let is_fetching (t : Core.t) id =
  List.exists (Plant_id.equal id) (React.S.value t.fetching)

let read_error = Log.db "refs: read"

let refresh (t : Core.t) id =
  match (Core.online t, is_fetching t id) with
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
let refresh_if_due (t : Core.t) id =
  match Core.online t with
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
                && Core.online t
              with
              | true -> start_fetch t id key
              | false -> (
                  (* A running fetch syncs when it ends. *)
                  match is_fetching t id with
                  | true -> ()
                  | false -> sync_thumbs t id)))

let gbif_ref ~plant ~at (taxon : Herbier_refs.Sources.Gbif.Taxon.t) =
  References.link ~plant ~source:Source.Gbif
    ~external_id:(string_of_int taxon.key)
    ~url:(Herbier_refs.Sources.Gbif.species_url taxon.key)
    ~at

(* The sources a plant ref can be pasted for (5a): all but the GBIF link,
   which {!link} itself writes. *)
let pasted_source = function
  | Source.Gbif -> false
  | Source.(
      ( Wikidata | Wikipedia | Powo | Ipni | Taxref | Tela | Eppo | Inat
      | Plantnet )) ->
      true

let fetch_if_online (t : Core.t) id key =
  match Core.online t with true -> start_fetch t id key | false -> ()

let link (t : Core.t) ?name id (taxon : Herbier_refs.Sources.Gbif.Taxon.t) =
  let open Fut.Syntax in
  let* plant = Db.find t.db (Plants.get id) in
  match plant with
  | Error e -> Fut.return (Error (Store e))
  | Ok None -> Fut.return (Error Plant_gone)
  | Ok (Some plant) -> (
      let at = Ptime_clock.now () in
      (* Every fetched source, not the rows read now: a branch of the old
         key's fetch may still save before [supersede] below. The pasted
         links named the old taxon too, so they go with it. *)
      let removes =
        match Plant_link.retires_references plant taxon with
        | false -> []
        | true ->
            List.map
              (fun source -> References.remove ~plant:id ~source ~at)
              Herbier_refs.Fanout.sources
            @ List.map
                (fun source -> References.unlink ~plant:id ~source ~at)
                (List.filter pasted_source Source.all)
      in
      let edits =
        Plants.upsert (Plant_link.apply ~at ?name plant taxon)
        :: gbif_ref ~plant:id ~at taxon
        :: removes
      in
      let was_fetching = is_fetching t id in
      let (_ : int) = supersede t id in
      let+ saved = Geocoding.save t edits in
      match saved with
      | Error e ->
          (* Nothing changed, but the old key's fetch was dropped. *)
          (match was_fetching with true -> refresh t id | false -> ());
          Error (Store e)
      | Ok (_ : int) ->
          (* Offline, the next fiche opening fetches: the plant is due. *)
          fetch_if_online t id taxon.key;
          Ok ())

let create_linked (t : Core.t) ?(extra = []) (plant : Herbier_domain.Plant.t)
    (taxon : Herbier_refs.Sources.Gbif.Taxon.t) =
  let open Fut.Syntax in
  let edits =
    Plants.upsert plant
    :: gbif_ref ~plant:plant.id ~at:plant.updated_at taxon
    :: extra
  in
  let+ saved = Geocoding.save t edits in
  match saved with
  | Error e -> Error e
  | Ok (_ : int) ->
      fetch_if_online t plant.id taxon.key;
      Ok ()

module Offline_data = Herbier_ui_model.Offline_data
module Files = Herbier_store_io.Files

type free_error =
  | Busy
  | Store of Db.error
  | Files of Herbier_bindings.Cap_error.t

let offline_usage () =
  let open Fut.Result_syntax in
  let* previews = Files.usage ~dir:Files.previews_dir in
  let+ reference_photos = Files.usage ~dir:Files.refthumbs_dir in
  {Offline_data.previews; reference_photos}

(* Rows first, then files: a row never points to a deleted file. A failed
   rmdir leaves orphans that the next downloads overwrite. *)
let clear_and_delete (t : Core.t) =
  let open Fut.Syntax in
  let* cleared = Db.write t.db Herbier_store.Ref_images.clear_thumbs in
  match cleared with
  | Error e -> Fut.return (Error (`Store e))
  | Ok (_ : int) ->
      Herbier_bindings.Fut_result.map_error
        (fun e -> `Files e)
        (Files.delete_dir ~dir:Files.refthumbs_dir)

let free_reference_photos (t : Core.t) =
  match (!(t.freeing), !(t.thumbs)) with
  | true, _ | false, _ :: _ -> Fut.return (Error Busy)
  | false, [] ->
      t.freeing := true;
      let freed =
        Fut.map
          (fun result ->
            t.freeing := false;
            (match result with
            | Ok () -> Core.log ["offline: freed reference photos"]
            | Error (`Store e) ->
                Core.log_error
                  ["offline: free reference photos"; Db.error_to_string e]
            | Error (`Files e) ->
                Core.log_error
                  [
                    "offline: free reference photos";
                    Herbier_bindings.Cap_error.to_string e;
                  ]);
            result)
          (clear_and_delete t)
      in
      (* From its own reaction, so a subscriber that raises cannot keep the
         caller's future from being determined. *)
      Fut.await freed (function
        | Ok () -> t.send_saved ()
        | Error (`Store _ | `Files _) -> ());
      Fut.map
        (Result.map_error (function `Store e -> Store e | `Files e -> Files e))
        freed
