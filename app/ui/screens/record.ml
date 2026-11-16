module Fr_text = Herbier_ui_model.Fr_text
module Gps = Herbier_ui_model.Gps
module Record_plan = Herbier_ui_model.Record_plan
open Brr
module Db = Herbier_store_io.Db
module Plants = Herbier_store.Plants
module Observations = Herbier_store.Observations
module Search = Herbier_store.Search
module Plant = Herbier_domain.Plant
module Plant_id = Herbier_domain.Ids.Plant_id
module Observation = Herbier_domain.Observation
module Observation_id = Herbier_domain.Ids.Observation_id
module Capture = Herbier_photos_io.Capture
module Object_url = Herbier_bindings.Object_url
module Camera_stream = Herbier_bindings.Camera_stream
module RList = ReactiveData.RList
module W = Widgets

let cls = Html.cls
let log = Log.error ~scope:"noter"

type suggestion = {plant : Plant.t; seen_here : bool}

let button = Html.button

type discard = Discard | Continue

let photos_not_saved n =
  Printf.sprintf "%s. Réessayez."
    (Fr_text.plural n "photo non enregistrée" "photos non enregistrées")

let v app =
  let db = App.db app and state = App.state app in
  (* style: section banners because the sections of this one screen share its
     state (camera, shots, save) and splitting [v] would thread it all. *)
  (* Camera *)
  let video =
    El.video
      ~at:[cls "record__video"; At.v (Jstr.v "playsinline") Jstr.empty]
      []
  in
  let camera_note = El.p ~at:[cls "record__camera-note"; cls "is-hidden"] [] in
  (* style: the open viewfinder, the facing, the open's number, the released
     flag and the stored observation are refs because they are read and written
     from DOM and future callbacks only and never shown. *)
  let viewfinder = ref None
  and facing = ref Camera_stream.Back
  and camera_seq = ref 0
  and released = ref false
  and stored = ref None in
  (* Every start and stop takes a new number: an open that resolves after a
     later start or stop (a second flip, the screen left) closes its own
     stream. *)
  let stop_camera () =
    incr camera_seq;
    Option.iter Capture.close_viewfinder !viewfinder;
    viewfinder := None
  in
  let start_camera () =
    incr camera_seq;
    let this_open = !camera_seq in
    Fut.await (Capture.open_viewfinder ~facing:!facing ~video ()) (function
      | Ok v when this_open <> !camera_seq -> Capture.close_viewfinder v
      | Ok v ->
          viewfinder := Some v;
          El.set_class (Jstr.v "is-hidden") true camera_note
      | Error _ when this_open <> !camera_seq -> ()
      | Error e ->
          El.set_children camera_note
            [
              El.txt'
                "Caméra indisponible. Les photos peuvent venir de la galerie.";
            ];
          El.set_class (Jstr.v "is-hidden") false camera_note;
          log "camera" (Capture.error_to_string e))
  in
  start_camera ();
  let gps = Gps_fix.start ~on_error:(log "gps") () in
  (* Shots *)
  let thumbs, thumbs_handle = RList.create [] in
  let items () = RList.value thumbs in
  let count = React.S.map List.length (RList.signal thumbs) in
  let saving, set_saving = React.S.create false in
  let save_error, set_save_error = React.S.create None in
  let add shots =
    match !released with
    | true -> ()
    | false ->
        RList.patch thumbs_handle
          (List.map
             (fun (s : Capture.shot) ->
               ReactiveData.RList.I (-1, (s, Object_url.create s.preview.jpeg)))
             shots)
  in
  let remove url =
    let rec index i = function
      | [] -> None
      | (_, u) :: _ when Jstr.equal u url -> Some i
      | _ :: rest -> index (i + 1) rest
    in
    match index 0 (items ()) with
    | None -> ()
    | Some i ->
        Object_url.revoke url;
        RList.remove i thumbs_handle
  in
  let thumb ((_ : Capture.shot), url) =
    let x =
      button ~label:"Retirer la photo" ["record__thumb-x"]
        [
          El.span
            ~at:[cls "record__thumb-disc"]
            [W.Icon.el ~size:16 W.Icon.Close];
        ]
    in
    let el =
      El.div
        ~at:[cls "record__thumb"]
        [El.img ~at:[At.src url; At.v (Jstr.v "alt") Jstr.empty] (); x]
    in
    let click, b = Rb.click x in
    (el, [b; Rb.act click (fun () -> remove url)])
  in
  let gallery = button ["record__gallery"] [El.txt' "galerie"] in
  let shutter = button ~label:"Prendre la photo" ["record__shutter"] [] in
  let flip =
    button ~label:"Changer de caméra" ["record__flip"]
      [W.Icon.el W.Icon.Refresh]
  in
  let close =
    button ~label:"Fermer" ["record__close"] [W.Icon.el W.Icon.Close]
  in
  (* Name and suggestions *)
  let name = W.Text_field.v ~placeholder:"Nom de la plante — facultatif" () in
  El.set_class (Jstr.v "record__name") true name.el;
  (* style: refs because [plants] and [observations] feed [suggest] and
     [chosen] feeds [save]; written by the one-time load, a chip tap and each
     query, and never shown. *)
  let plants = ref []
  and observations = ref []
  and chosen = ref None
  and query_seq = ref 0 in
  let suggestions, suggestions_handle = RList.create [] in
  let suggest () =
    incr query_seq;
    let this_query = !query_seq in
    let text = React.S.value name.value in
    let here =
      match React.S.value gps with
      | Gps.Fix p -> Record_plan.seen_here ~here:p !observations !plants
      | Gps.Searching | Gps.No_fix -> []
    in
    let matching =
      match Search.plants text with None -> Fut.ok [] | Some q -> Db.all db q
    in
    Fut.await matching (function
      | Error e -> log "search" (Db.error_to_string e)
      | Ok _ when this_query <> !query_seq -> ()
      | Ok found ->
          let top_matches = List.take 3 found in
          let fresh (p : Plant.t) =
            not
              (List.exists
                 (fun (q : Plant.t) -> Plant_id.equal p.id q.id)
                 top_matches)
          in
          let here = List.take 4 (List.filter fresh here) in
          RList.set suggestions_handle
            (List.map (fun plant -> {plant; seen_here = false}) top_matches
            @ List.map (fun plant -> {plant; seen_here = true}) here))
  in
  Fut.await
    (let open Fut.Result_syntax in
     let* ps = Db.all db Plants.list in
     let+ os = Db.all db Observations.list in
     (ps, os))
    (function
      | Error e -> log "load" (Db.error_to_string e)
      | Ok (ps, os) ->
          plants := ps;
          observations := os;
          suggest ());
  let suggestion s =
    let label =
      match s.seen_here with
      | false -> s.plant.display_name ^ " · déjà en collection"
      | true -> s.plant.display_name
    in
    let el = button ["record__suggestion"] [El.txt' label] in
    El.set_class (Jstr.v "record__suggestion--here") s.seen_here el;
    let click, b = Rb.click el in
    ( el,
      [
        b;
        Rb.act click (fun () ->
            chosen := Some s.plant;
            name.set s.plant.display_name);
      ] )
  in
  let here_label =
    El.span
      ~at:[cls "record__here-label"; cls "is-hidden"]
      [El.txt' "Vues ici ↓"]
  in
  let suggestion_list = El.div ~at:[cls "record__suggestions"] [] in
  (* Save *)
  let save_button = button ["record__save"] [] in
  let save_note = El.p ~at:[cls "record__save-note"; cls "is-hidden"] [] in
  let save_label =
    React.S.map
      (function
        | 0 -> "Enregistrer"
        | 1 -> "Enregistrer (1 photo)"
        | n -> Printf.sprintf "Enregistrer (%d photos)" n)
      count
  in
  let fail message =
    set_saving false;
    set_save_error (Some message)
  in
  (* Shots added while saving (a shutter future resolving late) are saved on
     the next round. *)
  let rec save_shots (o : Observation.t) =
    let shots = List.map fst (items ()) in
    Fut.await (App.save_photos app ~observation:o shots) (fun failed ->
        let saved (s, _) = List.memq s shots && not (List.memq s failed) in
        let kept, gone = List.partition (fun i -> not (saved i)) (items ()) in
        List.iter (fun (_, u) -> Object_url.revoke u) gone;
        RList.set thumbs_handle kept;
        match (failed, kept) with
        | [], [] -> (
            match !released with
            | true -> ()
            | false -> Route.replace (Route.Modal (Route.Saved o.id)))
        | [], _ :: _ -> save_shots o
        | _ :: _, _ -> fail (photos_not_saved (List.length failed)))
  in
  let observation () =
    let open Fut.Result_syntax in
    let now = Ptime_clock.now () in
    let fix = Gps.position (React.S.value gps) in
    let at, position =
      Record_plan.when_where ~now ~fix
        (List.map
           (fun ((s : Capture.shot), _) -> (s.exif.taken_at, s.exif.position))
           (items ()))
    in
    (* Read now, not at opening: the one-time load may not be in yet. *)
    let* plants = Db.all db Plants.list in
    let plant_edits, plant_id =
      match
        Record_plan.target ~plants ~chosen:!chosen (React.S.value name.value)
      with
      | Existing p -> ([], Some p.id)
      | Free n ->
          let p = Plant.v ~id:(Plant_id.fresh ()) ~at:now n in
          ([Plants.upsert p], Some p.id)
      | To_identify -> ([], None)
    in
    let o =
      {
        Observation.id = Observation_id.fresh ();
        plant_id;
        at;
        position;
        place_label = None;
        place_derived = None;
        note = None;
        created_at = now;
        updated_at = now;
        deleted_at = None;
      }
    in
    let+ (_ : int) = App.save app (plant_edits @ [Observations.upsert o]) in
    o
  in
  let save () =
    match React.S.value saving with
    | true -> ()
    | false -> (
        set_saving true;
        set_save_error None;
        match !stored with
        | Some o -> save_shots o
        | None ->
            Fut.await (observation ()) (function
              | Error e ->
                  log "save" (Db.error_to_string e);
                  fail "Enregistrement impossible. Réessayez."
              | Ok o ->
                  stored := Some o;
                  save_shots o))
  in
  let idle f () =
    match React.S.value saving with true -> () | false -> f ()
  in
  let discard =
    W.Dialog.v ~title:"Abandonner ces photos ?"
      ~text:"Elles ne sont pas encore enregistrées."
      [
        (W.Button.Danger, "Abandonner", Discard);
        (W.Button.Secondary, "Continuer", Continue);
      ]
  in
  let offline =
    El.span ~at:[cls "record__pill"; cls "record__pill--offline"] []
  in
  let gps_text = El.span [] in
  let gps_pill =
    El.span
      ~at:[cls "record__pill"]
      [El.span ~at:[cls "record__dot"] []; gps_text]
  in
  let thumb_list = El.div ~at:[cls "record__thumb-list"] [] in
  let el =
    El.div
      ~at:[cls "record"]
      [
        video;
        camera_note;
        El.div ~at:[cls "record__top"] [close; offline; gps_pill];
        El.div
          ~at:[cls "record__bottom"]
          [
            El.div ~at:[cls "record__thumbs"] [thumb_list; gallery];
            name.el;
            El.div
              ~at:[cls "record__suggestion-row"]
              [suggestion_list; here_label];
            save_note;
            El.div ~at:[cls "record__controls"] [flip; save_button; shutter];
          ];
        discard.el;
      ]
  in
  let close_click, b_close = Rb.click close in
  let shutter_click, b_shutter = Rb.click shutter in
  let gallery_click, b_gallery = Rb.click gallery in
  let flip_click, b_flip = Rb.click flip in
  let save_click, b_save = Rb.click save_button in
  let bindings =
    List.concat
      [
        [
          b_close;
          b_shutter;
          b_gallery;
          b_flip;
          b_save;
          Rb.on_release (fun () ->
              released := true;
              stop_camera ();
              List.iter (fun (_, u) -> Object_url.revoke u) (items ()));
          Rb.rlist thumb_list thumb thumbs;
          Rb.rlist suggestion_list suggestion suggestions;
          Rb.text save_button save_label;
          Rb.attr save_button "aria-busy"
            (React.S.map
               (function true -> Some "true" | false -> None)
               saving);
          Rb.text save_note (React.S.map (Option.value ~default:"") save_error);
          Rb.class_ save_note "is-hidden"
            (React.S.map Option.is_none save_error);
        ];
        List.map
          (fun el ->
            Rb.attr el "disabled"
              (React.S.map (function true -> Some "" | false -> None) saving))
          [close; shutter; gallery; flip];
        [
          Rb.act close_click
            (idle (fun () ->
                 match items () with
                 | [] -> Route.back ()
                 | _ :: _ -> discard.show ()));
          Rb.act discard.choice (function
            | Discard -> idle Route.back ()
            | Continue -> ());
          Rb.act shutter_click
            (idle (fun () ->
                 match !viewfinder with
                 | None -> ()
                 | Some v ->
                     Fut.await (Capture.shutter v) (function
                       | Ok s -> add [s]
                       | Error e -> log "shutter" (Capture.error_to_string e))));
          Rb.act gallery_click
            (idle (fun () ->
                 Fut.await (Capture.pick ~limit:10) (function
                   | Ok shots -> add shots
                   | Error e -> log "gallery" (Capture.error_to_string e))));
          Rb.act flip_click
            (idle (fun () ->
                 stop_camera ();
                 (facing :=
                    match !facing with
                    | Camera_stream.Back -> Camera_stream.Front
                    | Front -> Back);
                 start_camera ()));
          Rb.act save_click save;
          Rb.act (React.S.changes name.value) (fun text ->
              (match !chosen with
              | Some (p : Plant.t) when not (String.equal p.display_name text)
                ->
                  chosen := None
              | Some _ | None -> ());
              suggest ());
          Rb.act (React.S.changes gps) (fun _ -> suggest ());
          Rb.class_ here_label "is-hidden"
            (React.S.map
               (fun l -> not (List.exists (fun s -> s.seen_here) l))
               (RList.signal suggestions));
          Rb.text gps_text
            (React.S.map
               (function
                 | Gps.Searching -> "Position…"
                 | Gps.Fix _ -> "Position acquise"
                 | Gps.No_fix -> "Sans position")
               gps);
          Rb.class_ gps_pill "record__pill--fix"
            (React.S.map
               (function
                 | Gps.Fix _ -> true | Gps.(Searching | No_fix) -> false)
               gps);
          Rb.text offline
            (React.S.l2
               (fun ({online} : State.network) q ->
                 Herbier_ui_model.Network_text.banner ~online
                   ~pending:(Herbier_ui_model.Drive_text.pending_count q)
                 |> Option.value ~default:"")
               (State.network state) (App.upload_queue app));
          Rb.class_ offline "is-hidden"
            (React.S.map
               (fun (n : State.network) -> n.online)
               (State.network state));
        ];
        name.bindings;
        discard.bindings;
      ]
  in
  {Screen.el; bindings; ready = Screen.now}
