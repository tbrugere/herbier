open Brr
module Geocode = Herbier_geo.Geocode
module Geocoder = Herbier_geo_io.Geocoder
module Place_name = Herbier_geo.Place_name
module Places = Herbier_domain.Places
module Observation = Herbier_domain.Observation
module Observation_id = Herbier_domain.Ids.Observation_id
module Observations = Herbier_store.Observations
module Db = Herbier_store_io.Db

let schlucht = {Places.lat = 48.0633; lon = 7.0081}
let belfort = {Places.lat = 47.6380; lon = 6.8628}
let figeac = {Places.lat = 44.6020; lon = 2.0300}
let pelegri = {Places.lat = 44.6300; lon = 1.9835}

let points =
  [
    ("schlucht", schlucht);
    ("figeac", figeac);
    ("pelegri", pelegri);
    ("balveurche", {Places.lat = 48.0653; lon = 6.9946});
    ("landes", {Places.lat = 44.25; lon = -0.85});
    ("lausanne", {Places.lat = 46.5197; lon = 6.6323});
    ("kew", {Places.lat = 51.4787; lon = -0.2956});
    ("atlantic", {Places.lat = 46.2; lon = -5.0});
  ]

let now_ms () = Performance.now_ms G.performance

let on_start log t0 r =
  Kit.append log
    (Printf.sprintf "%6.0f ms start %s"
       (now_ms () -. t0)
       (Geocode.request_to_string r))

let outcome = function
  | Ok o -> Place_name.outcome_to_string o
  | Error e -> "error: " ^ Geocoder.error_to_string e

let online_sources =
  {Place_name.ign_offline = false; ign_online = true; photon_online = true}

let run_reverse log =
  let t0 = now_ms () in
  let remaining = ref (List.length points) in
  List.iter
    (fun (name, p) ->
      Fut.await
        (Geocoder.run ~on_start:(on_start log t0)
           (Place_name.resolve ~sources:online_sources ~online:true ~labelled:[]
              ~communes:Herbier_geo.Communes.empty p))
        (fun r ->
          Kit.append log
            (Printf.sprintf "%6.0f ms %s: %s"
               (now_ms () -. t0)
               name (outcome r));
          decr remaining;
          match !remaining with 0 -> Kit.append log "reverse done" | _ -> ()))
    points

let place (p : Geocode.place) =
  Printf.sprintf "%s — %s (%s, %s)" p.name
    (Option.value p.context ~default:"")
    (Geocode.coordinate p.point.lat)
    (Geocode.coordinate p.point.lon)

let requests () = Hooks.geocode_requests ()

(* Place-name sources *)

let status app ~opened =
  let state = App.state app in
  let s = React.S.value (State.place_sources state) in
  let on = function true -> "on" | false -> "off" in
  let packs = React.S.value (App.packs app) in
  let codes = function [] -> "aucun" | l -> String.concat ", " l in
  Printf.sprintf
    "IGN hors-ligne: %s (packs : %s ; illisibles : %s) · IGN en ligne: %s · \
     Photon en ligne: %s · %s · %d requêtes depuis l’ouverture de la page \
     (Inverse et Chercher compris)"
    (on s.ign_offline)
    (codes (List.map (fun (p : App.pack) -> p.row.departement) packs))
    (codes
       (List.filter_map
          (fun (p : App.pack) ->
            match p.usable with true -> None | false -> Some p.row.departement)
          packs))
    (on s.ign_online) (on s.photon_online)
    (match (React.S.value (State.network state)).online with
    | true -> "en ligne"
    | false -> "hors ligne")
    (List.length (requests ()) - opened)

let renames app =
  Fut.map
    (function
      | Ok (Some n) -> Printf.sprintf "%d à renommer (place_renames)" n
      | Ok None -> "place_renames: vide ?"
      | Error e -> "place_renames: " ^ Db.error_to_string e)
    (Db.find (App.db app) Herbier_store.Place_renames.count)

let observation ?label (p : Places.point) : Observation.t =
  let now = Ptime_clock.now () in
  {
    id = Observation_id.fresh ();
    plant_id = None;
    at = now;
    position = Some {lat = p.lat; lon = p.lon; accuracy_m = None};
    place_label = label;
    place_derived = None;
    place_detail = None;
    note = None;
    created_at = now;
    updated_at = now;
    deleted_at = None;
  }

