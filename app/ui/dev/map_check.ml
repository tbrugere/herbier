open Brr
module Db = Herbier_store.Db
module Observations = Herbier_store.Observations
module Observation = Herbier_domain.Observation
module Observation_id = Herbier_domain.Ids.Observation_id
module Places = Herbier_domain.Places
module Geo_map = Herbier_geo.Map
module Features = Herbier_geo.Features
module Dev_hook = Herbier_bindings.Dev_hook

let append log text = El.append_children log [El.div [El.txt' text]]

let button label f =
  let b = El.button [El.txt' label] in
  ignore (Ev.listen Ev.click (fun _ -> f ()) (El.as_target b));
  b

let poll_ms = 20
let attach_timeout_ms = 2000
let padding_px = 48

(* MapLibre sizes its canvas from the container when it is created, so wait
   for the router to put the page in the document. *)
let rec attached ~ms el =
  let open Fut.Syntax in
  match (Jv.to_bool (Jv.get (El.to_jv el) "isConnected"), ms <= 0) with
  | true, _ -> Fut.return true
  | false, true -> Fut.return false
  | false, false ->
      let* () = Fut.tick ~ms:poll_ms in
      attached ~ms:(ms - poll_ms) el

let coords ({lat; lon} : Places.point) = Printf.sprintf "%.5f,%.5f" lat lon

let status_text ~total ~placeable ~rendered =
  Printf.sprintf "observations: %d · placées: %d · rendues: %d" total placeable
    rendered

(* The observation's point and, when known, its accuracy radius. *)
let placed_accuracy observations id =
  let ( let* ) = Option.bind in
  let* (o : Observation.t) =
    List.find_opt
      (fun (o : Observation.t) -> Observation_id.equal o.id id)
      observations
  in
  Places.position_point o
  |> Option.map (fun p ->
      ( p,
        Option.bind o.position (fun (q : Observation.position) -> q.accuracy_m)
      ))

let show log status container colours observations =
  let open Fut.Syntax in
  let+ created =
    Geo_map.create container ~colours ~center:{lat = 0.; lon = 0.} ~zoom:1.
      ~interactive:true
  in
  match created with
  | Error e ->
      append log ("erreur: " ^ Geo_map.error_to_string e);
      None
  | Ok m ->
      let total = List.length observations
      and placeable =
        List.length (List.filter_map Places.position_point observations)
      in
      let refresh () =
        El.set_children status
          [
            El.txt'
              (status_text ~total ~placeable
                 ~rendered:(List.length (Geo_map.rendered m)));
          ]
      in
      let fit () =
        match Features.bounds observations with
        | Some b -> Geo_map.fit m b ~padding_px
        | None -> append log "rien à cadrer"
      in
      (* Subscribed before fit: without animation (reduced motion) its
         moveend fires synchronously. *)
      Geo_map.on_moveend m (fun ~center:_ ~zoom:_ -> refresh ());
      Geo_map.on_idle m refresh;
      Geo_map.set_observations m observations;
      fit ();
      refresh ();
      Geo_map.on_error m (fun message -> append log ("erreur: " ^ message));
      Geo_map.on_click m (fun {at; observations = ids} ->
          append log
            (Printf.sprintf "clic %s → %s" (coords at)
               (String.concat ", " (List.map Observation_id.to_string ids)));
          match ids with
          | [] -> ()
          | id :: _ -> (
              match placed_accuracy observations id with
              | Some (p, radius_m) ->
                  Geo_map.set_accuracy m (Option.map (fun r -> (p, r)) radius_m);
                  Geo_map.fly_to m ~center:p ~zoom:16.
              | None -> Geo_map.set_accuracy m None));
      append log "carte prête";
      Some (m, fit)

let el db =
  let status = El.p [El.txt' "chargement…"] in
  let log = El.div [] in
  let container =
    El.div ~at:[At.style (Jstr.v "height: 70vh; position: relative")] []
  in
  (* style: the map handle lives in a ref because the dev hook and the
     buttons are set up before the map exists. *)
  let current = ref None in
  Dev_hook.export_int "mapRendered" (fun () ->
      match !current with
      | Some (m, _) -> List.length (Geo_map.rendered m)
      | None -> 0);
  let fit_button =
    button "Ajuster" (fun () ->
        match !current with Some (_, fit) -> fit () | None -> ())
  and centre_button =
    button "Centre" (fun () ->
        match !current with
        | Some (m, _) -> (
            match (Geo_map.center m, Geo_map.zoom m) with
            | Some c, Some z ->
                append log (Printf.sprintf "centre %s · zoom %.2f" (coords c) z)
            | Some _, None | None, (Some _ | None) ->
                append log "erreur: caméra illisible")
        | None -> append log "pas de carte")
  in
  let start =
    let open Fut.Syntax in
    let* attached = attached ~ms:attach_timeout_ms container in
    match (attached, db, Theme.load ()) with
    | false, _, _ ->
        Fut.return (append log "erreur: la page n'est pas dans le document")
    | true, Error e, _ -> Fut.return (append log ("erreur: base: " ^ e))
    | true, Ok _, Error (Theme.Missing_tokens missing) ->
        Fut.return
          (append log ("erreur: jetons absents: " ^ String.concat ", " missing))
    | true, Ok db, Ok theme -> (
        let* observations = Db.all db Observations.list in
        match observations with
        | Error e -> Fut.return (append log ("erreur: " ^ Db.error_to_string e))
        | Ok observations ->
            let+ shown = show log status container theme.map observations in
            current := shown)
  in
  Fut.await start Fun.id;
  El.div
    [
      El.h1 [El.txt' "Map check"];
      status;
      container;
      El.p [fit_button; El.txt' " "; centre_button];
      log;
    ]
