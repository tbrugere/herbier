module Map_sheet = Herbier_ui_model.Map_sheet
module Move_plan = Herbier_ui_model.Move_plan
open Brr
module Db = Herbier_store_io.Db
module Observations = Herbier_store.Observations
module Observation = Herbier_domain.Observation
module Places = Herbier_domain.Places
module Geocode = Herbier_geo.Geocode
module Geocoder = Herbier_geo_io.Geocoder
module Geo_map = Herbier_geo_io.Map
module W = Widgets

let cls = Html.cls
let log_error = Log.error ~scope:"déplacer"
let hint = "Glissez la carte sous le point"
let gone_text = "Cette observation n'est plus dans l'herbier."
let save_failed = "La position n'a pas pu être enregistrée."
let zoom_in = "Zoomez pour placer le point précisément."

(* style: the MapLibre handle (style guide 2.2): created asynchronously, and
   the screen may be left before it exists. *)
(* What « Chercher un lieu » shows under its field. *)
type search =
  | Idle
  | Searching
  | Search_disabled
  | Offline
  | Search_failed
  | Network_failed
  | Nothing_found
  | Found of Geocode.place list

let enter = Html.enter

let round_button ~label icon =
  let el = W.Icon_button.el ~classes:["move-point__round"] ~label icon in
  let click, b = Rb.click el in
  (el, click, b)