(* Points across metropolitan France and one per overseas département, named
   offline once « Toute la France » has run. *)
let france_points =
  [
    {Places.lat = 48.3904; lon = -4.4861} (* Brest, 29 *);
    {Places.lat = 50.6292; lon = 3.0573} (* Lille, 59 *);
    {Places.lat = 48.5734; lon = 7.7521} (* Strasbourg, 67 *);
    {Places.lat = 48.8566; lon = 2.3522} (* Paris, 75 *);
    {Places.lat = 42.6887; lon = 2.8948} (* Perpignan, 66 *);
    {Places.lat = 41.9192; lon = 8.7386} (* Ajaccio, 2A *);
    {Places.lat = 16.2411; lon = -61.5331} (* Pointe-à-Pitre, 971 *);
    {Places.lat = 14.6161; lon = -61.0588} (* Fort-de-France, 972 *);
    {Places.lat = 4.9224; lon = -52.3135} (* Cayenne, 973 *);
    {Places.lat = -20.8823; lon = 55.4504} (* Saint-Denis, 974 *);
    {Places.lat = -12.7806; lon = 45.2279} (* Mamoudzou, 976 *);
  ]

let poll_seconds = 15

(* Polled rather than bound to [App.saved]: dev pages hand the router no
   bindings, and a timer needs none. *)
let watch app ~out ~before (created : Observation.t list) =
  let derived (o : Observation.t) =
    Fut.map
      (function
        | Ok (Some (r : Observation.t)) ->
            let name =
              Option.value r.place_derived ~default:Places.unknown_name
            in
            Geocode.named_to_string {Geocode.name; detail = r.place_detail}
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
  let renames_line = El.p [] in
  let show_renames () =
    Fut.await (renames app) (fun s -> El.set_children renames_line [El.txt' s])
  in
  show_renames ();
  let refresh = Kit.button "Rafraîchir" in
  Kit.on_click refresh (fun () ->
      El.set_children line [El.txt' (status app ~opened)];
      show_renames ());
  let out = El.div ~at:[At.v (Jstr.v "role") (Jstr.v "status")] [] in
  let single = Kit.button "Observation à la Schlucht" in
  Kit.on_click single (fun () -> save_all app ~out [observation schlucht]);
  let belfort_button = Kit.button "Observation à Belfort" in
  Kit.on_click belfort_button (fun () ->
      save_all app ~out [observation belfort]);
  let figeac_button = Kit.button "Observation à Figeac" in
  Kit.on_click figeac_button (fun () -> save_all app ~out [observation figeac]);
  let pelegri_button = Kit.button "Observation à Pélégri" in
  Kit.on_click pelegri_button (fun () ->
      save_all app ~out [observation pelegri]);
  let pair = Kit.button "Lieu nommé + voisine" in
  Kit.on_click pair (fun () ->
      save_all app ~out
        [
          observation ~label:"Lieu test" {lat = 44.25; lon = -0.85};
          observation {lat = 44.2518; lon = -0.85};
        ]);
  let france = Kit.button "Observations dans toute la France" in
  Kit.on_click france (fun () ->
      save_all app ~out (List.map (fun p -> observation p) france_points));
  [
    El.h2 [El.txt' "Noms de lieux"];
    line;
    renames_line;
    El.p
      [
        refresh;
        single;
        belfort_button;
        figeac_button;
        pelegri_button;
        pair;
        france;
      ];
    out;
  ]

let el app =
  let log = El.div ~at:[At.v (Jstr.v "role") (Jstr.v "log")] [] in
  let reverse_button = Kit.button "Inverse" in
  Kit.on_click reverse_button (fun () -> run_reverse log);
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
  let search_button = Kit.button "Chercher" in
  let results = El.ul [] in
  Kit.on_click search_button (fun () ->
      let q = Jstr.to_string (El.prop El.Prop.value input) in
      let t0 = now_ms () in
      El.set_children results [];
      Fut.await
        (Geocoder.search ~on_start:(on_start log t0) ~near:schlucht q)
        (function
          | Error e -> Kit.append log ("search: " ^ Geocoder.error_to_string e)
          | Ok places ->
              Kit.append log
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
