module Collection_filter = Herbier_ui_model.Collection_filter
module Journal_day = Herbier_ui_model.Journal_day
module Journal_filter = Herbier_ui_model.Journal_filter
module Map_filter = Herbier_ui_model.Map_filter
module Map_sheet = Herbier_ui_model.Map_sheet
open Brr
module Db = Herbier_store_io.Db
module Plants = Herbier_store.Plants
module Tags = Herbier_store.Tags
module Search = Herbier_store.Search
module Observations = Herbier_store.Observations
module Photos = Herbier_store.Photos
module Observation = Herbier_domain.Observation
module Photo = Herbier_domain.Photo
module Plant = Herbier_domain.Plant
module Tag = Herbier_domain.Tag
module Fold = Herbier_domain.Fold
module Places = Herbier_domain.Places
module Plant_id = Herbier_domain.Ids.Plant_id
module Observation_id = Herbier_domain.Ids.Observation_id
module Features = Herbier_geo.Features
module Geo_map = Herbier_geo_io.Map
module RList = ReactiveData.RList
module W = Widgets

let cls = Html.cls
let year_of (o : Observation.t) = Zone.year o.at
let padding_px = 64

(* What the screen is built from, loaded on entry and after each save. *)
type data = {
  observations : Observation.t list;
  names : (Plant_id.t * string) list;
  tags : Tag.t list;
  links : Tag.Plant_tag.t list;
  photos : Observation_id.t -> Photo.t list;
}

let no_data =
  {observations = []; names = []; tags = []; links = []; photos = (fun _ -> [])}

(* What the sheet shows: rebuilt after each data, filter, search or selection
   change. *)
type view = {
  data : data;
  places : Features.place list;
  selected : Features.place option;
  notice : Map_sheet.notice option;
      (** replaces the collapsed line, or shows under a place's summary, until
          the next selection, filter or data change *)
  broken : Map_sheet.broken option;  (** why there is no map: for good *)
}

(* The sheet's first line. [Renaming] holds the texts the field opened with:
   two [Renaming] are equal, so the open field, its draft and its focus
   survive every view change until it closes. *)
type head =
  | Line of string
  | Title of string
  | Renaming of {value : string; placeholder : string}

let head_equal a b =
  match (a, b) with
  | Line a, Line b | Title a, Title b -> String.equal a b
  | Renaming _, Renaming _ -> true
  | (Line _ | Title _ | Renaming _), _ -> false

(* The floating search: [seq] numbers the latest query, a reply to an older
   one is dropped; [frame_on_reply]: Enter was pressed while it ran. *)
type search = Idle of int | Running of {seq : int; frame_on_reply : bool}

let search_seq = function Idle seq | Running {seq; frame_on_reply = _} -> seq

(* style: the MapLibre handle (style guide 2.2): created asynchronously, and
   the screen may be left before it exists. *)
let log_error = Log.error ~scope:"carte"

let row ~this_year data (o : Observation.t) =
  let photos = data.photos o.id in
  let thumb =
    match photos with
    | (p : Photo.t) :: _ -> W.List_row.Preview p.preview_path
    | [] -> W.List_row.Placeholder
  in
  let meta =
    Map_sheet.row_meta ~this_year ~date:(Zone.date o.at)
      ~photos:(List.length photos)
  in
  let r, target =
    match o.plant_id with
    | Some id ->
        ( W.List_row.v ~thumb
            ~title:(Journal_day.plant_name data.names id)
            ~meta (),
          Route.Observation o.id )
    | None ->
        ( W.List_row.v ~thumb ~tone:W.List_row.To_identify ~title:"À identifier"
            ~meta (),
          Route.Identify o.id )
  in
  (r.el, Rb.act r.click (fun () -> Route.go (Route.Modal target)) :: r.bindings)

let rows (data, selected) =
  match selected with
  | None -> (El.div [], [])
  | Some (p : Features.place) ->
      let this_year = Zone.this_year () in
      let rows = List.rev_map (row ~this_year data) p.shown in
      ( El.div ~at:[cls "map-tab__rows"] (List.map fst rows),
        List.concat_map snd rows )

(* The rows show the place's shown members: a recompute that keeps them keeps
   the rows (and their thumbnails) as they are. *)
let same_rows (d, s) (d', s') =
  d == d'
  && Option.equal
       (fun (a : Features.place) (b : Features.place) ->
         Observation_id.equal a.key b.key
         && List.equal
              (fun (x : Observation.t) (y : Observation.t) ->
                Observation_id.equal x.id y.id)
              a.shown b.shown)
       s s'

