module Db = Herbier_store_io.Db
module Observations = Herbier_store.Observations
module Observation_id = Herbier_domain.Ids.Observation_id
module Places = Herbier_domain.Places
module Place_name = Herbier_geo.Place_name
module Geocode_pass = Herbier_ui_model.Geocode_pass

let tried (t : Core.t) (o : Herbier_domain.Observation.t) p =
  List.exists
    (fun (id, q) -> Observation_id.equal id o.id && Places.equal_point q p)
    !(t.geocode_tried)

let mark_tried (t : Core.t) (o : Herbier_domain.Observation.t) p =
  t.geocode_tried := (o.id, p) :: !(t.geocode_tried)

(* The marker is device-only bookkeeping: a failed delete only means the
   observation is resolved again at the next pass, where the guarded rename
   writes nothing. *)
let forget_rename (t : Core.t) (o : Herbier_domain.Observation.t) =
  Fut.await
    (Db.write t.db (Herbier_store.Place_renames.forget o.id))
    (function
      | Ok (_ : int) -> ()
      | Error e ->
          Core.log_error
            [
              "geocode: forget rename";
              Observation_id.to_string o.id;
              Db.error_to_string e;
            ])

let rec geocode_pending (t : Core.t) =
  match !(t.geocode_run) with
  | Geocoding | Geocoding_again -> t.geocode_run := Geocoding_again
  | Idle ->
      t.geocode_run := Geocoding;
      let open Fut.Result_syntax in
      Fut.await
        (let* () = Fut.map Result.ok t.communes_loaded in
         let* observations = Db.all t.db Observations.to_geocode in
         let* to_rename = Db.all t.db Observations.to_rename in
         let+ labelled = Db.all t.db Observations.labelled in
         (observations, to_rename, labelled))
        (function
          | Error e ->
              Core.log_error ["geocode: read"; Db.error_to_string e];
              geocode_end t
          | Ok (observations, to_rename, labelled) ->
              geocode_each t ~labelled
                (Geocode_pass.items ~to_geocode:observations ~to_rename))

and geocode_end (t : Core.t) =
  let again = !(t.geocode_run) in
  t.geocode_run := Idle;
  match again with
  | Geocoding_again -> geocode_pending t
  | Idle | Geocoding -> ()

and geocode_each (t : Core.t) ~labelled = function
  | [] -> geocode_end t
  | item :: _
    when Geocode_pass.yields item
           ~again:(!(t.geocode_run) = Core.Geocoding_again) ->
      (* geocode_end starts the new run, which reads the newly pending
         observations first; renames already done have lost their marker. *)
      geocode_end t
  | {Geocode_pass.o; p; kind} :: rest ->
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
      let online = Core.online t in
      let asked = Place_name.any_online sources && online in
      let allow (r : Herbier_geo.Geocode.request) =
        Place_name.allows
          (React.S.value (State.place_sources t.state))
          r.provider
      in
      Fut.await
        (Herbier_geo_io.Geocoder.run ~allow
           (Place_name.resolve ~sources ~online ~labelled
              ~communes:!(t.communes) p))
        (function
          | Error (Herbier_geo_io.Geocoder.Refused _) ->
              (* Its source was turned off while the request waited: not a
                 miss, so the point is asked again if it comes back on. *)
              Core.log ["geocode:"; id; "refused"];
              geocode_each t ~labelled rest
          | Error e ->
              (* A transient error leaves the observation to the next
                 trigger; any other would fail the same way again. *)
              (match Herbier_geo_io.Geocoder.transient e with
              | true -> ()
              | false -> mark_tried t o p);
              Core.log_error
                ["geocode:"; id; Herbier_geo_io.Geocoder.error_to_string e];
              geocode_end t
          | Ok Place_name.Deferred -> geocode_each t ~labelled rest
          | Ok Place_name.Unknown ->
              (* A rename keeps its old name and its marker: asked again at
                 the next trigger, as an unnamed point is. *)
              (match asked with
              | true ->
                  mark_tried t o p;
                  Core.log ["geocode:"; id; "unknown"]
              | false -> ());
              geocode_each t ~labelled rest
          | Ok (Place_name.Named named) -> (
              let at = Ptime_clock.now () in
              let edit =
                match kind with
                | Geocode_pass.Name ->
                    Observations.set_place_derived o.id ~lat:p.lat ~lon:p.lon
                      ~detail:named.detail named.name ~at
                | Geocode_pass.Rename {was} ->
                    Observations.rename_place_derived o.id ~lat:p.lat ~lon:p.lon
                      ~was ~detail:named.detail named.name ~at
              in
              Fut.await (Core.commit t [edit]) @@ function
              | Error e ->
                  mark_tried t o p;
                  Core.log_error ["geocode: save"; id; Db.error_to_string e];
                  geocode_end t
              | Ok changes ->
                  let next = Geocode_pass.after_save kind ~changes in
                  (match next.mark_tried with
                  | true -> mark_tried t o p
                  | false -> ());
                  Core.log ["geocode:"; id; next.outcome];
                  (match next.forget with
                  | true -> forget_rename t o
                  | false -> ());
                  geocode_each t ~labelled rest))

let settings_key = function
  | Place_name.Ign_offline -> Herbier_store.Settings.Place_source_ign_offline
  | Place_name.Ign_online -> Herbier_store.Settings.Place_source_ign_online
  | Place_name.Photon_online ->
      Herbier_store.Settings.Place_source_photon_online

let place_error (t : Core.t) = t.place_error

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

let set_place_source (t : Core.t) source value =
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
          Core.log_error
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

let save (t : Core.t) edits =
  let r = Core.commit t edits in
  Fut.await r (function Ok 0 | Error _ -> () | Ok _ -> geocode_pending t);
  r
