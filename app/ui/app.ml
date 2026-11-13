module Db = Herbier_store.Db
module Plants = Herbier_store.Plants
module References = Herbier_store.References
module Plant_id = Herbier_domain.Ids.Plant_id
module Source = Herbier_domain.Reference.Source
module Observations = Herbier_store.Observations
module Observation_id = Herbier_domain.Ids.Observation_id
module Places = Herbier_domain.Places
module Place_name = Herbier_geo.Place_name
module Communes = Herbier_geo.Communes
module Commune_packs = Herbier_geo.Commune_packs
module Pack_rows = Herbier_store.Commune_packs
module Code = Communes.Code

type geocode_run =
  | Idle
  | Geocoding
  | Geocoding_again (* a trigger came during the run: read the list again *)

(* A plant's running thumbnail sync, and whether another was asked for
   meanwhile. *)
type thumb_sync = Running | Rerun_requested
type pack = {code : Code.t; row : Pack_rows.t; usable : bool}

let equal_pack a b =
  Code.equal a.code b.code
  && Pack_rows.equal a.row b.row
  && Bool.equal a.usable b.usable

type t = {
  db : Db.t;
  state : State.t;
  theme : (Theme.t, Theme.error) result;
  auth : Herbier_sync.Auth.t;
  engine : Herbier_sync.Engine.t;
  keepalive : Herbier_sync.Keepalive.t;
  saved : unit React.event;
  send_saved : unit -> unit;
  synced : unit React.event;
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
  geocode_tried : (Observation_id.t * Places.point) list ref;
      (* style: mutable because a geocode run settles in a future's
         callback, outside any reaction; nothing outside this module sees
         it. The observations not to try again this session, with the
         position they were tried at (a moved one is tried again). *)
  geocode_run : geocode_run ref;
      (* style: mutable for the same reason: whether a run is going, and
         whether a trigger came during it. *)
  place_stored : Place_name.sources ref;
      (* style: mutable because a switch's write settles in a future's
         callback: the switches as last written to the settings table, what
         a failed write falls back to. *)
  place_writes : int ref;
  place_latest : (Place_name.source * int) list ref;
      (* style: mutable for the same reason: a write counter and the latest
         write per source; only the latest one's failure is shown. *)
  place_error : string option React.signal;
  set_place_error : string option -> unit;
  place_error_source : Place_name.source option ref;
      (* style: mutable for the same reason: the source whose failure
         {!place_error} shows, so another source's success keeps it. *)
  thumbs : (Plant_id.t * thumb_sync) list ref;
      (* style: mutable for the same reason: a thumbnail sync settles in a
         future's callback. The plants with a sync running. *)
  communes : Communes.t ref;
      (* style: mutable because the packs load and download in futures'
         callbacks; a geocode run reads it at each observation. *)
  communes_loaded : unit Fut.t;
      (* the startup load of the packs: a geocode run waits for it, so an
         observation saved meanwhile is not skipped past the offline source *)
  packs : pack list React.signal;
  set_packs : ?step:React.step -> pack list -> unit;
  downloading : Communes.departement option React.signal;
  set_downloading : ?step:React.step -> Communes.departement option -> unit;
}

let log_error parts = Brr.Console.(error [str (String.concat " " parts)])

(* The packs' load, started once by [create]: its result fills the index and
   [packs]; a failure leaves them empty. *)
let load_packs db ~communes ~set_packs =
  Fut.map
    (function
      | Error e -> log_error ["communes:"; Commune_packs.error_to_string e]
      | Ok (l : Commune_packs.loaded) ->
          communes := l.index;
          set_packs
            (List.map
               (fun (code, row) ->
                 {
                   code;
                   row;
                   usable = not (List.exists (Code.equal code) l.unreadable);
                 })
               l.rows))
    (Commune_packs.load db)

(* The engine calls [on_cycle] from a future's callback, never inside an
   update step. A pull that wrote rows fires [saved] so screens reload, but
   is no local write: it must not trigger another cycle. *)
let on_cycle ~send_saved ~send_synced (report : Herbier_sync.Cycle.Report.t) =
  (match Herbier_sync.Cycle.Report.pulled_writes report with
  | true -> send_saved ()
  | false -> ());
  send_synced ()

let create ~db ~state ~theme ~auth =
  let saved, send = React.E.create () in
  let synced, send_synced = React.E.create () in
  let send_saved () = send () in
  let keepalive = Herbier_sync.Keepalive.create ~db in
  let engine =
    Herbier_sync.Engine.create ~db ~auth ~keepalive
      ~on_cycle:(on_cycle ~send_saved ~send_synced:(fun () -> send_synced ()))
  in
  let packs, set_packs = React.S.create ~eq:(List.equal equal_pack) [] in
  let set_packs ?step p = set_packs ?step p in
  let downloading, set_downloading =
    React.S.create ~eq:(Option.equal Communes.equal_departement) None
  in
  let set_downloading ?step d = set_downloading ?step d in
  let communes = ref Communes.empty in
  let fetching, set_fetching =
    React.S.create ~eq:(List.equal Plant_id.equal) []
  in
  let place_error, set_place_error =
    React.S.create ~eq:(Option.equal String.equal) None
  in
  {
    db;
    state;
    theme;
    auth;
    engine;
    keepalive;
    saved;
    send_saved;
    synced;
    generations = ref [];
    running = ref [];
    fetching;
    set_fetching = (fun ids -> set_fetching ids);
    geocode_tried = ref [];
    geocode_run = ref Idle;
    place_stored = ref (React.S.value (State.place_sources state));
    place_writes = ref 0;
    place_latest = ref [];
    place_error;
    set_place_error = (fun e -> set_place_error e);
    place_error_source = ref None;
    thumbs = ref [];
    communes;
    communes_loaded = load_packs db ~communes ~set_packs:(fun p -> set_packs p);
    packs;
    set_packs;
    downloading;
    set_downloading;
  }

let db t = t.db
let state t = t.state
let theme t = t.theme
let saved t = t.saved
let auth t = t.auth
let engine t = t.engine
let keepalive t = t.keepalive
let synced t = t.synced

let changed t =
  t.send_saved ();
  Herbier_sync.Engine.local_write t.engine

(* Auth calls [on_change] from future and listener callbacks, never inside an
   update step, so the setter may run here. *)
let start_auth t =
  Herbier_sync.Auth.start t.auth ~on_change:(fun status ->
      let account = React.S.value (State.account t.state) in
      State.set_account t.state {account with auth = status};
      match status with
      | Signed_in _ -> Herbier_sync.Engine.signed_in t.engine
      | Unconfigured | Restoring | Signed_out -> ())

let start_sync t = Herbier_sync.Engine.start t.engine

(* Auth calls the hook from future callbacks; Keepalive logs every
   failure. *)
let start_keepalive t =
  let module K = Herbier_sync.Keepalive in
  let ignore_result (_ : (unit, K.error) result) = () in
  Herbier_sync.Auth.on_job_session t.auth (function
    | Dropped -> Fut.await (K.drop_session t.keepalive) ignore_result
    | Granted s -> Fut.await (K.replace_session t.keepalive s) ignore_result)

(* [saved] fires from its own reaction on the result, so a subscriber that
   raises cannot keep the caller's future from being determined. [commit]
   does not geocode: the geocoder's own writes and the reference branches
   (no observation in them) use it. *)
let commit t edits =
  let r = Db.edit t.db edits in
  Fut.await r (function Ok 0 | Error _ -> () | Ok _ -> changed t);
  r

let log parts = Brr.Console.(log [str (String.concat " " parts)])
let online t = (React.S.value (State.network t.state)).online

(* Place names (architecture §8). *)

let tried t (o : Herbier_domain.Observation.t) p =
  List.exists
    (fun (id, q) -> Observation_id.equal id o.id && Places.equal_point q p)
    !(t.geocode_tried)

let mark_tried t (o : Herbier_domain.Observation.t) p =
  t.geocode_tried := (o.id, p) :: !(t.geocode_tried)

let pending (o : Herbier_domain.Observation.t) =
  Option.map (fun pos -> (o, Places.of_position pos)) o.position

let rec geocode_pending t =
  match !(t.geocode_run) with
  | Geocoding | Geocoding_again -> t.geocode_run := Geocoding_again
  | Idle ->
      t.geocode_run := Geocoding;
      let open Fut.Result_syntax in
      Fut.await
        (let* () = Fut.map Result.ok t.communes_loaded in
         let* observations = Db.all t.db Observations.to_geocode in
         let+ labelled = Db.all t.db Observations.labelled in
         (observations, labelled))
        (function
          | Error e ->
              log_error ["geocode: read"; Db.error_to_string e];
              geocode_end t
          | Ok (observations, labelled) ->
              geocode_each t ~labelled (List.filter_map pending observations))

and geocode_end t =
  let again = !(t.geocode_run) in
  t.geocode_run := Idle;
  match again with
  | Geocoding_again -> geocode_pending t
  | Idle | Geocoding -> ()

and geocode_each t ~labelled = function
  | [] -> geocode_end t
  | ((o : Herbier_domain.Observation.t), (p : Places.point)) :: rest ->
      let id = Observation_id.to_string o.id in
      (* A point already asked at this position keeps its local lookups
         (own places and commune packs: free, and a place labelled or a pack
         downloaded since may name it) but its remote sources are not asked
         again until an online source is turned on. *)
      let current = React.S.value (State.place_sources t.state) in
      let sources =
        match tried t o p with
        | true -> Place_name.offline_only current
        | false -> current
      in
      let online = online t in
      let asked = Place_name.any_online sources && online in
      let allow (r : Herbier_geo.Geocode.request) =
        Place_name.allows
          (React.S.value (State.place_sources t.state))
          r.provider
      in
      Fut.await
        (Herbier_geo.Geocoder.run ~allow
           (Place_name.resolve ~sources ~online ~labelled
              ~communes:!(t.communes) p))
        (function
          | Error (Herbier_geo.Geocoder.Refused _) ->
              (* Its source was turned off while the request waited: not a
                 miss, so the point is asked again if it comes back on. *)
              log ["geocode:"; id; "refused"];
              geocode_each t ~labelled rest
          | Error e ->
              (* A transient error leaves the observation to the next
                 trigger; any other would fail the same way again. *)
              (match Herbier_geo.Geocoder.transient e with
              | true -> ()
              | false -> mark_tried t o p);
              log_error ["geocode:"; id; Herbier_geo.Geocoder.error_to_string e];
              geocode_end t
          | Ok Place_name.Deferred -> geocode_each t ~labelled rest
          | Ok Place_name.Unknown ->
              (match asked with
              | true ->
                  mark_tried t o p;
                  log ["geocode:"; id; "unknown"]
              | false -> ());
              geocode_each t ~labelled rest
          | Ok (Place_name.Named name) -> (
              let edit =
                Observations.set_place_derived o.id ~lat:p.lat ~lon:p.lon name
                  ~at:(Ptime_clock.now ())
              in
              Fut.await (commit t [edit]) @@ function
              | Error e ->
                  mark_tried t o p;
                  log_error ["geocode: save"; id; Db.error_to_string e];
                  geocode_end t
              | Ok 0 ->
                  (* Moved, named or deleted meanwhile: nothing to retry at
                     this position. *)
                  mark_tried t o p;
                  log ["geocode:"; id; "unchanged"];
                  geocode_each t ~labelled rest
              | Ok (_ : int) ->
                  log ["geocode:"; id; "named"];
                  geocode_each t ~labelled rest))

let settings_key = function
  | Place_name.Ign_offline -> Herbier_store.Settings.Place_source_ign_offline
  | Place_name.Ign_online -> Herbier_store.Settings.Place_source_ign_online
  | Place_name.Photon_online ->
      Herbier_store.Settings.Place_source_photon_online

let place_error t = t.place_error

let place_error_text source ~shown ~stored =
  let name = Place_name.label source in
  match (shown, stored) with
  | false, true ->
      Printf.sprintf
        "« %s » : réglage non enregistré. Désactivé jusqu’à la fermeture \
         d’Herbier, il sera de nouveau actif au prochain démarrage. Réessayez."
        name
  | true, _ | false, false ->
      Printf.sprintf "« %s » : réglage non enregistré. Réessayez." name

let set_place_source t source value =
  let show v =
    State.set_place_sources t.state
      (Place_name.set (React.S.value (State.place_sources t.state)) source v)
  in
  incr t.place_writes;
  let mine = !(t.place_writes) in
  let others =
    List.filter
      (fun (s, _) -> not (Place_name.equal_source s source))
      !(t.place_latest)
  in
  t.place_latest := (source, mine) :: others;
  let latest () =
    List.exists
      (fun (s, n) -> Place_name.equal_source s source && Int.equal n mine)
      !(t.place_latest)
  in
  show value;
  Fut.await
    (Db.write t.db (Herbier_store.Settings.set (settings_key source) value))
    (function
      | Error e -> (
          log_error
            [
              "réglages: noms de lieux";
              Place_name.label source;
              Db.error_to_string e;
            ];
          match latest () with
          | false -> ()
          | true ->
              (* A failed opt-out stays off for the session: falling back to
                 the stored "on" would send positions the user refused. *)
              let stored = Place_name.enabled !(t.place_stored) source in
              let shown = value && stored in
              show shown;
              t.place_error_source := Some source;
              t.set_place_error (Some (place_error_text source ~shown ~stored)))
      | Ok (_ : int) -> (
          t.place_stored := Place_name.set !(t.place_stored) source value;
          (match (latest (), !(t.place_error_source)) with
          | true, Some s when Place_name.equal_source s source ->
              t.place_error_source := None;
              t.set_place_error None
          | _ -> ());
          (* Points already tried were tried remotely: only a newly enabled
             source that sends the position is a reason to ask them again;
             the offline source is asked for them anyway. *)
          match (value, Place_name.is_online source) with
          | true, true ->
              t.geocode_tried := [];
              geocode_pending t
          | true, false -> geocode_pending t
          | false, _ -> ()))

let save t edits =
  let r = commit t edits in
  Fut.await r (function Ok 0 | Error _ -> () | Ok _ -> geocode_pending t);
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
      (match saved with 0 -> () | _ -> changed t);
      List.rev failed)
    (List.fold_left
       (fun acc s -> Fut.bind acc (fun r -> step r s))
       (Fut.return (0, []))
       shots)

(* References (architecture §6). *)

type link_error = Plant_gone | Store of Db.error

let fetching t = t.fetching

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
    match generation t id = g with
    | true -> Some (commit t edits)
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

let fetch_if_online t id key =
  match online t with true -> start_fetch t id key | false -> ()

let link t ?name id (taxon : Herbier_refs.Sources.Gbif.Taxon.t) =
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
      let+ saved = save t edits in
      match saved with
      | Error e ->
          (* Nothing changed, but the old key's fetch was dropped. *)
          (match was_fetching with true -> refresh t id | false -> ());
          Error (Store e)
      | Ok (_ : int) ->
          (* Offline, the next fiche opening fetches: the plant is due. *)
          fetch_if_online t id taxon.key;
          Ok ())

let create_linked t ?(extra = []) (plant : Herbier_domain.Plant.t)
    (taxon : Herbier_refs.Sources.Gbif.Taxon.t) =
  let open Fut.Syntax in
  let edits =
    Plants.upsert plant
    :: gbif_ref ~plant:plant.id ~at:plant.updated_at taxon
    :: extra
  in
  let+ saved = save t edits in
  match saved with
  | Error e -> Error e
  | Ok (_ : int) ->
      fetch_if_online t plant.id taxon.key;
      Ok ()

(* « IGN hors-ligne » packs (architecture §8). *)

let packs t = t.packs
let downloading t = t.downloading

type pack_error = Busy | Offline | Pack of Commune_packs.error

let pack_error_to_string = function
  | Busy -> "Un téléchargement est déjà en cours."
  | Offline
  | Pack (Commune_packs.Fetch Herbier_geo.Geocoder.(Network _ | Timeout)) ->
      "Hors ligne : réessayez une fois connecté."
  | Pack (Commune_packs.Fetch (Herbier_geo.Geocoder.Refused _)) ->
      "Téléchargement non envoyé. Réessayez."
  | Pack (Commune_packs.Fetch (Herbier_geo.Geocoder.Status _ as e))
    when Herbier_geo.Geocoder.transient e ->
      "Service de l’IGN indisponible : réessayez plus tard."
  | Pack (Commune_packs.Fetch Herbier_geo.Geocoder.(Payload _ | Status _)) ->
      "Réponse de l’IGN inattendue."
  | Pack (Commune_packs.File _ | Commune_packs.Store _) ->
      "Enregistrement impossible."

let departements t =
  match online t with
  | false -> Fut.return (Error Offline)
  | true ->
      Fut.map
        (Result.map_error (fun e -> Pack e))
        (Commune_packs.departements ())

let without_pack code = List.filter (fun p -> not (Code.equal p.code code))

let download_pack t (d : Communes.departement) =
  match React.S.value t.downloading with
  | Some (_ : Communes.departement) -> Fut.return (Error Busy)
  | None ->
      t.set_downloading (Some d);
      Fut.map
        (function
          | Error e ->
              log_error
                [
                  "communes: download";
                  Code.to_string d.code;
                  Commune_packs.error_to_string e;
                ];
              t.set_downloading None;
              Error (Pack e)
          | Ok ((row : Pack_rows.t), pack) ->
              t.communes := Communes.add !(t.communes) pack;
              let packs =
                List.sort
                  (fun a b -> Code.compare a.code b.code)
                  ({code = d.code; row; usable = true}
                  :: without_pack d.code (React.S.value t.packs))
              in
              let step = React.Step.create () in
              t.set_packs ~step packs;
              t.set_downloading ~step None;
              React.Step.execute step;
              log ["communes: downloaded"; Code.to_string d.code];
              (* Downloading a département is choosing this source. *)
              (match
                 (React.S.value (State.place_sources t.state)).ign_offline
               with
              | false -> set_place_source t Place_name.Ign_offline true
              | true -> geocode_pending t);
              Ok ())
        (* Wait for the startup load: it replaces the index and [packs]
           wholesale, so a download finished before it would be lost. *)
        (Fut.bind t.communes_loaded (fun () ->
             Commune_packs.download t.db ~now:(Ptime_clock.now ()) d))

let delete_pack t code =
  match React.S.value t.downloading with
  | Some (d : Communes.departement) when Code.equal d.code code ->
      Fut.return (Error Busy)
  | Some _ | None ->
      Fut.map
        (function
          | Error e ->
              log_error
                [
                  "communes: delete";
                  Code.to_string code;
                  Commune_packs.error_to_string e;
                ];
              Error (Pack e)
          | Ok () ->
              t.communes := Communes.remove !(t.communes) code;
              t.set_packs (without_pack code (React.S.value t.packs));
              Ok ())
        (Commune_packs.delete t.db code)
