open Brr
module Geocode = Herbier_geo.Geocode
module Geocoder = Herbier_geo.Geocoder
module Place_name = Herbier_geo.Place_name
module Places = Herbier_domain.Places
module Observation = Herbier_domain.Observation
module Observation_id = Herbier_domain.Ids.Observation_id
module Observations = Herbier_store.Observations
module Db = Herbier_store.Db

let append log text = El.append_children log [El.div [El.txt' text]]
let schlucht = {Places.lat = 48.0633; lon = 7.0081}

let points =
  [
    ("schlucht", schlucht);
    ("landes", {Places.lat = 44.25; lon = -0.85});
    ("lausanne", {Places.lat = 46.5197; lon = 6.6323});
    ("kew", {Places.lat = 51.4787; lon = -0.2956});
    ("atlantic", {Places.lat = 46.2; lon = -5.0});
  ]

let now_ms () = Performance.now_ms G.performance

let on_start log t0 r =
  append log
    (Printf.sprintf "%6.0f ms start %s"
       (now_ms () -. t0)
       (Geocode.request_to_string r))

let outcome = function
  | Ok o -> Place_name.outcome_to_string o
  | Error e -> "error: " ^ Geocoder.error_to_string e

let all_on = {Place_name.ign_online = true; photon_online = true}

let run_reverse log =
  let t0 = now_ms () in
  let remaining = ref (List.length points) in
  List.iter
    (fun (name, p) ->
      Fut.await
        (Geocoder.run ~on_start:(on_start log t0)
           (Place_name.resolve ~sources:all_on ~online:true ~labelled:[] p))
        (fun r ->
          append log
            (Printf.sprintf "%6.0f ms %s: %s"
               (now_ms () -. t0)
               name (outcome r));
          decr remaining;
          match !remaining with 0 -> append log "reverse done" | _ -> ()))
    points

let place (p : Geocode.place) =
  Printf.sprintf "%s — %s (%s, %s)" p.name
    (Option.value p.context ~default:"")
    (Geocode.coordinate p.point.lat)
    (Geocode.coordinate p.point.lon)

let button label = El.button ~at:[At.type' (Jstr.v "button")] [El.txt' label]

let on_click el f =
  ignore (Ev.listen Ev.click (fun _ -> f ()) (El.as_target el) : Ev.listener)

let requests () = Hooks.geocode_requests ()

(* Place-name sources *)

let status app ~opened =
  let state = App.state app in
  let s = React.S.value (State.place_sources state) in
  let on = function true -> "on" | false -> "off" in
  Printf.sprintf
    "IGN en ligne: %s · Photon en ligne: %s · %s · %d requêtes depuis \
     l’ouverture de la page (Inverse et Chercher compris)"
    (on s.ign_online) (on s.photon_online)
    (match (React.S.value (State.network state)).online with
    | true -> "en ligne"
    | false -> "hors ligne")
    (List.length (requests ()) - opened)

let observation ?label (p : Places.point) : Observation.t =
  let now = Ptime_clock.now () in
  {
    id = Observation_id.fresh ();
    plant_id = None;
    at = now;
    position = Some {lat = p.lat; lon = p.lon; accuracy_m = None};
    place_label = label;
    place_derived = None;
    note = None;
    created_at = now;
    updated_at = now;
    deleted_at = None;
  }

let poll_seconds = 15

(* Polled rather than bound to [App.saved]: dev pages hand the router no
   bindings, and a timer needs none. *)
let watch app ~out ~before (created : Observation.t list) =
  let derived (o : Observation.t) =
    Fut.map
      (function
        | Ok (Some (r : Observation.t)) ->
            Option.value r.place_derived ~default:Places.unknown_name
        | Ok None -> "absent"
        | Error e -> "error: " ^ Db.error_to_string e)
      (Db.find (App.db app) (Observations.get o.id))
  in
  let rec tick n =
    Fut.await
      (List.fold_left
         (fun acc (o : Observation.t) ->
           Fut.bind acc (fun lines ->
               Fut.map
                 (fun d -> (Observation_id.to_string o.id ^ ": " ^ d) :: lines)
                 (derived o)))
         (Fut.return []) created)
      (fun lines ->
        let since = List.drop before (requests ()) in
        El.set_children out
          (List.map
             (fun l -> El.div [El.txt' l])
             (List.rev lines
             @ [
                 Printf.sprintf "requêtes depuis le geste: %d"
                   (List.length since);
               ]
             @ List.map Geocode.request_to_string since));
        match n < poll_seconds with
        | true ->
            let _timer : G.timer_id =
              G.set_timeout ~ms:1000 (fun () -> tick (n + 1))
            in
            ()
        | false -> ())
  in
  tick 0

let save_all app ~out observations =
  let before = List.length (requests ()) in
  let rec go = function
    | [] -> watch app ~out ~before observations
    | o :: rest ->
        Fut.await
          (App.save app [Observations.upsert o])
          (function
            | Error e ->
                El.set_children out
                  [El.div [El.txt' ("save: " ^ Db.error_to_string e)]]
            | Ok (_ : int) -> go rest)
  in
  go observations

let place_names app =
  let opened = List.length (requests ()) in
  let line = El.p [El.txt' (status app ~opened)] in
  let refresh = button "Rafraîchir" in
  on_click refresh (fun () ->
      El.set_children line [El.txt' (status app ~opened)]);
  let out = El.div ~at:[At.v (Jstr.v "role") (Jstr.v "status")] [] in
  let single = button "Observation à la Schlucht" in
  on_click single (fun () -> save_all app ~out [observation schlucht]);
  let pair = button "Lieu nommé + voisine" in
  on_click pair (fun () ->
      save_all app ~out
        [
          observation ~label:"Lieu test" {lat = 44.25; lon = -0.85};
          observation {lat = 44.2518; lon = -0.85};
        ]);
  [El.h2 [El.txt' "Noms de lieux"]; line; El.p [refresh; single; pair]; out]

let el app =
  let log = El.div ~at:[At.v (Jstr.v "role") (Jstr.v "log")] [] in
  let reverse_button = button "Inverse" in
  on_click reverse_button (fun () -> run_reverse log);
  let input =
    El.input
      ~at:
        [
          At.type' (Jstr.v "text");
          At.v (Jstr.v "aria-label") (Jstr.v "Lieu");
          At.v (Jstr.v "placeholder") (Jstr.v "Lieu");
        ]
      ()
  in
  let search_button = button "Chercher" in
  let results = El.ul [] in
  on_click search_button (fun () ->
      let q = Jstr.to_string (El.prop El.Prop.value input) in
      let t0 = now_ms () in
      El.set_children results [];
      Fut.await
        (Geocoder.search ~on_start:(on_start log t0) ~near:schlucht q)
        (function
          | Error e -> append log ("search: " ^ Geocoder.error_to_string e)
          | Ok places ->
              append log
                (Printf.sprintf "search: %d places" (List.length places));
              El.set_children results
                (List.map (fun p -> El.li [El.txt' (place p)]) places)));
  El.div
    ([
       El.h1 [El.txt' "Geocode check"];
       El.p [reverse_button];
       El.p [input; search_button];
       results;
       log;
     ]
    @
    match app with
    | Ok app -> place_names app
    | Error e -> [El.p [El.txt' ("no app: " ^ e)]])