let enter = Html.enter

let shown_members places =
  List.concat_map (fun (p : Features.place) -> p.shown) places

let load db =
  let open Fut.Result_syntax in
  (* Thumbnails are decoration: a failed photo read leaves the rows without
     them, not the map empty. *)
  let photos =
    Fut.map
      (function
        | Ok l -> l
        | Error e ->
            log_error "photos" (Db.error_to_string e);
            [])
      (Db.all db Photos.live)
  in
  let* observations = Db.all db Observations.list in
  let* plants = Db.all db Plants.list in
  let* tags = Db.all db Tags.list in
  let* links = Db.all db Tags.links in
  let+ photos = Fut.map Result.ok photos in
  {
    observations;
    names = List.map (fun (p : Plant.t) -> (p.id, p.display_name)) plants;
    tags;
    links;
    photos = Map_sheet.photos_by_observation photos;
  }

let head (v, renaming) =
  match (v.selected, renaming) with
  | None, _ ->
      Line
        (match (v.broken, v.notice) with
        | Some b, _ -> Map_sheet.broken_text b
        | None, Some n -> Map_sheet.notice_text n
        | None, None ->
            Map_sheet.collapsed ~places:(List.length v.places)
              ~observations:(List.length (shown_members v.places)))
  | Some p, false -> Title (Map_sheet.title p.cluster)
  | Some p, true ->
      Renaming
        {
          value = Map_sheet.rename_value p.cluster;
          placeholder = Map_sheet.title p.cluster;
        }

let summary v =
  Option.map (fun (p : Features.place) -> Map_sheet.summary p.shown) v.selected

(* Under a place's summary: what went wrong last (with no place, the
   collapsed line says it). *)
let message (v, rename_failed) =
  match (v.selected, rename_failed, v.broken, v.notice) with
  | None, _, _, _ -> None
  | Some _, true, _, _ -> Some "Enregistrement impossible. Réessayez."
  | Some _, false, Some b, _ -> Some (Map_sheet.broken_text b)
  | Some _, false, None, Some n -> Some (Map_sheet.notice_text n)
  | Some _, false, None, None -> None