let search_line text = (El.p ~at:[cls "t-meta"] [El.txt' text], [])

let result_row pick (p : Geocode.place) =
  let el =
    Html.button ["move-point__result"]
      (El.span ~at:[cls "move-point__result-name"] [El.txt' p.name]
      :: Option.to_list
           (Option.map
              (fun c -> El.span ~at:[cls "t-meta"] [El.txt' c])
              p.context))
  in
  let click, b = Rb.click el in
  (el, [b; Rb.act click (fun () -> pick p)])

let search_view pick = function
  | Idle -> (El.div [], [])
  | Searching -> search_line "Recherche…"
  | Search_disabled ->
      search_line
        "Activez « Photon en ligne » dans Réglages pour chercher un lieu."
  | Offline -> search_line "Hors ligne : la recherche attend le réseau."
  | Search_failed -> search_line "Recherche impossible"
  | Network_failed -> search_line "Réseau indisponible, réessayez."
  | Nothing_found -> search_line "Aucun lieu trouvé"
  | Found places ->
      let rows = List.map (result_row pick) places in
      ( El.div ~at:[cls "move-point__results"] (List.map fst rows),
        List.concat_map snd rows )

(* A fixed pin whose foot is the map's centre: the map slides under it. *)
let pin () =
  El.div
    ~at:[cls "move-point__pin"; At.v (Jstr.v "aria-hidden") (Jstr.v "true")]
    [
      El.span ~at:[cls "move-point__halo"] [];
      El.span ~at:[cls "move-point__stem"] [];
      El.span ~at:[cls "move-point__head"] [];
    ]

let render app (o : Observation.t) =
  let db = App.db app and state = App.state app in
  let id = o.id in
  let origin = Places.position_point o and origin_name = Places.place_name o in
  let entry =
    match origin with
    | Some center -> {State.center; zoom = Move_plan.initial_zoom}
    | None ->
        Option.value (React.S.value (State.map_view state)).camera
          ~default:Locate.world
  in
  let camera, set_camera = React.S.create ~eq:State.equal_camera entry in
  let picked, set_picked =
    React.S.create
      ~eq:
        (Option.equal (fun (a, p) (b, q) ->
             String.equal a b && Places.equal_point p q))
      None
  in
  let ready, set_ready = React.S.create ~eq:Bool.equal false in
  let moving, set_moving = React.S.create ~eq:Bool.equal false in
  let saving, set_saving = React.S.create ~eq:Bool.equal false in
  let pill, set_pill = React.S.create ~eq:String.equal hint in
  let message, set_message =
    React.S.create
      ~eq:(Option.equal String.equal)
      (match App.theme app with
      | Ok _ -> None
      | Error (Theme.Missing_tokens missing) ->
          Some (Map_sheet.broken_text (Map_sheet.Missing_tokens missing)))
  in
  let search, set_search = React.S.create ~eq:( == ) Idle in
  (* style: state read and written from future callbacks, MapLibre callbacks
     and [Rb.act] handlers only (outside update steps). [moved]: the user
     moved the camera since entry (a gesture, a search result, « Point
     d'origine » or « Ma position »; not a resize nor the entry fix), so a
     late entry fix no longer takes it over;
     [pending_fix]: a fix that arrived before the map existed; [search_seq]
     numbers the latest query, a reply to an older one is dropped. *)
  let map = ref Map_slot.Creating
  and moved = ref false
  and pending_fix = ref None
  and search_seq = ref 0 in
  let alive () = Map_slot.alive !map in
  let fly ?(zoom = Move_plan.initial_zoom) point =
    match !map with
    | Map_slot.Ready m -> Geo_map.fly_to m ~center:point ~zoom
    | Map_slot.(Creating | Failed | Released) -> ()
  in
  let field =
    W.Text_field.v ~icon:W.Icon.Search ~action:"OK"
      ~placeholder:"Chercher un lieu" ()
  in
  let pick (p : Geocode.place) =
    moved := true;
    El.set_has_focus false field.input;
    set_search Idle;
    set_picked (Some (p.name, p.point));
    fly ~zoom:Move_plan.search_zoom p.point
  in
  let run_search () =
    let text = React.S.value field.value in
    incr search_seq;
    let mine = !search_seq in
    (* The query and the map centre go to Photon: only with its source on. *)
    match
      ( String.trim text,
        Herbier_geo.Place_name.can_search
          (React.S.value (State.place_sources state)),
        (React.S.value (State.network state)).online )
    with
    | "", _, _ -> set_search Idle
    | _, false, _ -> set_search Search_disabled
    | _, true, false -> set_search Offline
    | _, true, true ->
        set_search Searching;
        let allow (_ : Geocode.request) =
          Herbier_geo.Place_name.can_search
            (React.S.value (State.place_sources state))
        in
        Fut.await
          (Geocoder.search ~allow ~near:(React.S.value camera).center text)
          (fun reply ->
            (match reply with
            | Error e -> log_error "recherche" (Geocoder.error_to_string e)
            | Ok (_ : Geocode.place list) -> ());
            match (alive () && mine = !search_seq, reply) with
            | false, _ -> ()
            | true, Error (Geocoder.Refused _) -> set_search Search_disabled
            | true, Error e when Geocoder.transient e ->
                set_search Network_failed
            | true, Error _ -> set_search Search_failed
            | true, Ok [] -> set_search Nothing_found
            | true, Ok places -> set_search (Found places))
  in
  let locate () =
    moved := true;
    Fut.await (Locate.current ~what:"déplacer: position") (function
      | _ when not (alive ()) -> ()
      | Error notice -> set_pill (Map_sheet.notice_text notice)
      | Ok fix -> (
          set_pill hint;
          match !map with
          | Map_slot.Ready m ->
              fly
                ~zoom:
                  (Float.max Move_plan.initial_zoom
                     (Option.value (Geo_map.zoom m) ~default:0.))
                fix
          | Map_slot.Creating -> pending_fix := Some fix
          | Map_slot.(Failed | Released) -> ()))
  in
  (* Without origin, the device's fix is a better start than the last 4b
     camera, but only until the user moves the map. *)
  let locate_on_entry () =
    Fut.await (Locate.current ~what:"déplacer: position (entrée)") (function
      | _ when not (alive ()) -> ()
      | Error (_ : Map_sheet.notice) -> ()
      | Ok fix -> (
          match (!map, !moved) with
          | Map_slot.Ready _, false -> fly fix
          | Map_slot.Creating, false -> pending_fix := Some fix
          | Map_slot.(Ready _ | Creating | Failed | Released), _ -> ()))
  in
  let on_movestart ~user =
    (match user with true -> moved := true | false -> ());
    set_moving true
  in
  let on_moveend ~center ~zoom =
    set_moving false;
    set_camera {center; zoom}
  in
  let container = El.div ~at:[cls "move-point__map"] [] in
  (match App.theme app with
  | Error (Theme.Missing_tokens missing) ->
      map := Map_slot.Failed;
      log_error "thème" (String.concat ", " missing)
  | Ok theme ->
      Fut.await
        (Geo_map.create container ~colours:theme.map ~center:entry.center
           ~zoom:entry.zoom ~interactive:true) (function
        | Ok m when not (alive ()) -> Geo_map.remove m
        | Error _ when not (alive ()) -> ()
        | Error e ->
            map := Map_slot.Failed;
            log_error "création" (Geo_map.error_to_string e);
            set_message (Some (Map_sheet.broken_text Map_sheet.Map_unavailable))
        | Ok m ->
            map := Map_slot.Ready m;
            Geo_map.set_origin m origin;
            Geo_map.on_movestart m on_movestart;
            Geo_map.on_moveend m on_moveend;
            set_ready true;
            Option.iter fly !pending_fix;
            pending_fix := None));
  (match origin with Some _ -> () | None -> locate_on_entry ());
  (* The point saved is the camera the drawer shows, the centre at the last
     [moveend]; « Valider » is disabled while the map moves. *)
  let validate () =
    let c = React.S.value camera in
    match
      ( !map,
        React.S.value saving,
        React.S.value moving,
        Move_plan.can_validate ~zoom:c.zoom )
    with
    | Map_slot.Ready _, false, false, true ->
        let centre = c.center in
        set_saving true;
        set_message None;
        let fail text =
          set_saving false;
          set_message (Some text)
        in
        Fut.await
          (Db.find db (Observations.get id))
          (fun found ->
            (match found with
            | Error e -> log_error "lecture" (Db.error_to_string e)
            | Ok (_ : Observation.t option) -> ());
            match (alive (), found) with
            | false, _ -> ()
            | true, Error _ -> fail save_failed
            | true, Ok None -> fail gone_text
            | true, Ok (Some fresh) -> (
                match Move_plan.apply fresh centre ~at:(Ptime_clock.now ()) with
                | None -> Route.back ()
                | Some next ->
                    Fut.await
                      (App.save app [Observations.upsert next])
                      (fun result ->
                        (match result with
                        | Error e ->
                            log_error "enregistrer" (Db.error_to_string e)
                        | Ok (_ : int) -> ());
                        match (alive (), result) with
                        | false, _ -> ()
                        | true, Error _ -> fail save_failed
                        | true, Ok _ -> Route.back ())))
    | Map_slot.(Ready _ | Creating | Failed | Released), _, _, _ -> ()
  in
  let close, close_click, b_close = round_button ~label:"Fermer" W.Icon.Close in
  let locate_el, locate_click, b_locate =
    round_button ~label:"Ma position" W.Icon.My_location
  in
  let status = At.v (Jstr.v "role") (Jstr.v "status") in
  let pill_el = El.p ~at:[cls "move-point__pill"; status] [] in
  let title_el = El.h2 ~at:[cls "move-point__title"] [] in
  let meta_el = El.p ~at:[cls "t-meta"; cls "move-point__meta"] [] in
  let results_el = El.div [] in
  (* Always in the document, empty when there is nothing to say: a live
     region that appears with its text is not reliably announced. *)
  let message_el =
    El.p ~at:[cls "t-meta"; cls "move-point__message"; status] []
  in
  let back_to_origin =
    Option.map
      (fun o -> (o, W.Button.v ~kind:W.Button.Secondary "Point d'origine"))
      origin
  in
  let valider = W.Button.v "Valider" in
  let zoomed_in =
    React.S.map ~eq:Bool.equal
      (fun (c : State.camera) -> Move_plan.can_validate ~zoom:c.zoom)
      camera
  in
  let can_validate =
    React.S.l4 ~eq:Bool.equal
      (fun ready saving moving zoomed_in ->
        ready && (not saving) && (not moving) && zoomed_in)
      ready saving moving zoomed_in
  in
  (* A failure first; else why « Valider » is greyed at this zoom. *)
  let message_text =
    React.S.l3 ~eq:String.equal
      (fun message ready zoomed_in ->
        match (message, ready && not zoomed_in) with
        | Some text, _ -> text
        | None, true -> zoom_in
        | None, false -> "")
      message ready zoomed_in
  in
  let drawer =
    El.div
      ~at:[cls "move-point__drawer"]
      [
        title_el;
        meta_el;
        field.el;
        results_el;
        message_el;
        El.div
          ~at:[cls "move-point__buttons"]
          (List.concat
             [
               Option.to_list
                 (Option.map (fun (_, b) -> b.W.Button.el) back_to_origin);
               [valider.el];
             ]);
      ]
  in
  let el =
    El.div
      ~at:[cls "move-point__content"]
      [
        El.div
          ~at:[cls "move-point__stage"]
          [
            container;
            pin ();
            El.div ~at:[cls "move-point__top"] [close; pill_el; locate_el];
          ];
        drawer;
      ]
  in
  let release_map = Rb.on_release (fun () -> Map_slot.release map) in
  ( el,
    List.concat
      [
        [
          release_map;
          b_close;
          b_locate;
          Rb.act close_click Route.back;
          Rb.act locate_click locate;
          Rb.text pill_el pill;
          Rb.text title_el
            (React.S.l2 ~eq:String.equal
               (fun (c : State.camera) picked ->
                 Move_plan.title ~origin ~origin_name ~picked c.center)
               camera picked);
          Rb.text meta_el
            (React.S.map ~eq:String.equal
               (fun (c : State.camera) -> Move_plan.meta ~origin c.center)
               camera);
          Rb.view results_el (search_view pick) search;
          Rb.act field.action run_search;
          Rb.listen field.input Ev.keydown (fun ev ->
              match enter ev with true -> run_search () | false -> ());
          Rb.text message_el message_text;
          Rb.class_ message_el "is-error"
            (React.S.map ~eq:Bool.equal Option.is_some message);
          Rb.attr valider.el "disabled"
            (React.S.map
               (function true -> None | false -> Some "")
               can_validate);
          Rb.act valider.click validate;
        ];
        (match back_to_origin with
        | None -> []
        | Some (o, b) ->
            Rb.act b.click (fun () ->
                moved := true;
                set_picked None;
                fly o)
            :: b.bindings);
        field.bindings;
        valider.bindings;
      ] )

(* The full-screen box has no padding of its own: a notice gets the
   screen's. *)
let notice text =
  let el, bindings = Loaded.notice text in
  El.set_class (Jstr.v "screen") true el;
  (el, bindings)

let v app id =
  let el = El.div ~at:[cls "move-point"] [] in
  let item = function None -> notice gone_text | Some o -> render app o in
  {
    Screen.el;
    ready = Screen.now;
    bindings =
      Loaded.v ~what:"déplacer"
        ~failed:(fun () -> notice "L'observation n'a pas pu être lue.")
        el
        (fun () -> Db.find (App.db app) (Observations.get id))
        item;
  }