let optional_p class_name = function
  | None -> (El.txt' "", [])
  | Some s -> (El.p ~at:[cls class_name] [El.txt' s], [])

let v app =
  let db = App.db app and state = App.state app in
  let filters = State.filters state in
  let restored = React.S.value (State.map_view state) in
  let theme = App.theme app in
  let view, set_view =
    React.S.create ~eq:( == )
      {
        data = no_data;
        places = [];
        selected = None;
        notice = Some Map_sheet.Loading;
        broken =
          (match theme with
          | Ok _ -> None
          | Error (Theme.Missing_tokens missing) ->
              Some (Map_sheet.Missing_tokens missing));
      }
  in
  let renaming, set_renaming = React.S.create false in
  let rename_failed, set_rename_failed = React.S.create false in
  let stop_renaming ?step () =
    set_renaming ?step false;
    set_rename_failed ?step false
  in
  let chips, chips_handle = RList.create [] in
  let search =
    W.Text_field.v ~icon:W.Icon.Search
      ~placeholder:"Chercher un lieu, une plante…" ()
  in
  (* style: state read and written from future callbacks, MapLibre callbacks
     and [Rb.act] handlers only (outside update steps). [query] is the
     search's last applied result; [needs_fit]: first entry with no framing
     asked by another screen, the camera frames the first data ([have_data]:
     it has arrived); [saving]: a rename is being
     written. *)
  let map = ref Map_slot.Creating
  and query = ref Map_filter.Everything
  and searching = ref (Idle 0)
  and needs_fit =
    ref (Option.is_none restored.camera && Option.is_none restored.focus)
  and have_data = ref false
  and saving = ref false in
  let alive () = Map_slot.alive !map in
  let head_el = El.div []
  and summary_el = El.div []
  and message_el = El.div [] in
  let header =
    El.div ~at:[cls "map-tab__header"] [head_el; summary_el; message_el]
  in
  let body = El.div ~at:[cls "map-tab__body"] [] in
  (* Snap points before layout; [measure] replaces them before the first
     frame. *)
  let sheet =
    W.Sheet.v
      ~snaps:
        (Map_sheet.snaps
           ~available:(Float.of_int (Window.inner_height G.window))
           ~top:0.)
      ~start:(match restored.selected with Some _ -> 1 | None -> 0)
      ~header:[header] ~body:[body] ()
  in
  El.set_class (Jstr.v "map-tab__sheet") true sheet.el;
  let push_map () =
    match !map with
    | Map_slot.Ready m ->
        let v = React.S.value view in
        Geo_map.set_places m v.places;
        Geo_map.set_selection m v.selected
    | Map_slot.(Creating | Failed | Released) -> ()
  in
  (* Read when the map exists, not at entry: the framing is the latest one
     asked. Also taken, and dropped, when the map cannot be created, so that it
     does not surprise a later visit. *)
  let take_focus () =
    let current = React.S.value (State.map_view state) in
    State.set_map_view state {current with focus = None};
    current.focus
  in
  let first_fit () =
    match (!map, !needs_fit && !have_data) with
    | Map_slot.Ready m, true ->
        needs_fit := false;
        Option.iter
          (fun b -> Geo_map.fit m b ~padding_px)
          (Features.bounds (shown_members (React.S.value view).places))
    | Map_slot.(Ready _ | Creating | Failed | Released), _ -> ()
  in
  (* Places from the data, the filters and the search; the selection is found
     again by any member's id, since a place's key can change when an earlier
     observation joins it. A place the filters or the search hide stays
     selected in State, and comes back with the sheet open when it shows
     again; one whose observation is gone from the data is forgotten. *)
  let recompute_loaded ?selected data =
    let f = React.S.value filters in
    let tagged = Collection_filter.tagged data.links f.tags in
    let filter =
      Journal_filter.keep ~year_of ~year:f.year
        ~to_identify_only:f.to_identify_only ~tagged
    in
    let places =
      Features.places ~keep:(Map_filter.keep ~filter !query) data.observations
    in
    let key =
      match selected with
      | Some key -> key
      | None -> (React.S.value (State.map_view state)).selected
    in
    let found = Option.bind key (Features.find places) in
    let exists id =
      List.exists
        (fun (o : Observation.t) -> Observation_id.equal o.id id)
        data.observations
    in
    let kept =
      match (found, key) with
      | Some p, _ -> Some p.key
      | None, Some id when exists id -> Some id
      | None, (Some _ | None) -> None
    in
    (match (key, found, (React.S.value view).selected) with
    | Some _, None, _ -> sheet.snap_to 0
    | _, Some _, None -> sheet.snap_to 1
    | _, Some _, Some _ | None, None, _ -> ());
    let step = React.Step.create () in
    set_view ~step
      {(React.S.value view) with data; places; selected = found; notice = None};
    (match found with None -> stop_renaming ~step () | Some _ -> ());
    let current = React.S.value (State.map_view state) in
    State.set_map_view state ~step {current with selected = kept};
    React.Step.execute step;
    push_map ();
    first_fit ()
  in
  let recompute ?selected data =
    match !have_data with
    | false -> ()
    | true -> recompute_loaded ?selected data
  in
  let select = function
    | None ->
        recompute ~selected:None (React.S.value view).data;
        sheet.snap_to 0
    | Some (p : Features.place) ->
        (* The field was opened for the place shown, not for this one. *)
        (match (React.S.value view).selected with
        | Some q when Observation_id.equal q.key p.key -> ()
        | Some _ | None -> stop_renaming ());
        recompute ~selected:(Some p.key) (React.S.value view).data;
        sheet.snap_to 1
  in
  let frame () =
    let places = (React.S.value view).places in
    (match (!map, Features.bounds (shown_members places)) with
    | Map_slot.Ready m, Some b -> Geo_map.fit m b ~padding_px
    | Map_slot.(Ready _ | Creating | Failed | Released), _ -> ());
    match places with [p] -> select (Some p) | [] | _ :: _ :: _ -> ()
  in
  let run_search text =
    let mine = search_seq !searching + 1 in
    let frame_on_reply =
      match !searching with
      | Running r -> r.frame_on_reply
      | Idle (_ : int) -> false
    in
    searching := Running {seq = mine; frame_on_reply};
    let finish q =
      let frame_now =
        match !searching with
        | Running {frame_on_reply; seq = _} -> frame_on_reply
        | Idle (_ : int) -> false
      in
      searching := Idle mine;
      query := q;
      recompute (React.S.value view).data;
      match frame_now with true -> frame () | false -> ()
    in
    match Search.plants_by_name text with
    | None -> finish Map_filter.Everything
    | Some plants ->
        let place c =
          match Map_filter.place_name c with
          | Some name -> Fold.matches ~query:text name
          | None -> false
        in
        Fut.await (Db.all db plants) (function
          | _ when (not (alive ())) || mine <> search_seq !searching -> ()
          | Error e ->
              log_error "recherche" (Db.error_to_string e);
              (* Place names still match: the map follows the text. *)
              finish (Map_filter.Matching {plants = []; place});
              let v = React.S.value view in
              set_view {v with notice = Some Map_sheet.Search_failed}
          | Ok found ->
              finish
                (Map_filter.Matching
                   {plants = List.map (fun (p : Plant.t) -> p.id) found; place}))
  in
  let on_enter () =
    match !searching with
    | Idle (_ : int) -> frame ()
    | Running r -> searching := Running {r with frame_on_reply = true}
  in
  (* The load's result arrives through [loaded], so that a released screen
     ([Rb.act] stopped) does not write its state. *)
  let loaded, send_loaded = React.E.create () in
  let on_loaded = function
    | Error e ->
        log_error "lecture" (Db.error_to_string e);
        let v = React.S.value view in
        set_view {v with notice = Some Map_sheet.Read_failed}
    | Ok data ->
        have_data := true;
        RList.set chips_handle
          (Filter_chips.chips ~year_of (React.S.value filters) data.observations
             data.tags);
        recompute data
  in
  let reload () = Fut.await (load db) send_loaded in
  let on_tap ({hits; at = _} : Geo_map.tap) =
    match hits with
    | Features.Group b :: _ -> (
        (* Framed, its places no longer overlap on screen and split; a group
           whose places sit within a few metres is framed at max_zoom, past
           detail_zoom. *)
        match !map with
        | Map_slot.Ready m -> Geo_map.fit m b ~padding_px
        | Map_slot.(Creating | Failed | Released) -> ())
    | Features.Member id :: _ ->
        Option.iter
          (fun p -> select (Some p))
          (Features.find (React.S.value view).places id)
    | [] -> select None
  in
  let on_moveend ~center ~zoom =
    let current = React.S.value (State.map_view state) in
    State.set_map_view state {current with camera = Some {center; zoom}}
  in
  let container = El.div ~at:[cls "map-tab__map"] [] in
  (* The router mounts the screen in the step that builds it, and [create]
     fetches the style first: the container is in the document, with its
     size, when MapLibre reads it. *)
  (match theme with
  | Error (Theme.Missing_tokens missing) ->
      map := Map_slot.Failed;
      ignore (take_focus ());
      log_error "thème" (String.concat ", " missing)
  | Ok theme ->
      let camera = Option.value restored.camera ~default:Locate.world in
      Fut.await
        (Geo_map.create container ~colours:theme.map ~center:camera.center
           ~zoom:camera.zoom ~interactive:true) (function
        | Ok m when not (alive ()) -> Geo_map.remove m
        | Error _ when not (alive ()) -> ()
        | Error e ->
            map := Map_slot.Failed;
            ignore (take_focus ());
            log_error "création" (Geo_map.error_to_string e);
            let v = React.S.value view in
            set_view {v with broken = Some Map_sheet.Map_unavailable}
        | Ok m ->
            map := Map_slot.Ready m;
            Geo_map.on_tap m on_tap;
            Geo_map.on_moveend m on_moveend;
            push_map ();
            (match take_focus () with
            | Some b ->
                needs_fit := false;
                Geo_map.fit m b ~padding_px ~animate:false
            | None -> ());
            first_fit ()));
  reload ();
  let locate () =
    Fut.await (Locate.current ~what:"carte: position") (function
      | _ when not (alive ()) -> ()
      | Error notice ->
          let v = React.S.value view in
          set_view {v with notice = Some notice}
      | Ok fix -> (
          (* A position now: an earlier position failure no longer holds. *)
          let v = React.S.value view in
          (match v.notice with
          | Some
              (Map_sheet.Position_unavailable | Location_denied | Location_off)
            ->
              set_view {v with notice = None}
          | Some (Loading | Read_failed | Search_failed) | None -> ());
          match !map with
          | Map_slot.Ready m ->
              let zoom =
                Float.max Herbier_geo.Style.detail_zoom
                  (Option.value (Geo_map.zoom m) ~default:0.)
              in
              Geo_map.fly_to m ~center:fix ~zoom
          | Map_slot.(Creating | Failed | Released) -> ()))
  in
  let rename (p : Features.place) text =
    match (!saving, Places.rename text ~at:(Ptime_clock.now ()) p.cluster) with
    | true, _ -> ()
    | false, [] -> stop_renaming ()
    | false, edits ->
        saving := true;
        set_rename_failed false;
        Fut.await
          (App.save app (List.map Observations.upsert edits))
          (fun result ->
            saving := false;
            (match result with
            | Error e -> log_error "renommer" (Db.error_to_string e)
            | Ok (_ : int) -> ());
            (* The field stays open on a failure, for another try. *)
            match (alive (), result) with
            | false, _ -> ()
            | true, Error _ -> set_rename_failed true
            | true, Ok _ -> stop_renaming ())
  in
  let head_view = function
    | Line line -> (El.p ~at:[cls "map-tab__line"] [El.txt' line], [])
    | Title title ->
        let button = Html.button ["map-tab__rename"] [El.txt' "Renommer"] in
        let click, b = Rb.click button in
        ( El.div
            ~at:[cls "map-tab__title-row"]
            [El.h2 ~at:[cls "map-tab__title"] [El.txt' title]; button],
          [
            b;
            Rb.act click (fun () ->
                set_renaming true;
                Option.iter (El.set_has_focus true)
                  (El.find_first_by_selector ~root:header
                     (Jstr.v ".map-tab__rename-field input")));
          ] )
    | Renaming {value; placeholder} ->
        let field = W.Text_field.v ~action:"OK" ~value ~placeholder () in
        El.set_class (Jstr.v "map-tab__rename-field") true field.el;
        (* The place shown now: a reload may have widened it since. *)
        let submit () =
          Option.iter
            (fun p -> rename p (React.S.value field.value))
            (React.S.value view).selected
        in
        ( field.el,
          Rb.act field.action submit
          :: Rb.listen field.input Ev.keydown (fun ev ->
              match enter ev with true -> submit () | false -> ())
          :: field.bindings )
  in
  let locate_button =
    W.Icon_button.el ~classes:["map-tab__locate"] ~label:"Ma position"
      W.Icon.My_location
  in
  let locate_click, locate_binding = Rb.click locate_button in
  let chips_el = El.div ~at:[cls "chip-row"; cls "map-tab__chips"] [] in
  let top =
    El.div
      ~at:[cls "map-tab__top"]
      [El.div ~at:[cls "map-tab__search"] [search.el; locate_button]; chips_el]
  in
  let el = El.div ~at:[cls "map-tab"] [container; top; sheet.el] in
  (* The sheet's room is measured, not assumed: the tab bar below and the
     controls above both grow with the safe-area insets. A screen not laid
     out (released) measures 0 and keeps its snap points. *)
  let measure () =
    let available = El.bound_h el in
    match available > 0. with
    | false -> ()
    | true ->
        let top = El.bound_y top +. El.bound_h top -. El.bound_y el in
        sheet.set_snaps (Map_sheet.snaps ~available ~top)
  in
  ignore (G.request_animation_frame (fun _ -> measure ()));
  let resize =
    Ev.listen Ev.resize (fun _ -> measure ()) (Window.as_target G.window)
  in
  let release_map = Rb.on_release (fun () -> Map_slot.release map) in
  {
    Screen.el;
    bindings =
      List.concat
        [
          [
            Rb.on_release (fun () -> Ev.unlisten resize);
            release_map;
            Rb.act loaded on_loaded;
            Rb.rlist chips_el (Filter_chips.el state) chips;
            Rb.view head_el head_view
              (React.S.l2 ~eq:head_equal (fun v r -> head (v, r)) view renaming);
            Rb.view summary_el
              (optional_p "map-tab__summary")
              (React.S.map ~eq:(Option.equal String.equal) summary view);
            Rb.view message_el
              (optional_p "map-tab__message")
              (React.S.l2
                 ~eq:(Option.equal String.equal)
                 (fun v f -> message (v, f))
                 view rename_failed);
            Rb.view body rows
              (React.S.map ~eq:same_rows (fun v -> (v.data, v.selected)) view);
            Rb.act (React.S.changes filters) (fun _ ->
                recompute (React.S.value view).data);
            Rb.act (React.S.changes search.value) run_search;
            Rb.listen search.input Ev.keydown (fun ev ->
                match enter ev with true -> on_enter () | false -> ());
            locate_binding;
            Rb.act locate_click locate;
            Rb.act (App.saved app) reload;
          ];
          search.bindings;
          sheet.bindings;
        ];
  }
