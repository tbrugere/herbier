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
module Organ = Herbier_identify.Organ
module Plantnet = Herbier_identify.Plantnet
module Caller = Herbier_ui_model.Identify.Caller
module Choice = Herbier_ui_model.Identify.Choice
module Plant_link = Herbier_ui_model.Plant_link
module Photo_id = Herbier_domain.Ids.Photo_id

let cls = Html.cls
let log = Log.error ~scope:"noter"

type suggestion = {plant : Plant.t; seen_here : bool}

let button = Html.button

type discard = Discard | Continue

(* An identification asked from 4d, kept for a reopen with an ask it answers
   ({!Record_plan.reuses}): in flight, or settled with an answer worth
   keeping. *)
type kept = {
  ask : App.image Record_plan.ask;
  answer : Herbier_identify.identified App.current Fut.t;
}

(* A photo being taken for the layer's « + <organe> ». *)
type taking = {
  organ : Organ.sent;
  give : Identify.photo option -> unit;
  entry : Overlay.t;
}

let same_image (a : App.image) (b : App.image) =
  match (a, b) with
  | Preview a, Preview b -> a == b
  | Stored a, Stored b -> Photo_id.equal a b
  | Preview _, Stored _ | Stored _, Preview _ -> false

let photos_not_saved n =
  Printf.sprintf "%s. Réessayez."
    (Fr_text.plural n "photo non enregistrée" "photos non enregistrées")

let v app =
  let db = App.db app and state = App.state app in
  (* Created first: the identification layer is mounted in it. *)
  let el = El.div ~at:[cls "record"] [] in
  (* style: section banners because the sections of this one screen share its
     state (camera, shots, identification, save) and splitting [v] would thread
     it all: identification reads the row, the name field, [saving] and
     [released], and the camera reads its take, the save its choice. *)
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
  let append shots =
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
  let remove_preview blob =
    match
      List.find_opt
        (fun ((s : Capture.shot), _) -> s.preview.jpeg == blob)
        (items ())
    with
    | Some (_, url) -> remove url
    | None -> ()
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
  let identify_button =
    button ~label:Record_plan.identify_label ["record__identify"]
      [
        El.span
          ~at:[cls "record__identify-disc"]
          [W.Identify_glyph.el ~size:20 ()];
      ]
  in
  let name =
    W.Text_field.v ~trailing:identify_button
      ~placeholder:"Nom de la plante — facultatif" ()
  in
  El.set_class (Jstr.v "record__name") true name.el;
  (* The one-time load's plants: 6e's card names its owner from them. *)
  let plants, set_plants =
    React.S.create ~eq:(List.equal Plant.equal) ([] : Plant.t list)
  in
  (* style: refs because [observations] feeds [suggest] and [chosen] feeds
     [save]; written by the one-time load, a chip tap and each query, and
     never shown. *)
  let observations = ref [] and chosen = ref None and query_seq = ref 0 in
  let suggestions, suggestions_handle = RList.create [] in
  let suggest () =
    incr query_seq;
    let this_query = !query_seq in
    let text = React.S.value name.value in
    let here =
      match React.S.value gps with
      | Gps.Fix p ->
          Record_plan.seen_here ~here:p !observations (React.S.value plants)
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
          set_plants ps;
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
  (* Identification (6a, 6e) *)
  let gate = App.identify_gate app in
  let channel = App.channel () in
  (* style: refs because the layer, the kept answer, the photo being taken, the
     organ of each shot (by preview Blob) and the arming of the first-photo
     opening are read and written from DOM and future callbacks only and never
     shown; [choice_seq] drops a GBIF answer for an older choice. *)
  let layer = ref None
  and kept = ref None
  and taking = ref None
  and organs = ref []
  and armed = ref true
  and choice_seq = ref 0 in
  let choice, set_choice =
    React.S.create ~eq:(Option.equal Choice.equal) None
  in
  let organ_of (s : Capture.shot) =
    List.find_map
      (fun (b, o) ->
        match b == s.preview.jpeg with true -> Some o | false -> None)
      !organs
    |> Option.value ~default:Organ.Auto
  in
  let layer_photos () =
    List.map
      (fun ((s : Capture.shot), _) ->
        {Identify.image = App.Preview s.preview.jpeg; organ = organ_of s})
      (items ())
  in
  (* An ask the kept one answers ({!Record_plan.reuses}) gets that answer: no
     second request. Only a 200 or a 404 is kept once settled. *)
  let identify ~key ~flora ~no_reject photos =
    let sent = List.take Organ.max_photos photos in
    let ask =
      {
        Record_plan.photos = List.map fst sent;
        organs = List.map snd sent;
        flora = Plantnet.asked_flora flora;
        no_reject;
      }
    in
    match !kept with
    | Some k when Record_plan.reuses same_image ~kept:k.ask ask -> k.answer
    | Some _ | None ->
        let answer = App.identify app channel ~key ~flora ~no_reject photos in
        let entry = {ask; answer} in
        kept := Some entry;
        Fut.await answer (fun current ->
            let keep =
              match current with
              | App.Settled r ->
                  Record_plan.keep_answer
                    (Result.map_error Identify.error_of_app r)
              | Superseded -> false
            in
            match (!kept, keep) with
            | Some k, false when k == entry -> kept := None
            | (Some _ | None), (true | false) -> ());
        answer
  in
  let services = {(Identify.services app channel) with identify} in
  let clear_choice () =
    incr choice_seq;
    set_choice None
  in
  let choose p =
    incr choice_seq;
    let mine = !choice_seq in
    let c = Choice.v p in
    set_choice (Some c);
    Fut.await (App.resolve_choice p) (fun r ->
        match (!released, Int.equal mine !choice_seq) with
        | false, true -> set_choice (Some (Choice.resolved c r))
        | true, (true | false) | false, false -> ())
  in
  let choice_clear =
    button ~label:Record_plan.clear_choice_label ["record__choice-clear"]
      [W.Icon.el ~size:20 W.Icon.Close]
  in
  let focus_back () =
    El.set_has_focus true
      (match React.S.value choice with
      | Some _ -> choice_clear
      | None -> identify_button)
  in
  let on_close outcome (photos : Identify.photo list) =
    layer := None;
    match !released with
    | true -> ()
    | false ->
        let row =
          List.map (fun ((s : Capture.shot), _) -> s.preview.jpeg) (items ())
        in
        let given =
          List.filter_map
            (fun (p : Identify.photo) ->
              match p.image with
              | Preview b -> Some (b, p.organ)
              | Stored (_ : Photo_id.t) -> None)
            photos
        in
        organs := List.filter (fun (b, _) -> List.memq b row) (given @ !organs);
        let after = Record_plan.after_layer outcome in
        (match after.choice with
        | Keep_choice -> ()
        | Clear_choice -> clear_choice ()
        | Set_choice p -> choose p);
        (match after.clear_text with true -> name.set "" | false -> ());
        (match after.retake with
        | true ->
            List.iter
              (fun (b, _) -> remove_preview b)
              (List.take Organ.max_photos given);
            armed := true
        | false -> ());
        focus_back ()
  in
  let taking_pill = El.span ~at:[cls "record__pill"] [] in
  let taking_cancel =
    button ["record__taking-cancel"] [El.txt' Record_plan.taking_cancel]
  in
  let taking_bar =
    El.div ~at:[cls "record__taking"] [taking_pill; taking_cancel]
  in
  let finish_take shot =
    match !taking with
    | None -> ()
    | Some t ->
        taking := None;
        Overlay.remove t.entry;
        El.set_class (Jstr.v "record--taking") false el;
        t.give
          (Option.map
             (fun (s : Capture.shot) ->
               {Identify.image = App.Preview s.preview.jpeg; organ = t.organ})
             shot)
  in
  (* « + <organe> »: the layer steps aside for 4d's own viewfinder until the
     next shot, a gallery pick, « Annuler » or back (which cancels the take,
     not the layer). *)
  let add_photo organ =
    match !taking with
    | Some (_ : taking) -> Fut.return None
    | None ->
        let photo, give = Fut.create () in
        let entry = Overlay.push ~close:(fun () -> finish_take None) in
        taking := Some {organ; give; entry};
        El.set_children taking_pill [El.txt' (Record_plan.taking_label organ)];
        El.set_class (Jstr.v "record--taking") true el;
        El.set_has_focus true taking_cancel;
        photo
  in
  let open_layer () =
    match (!released, !layer, !taking, layer_photos ()) with
    | false, None, None, (_ :: _ as photos) ->
        layer :=
          Some
            (Identify.open_ ~host:el services ~caller:Caller.Noter ~add_photo
               ~on_close photos)
    | true, _, _, _
    | false, Some _, _, _
    | false, None, Some _, _
    | false, None, None, [] ->
        ()
  in
  (* The session's first photos open 6b at once when « Identifier dès la
     photo » is on ({!Record_plan.auto_open}); a photo taken for the layer
     never does. *)
  let add shots =
    match !released with
    | true -> ()
    | false -> (
        let before = List.length (items ()) in
        append shots;
        let opens =
          (not (React.S.value saving))
          && Option.is_none !layer
          && Option.is_none !taking
          && Record_plan.auto_open ~armed:!armed
               ~on_photo:(React.S.value (App.identify_on_photo app))
               (React.S.value gate) ~before ~added:(List.length shots)
        in
        match opens with
        | true ->
            armed := false;
            open_layer ()
        | false -> ())
  in
  let took shots =
    match (!released, !taking, shots) with
    | false, Some t, (s : Capture.shot) :: _ ->
        organs := (s.preview.jpeg, t.organ) :: !organs;
        append [s];
        finish_take (Some s)
    | false, Some _, [] -> ()
    | false, None, _ | true, _, _ -> add shots
  in
  let identify_enabled =
    React.S.l2 (fun g n -> Record_plan.identify_enabled g ~photos:n) gate count
  in
  let identify_line = El.p ~at:[cls "record__identify-line"] [] in
  let choice_name = El.span ~at:[cls "record__choice-name"] [] in
  let choice_latin = El.span ~at:[cls "record__choice-latin"] [] in
  let choice_score = El.span [] in
  let choice_card =
    El.div
      ~at:[cls "record__choice"]
      [
        El.span
          ~at:[cls "record__choice-check"]
          [W.Icon.el ~size:20 W.Icon.Check];
        El.div
          ~at:[cls "record__choice-text"]
          [
            choice_name;
            El.span ~at:[cls "record__choice-sub"] [choice_latin; choice_score];
          ];
        choice_clear;
      ]
  in
  let already = El.p ~at:[cls "record__identify-line"] [] in
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
    let observation plant_id =
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
    let saved edits =
      Fut.map (Result.map (fun (_ : int) -> ())) (App.save app edits)
    in
    let o, write =
      match
        Record_plan.target ~plants ~chosen:!chosen
          ?choice:(React.S.value choice) (React.S.value name.value)
      with
      | Existing p ->
          let o = observation (Some p.id) in
          (o, saved [Observations.upsert o])
      | Free n ->
          let p = Plant.v ~id:(Plant_id.fresh ()) ~at:now n in
          let o = observation (Some p.id) in
          (o, saved [Plants.upsert p; Observations.upsert o])
      | Linked {name; taxon} ->
          let p =
            Plant_link.create ~id:(Plant_id.fresh ()) ~at:now ~name taxon
          in
          let o = observation (Some p.id) in
          (o, App.create_linked app ~extra:[Observations.upsert o] p taxon)
      | To_identify ->
          let o = observation None in
          (o, saved [Observations.upsert o])
    in
    let+ () = write in
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
  let suggestion_row =
    El.div ~at:[cls "record__suggestion-row"] [suggestion_list; here_label]
  in
  El.set_children el
    [
      video;
      camera_note;
      El.div ~at:[cls "record__top"] [close; offline; gps_pill];
      El.div
        ~at:[cls "record__bottom"]
        [
          taking_bar;
          El.div ~at:[cls "record__thumbs"] [thumb_list; gallery];
          El.div
            ~at:[cls "record__naming"]
            [name.el; choice_card; identify_line; already; suggestion_row];
          save_note;
          El.div ~at:[cls "record__controls"] [flip; save_button; shutter];
        ];
      discard.el;
    ];
  let close_click, b_close = Rb.click close in
  let shutter_click, b_shutter = Rb.click shutter in
  let gallery_click, b_gallery = Rb.click gallery in
  let flip_click, b_flip = Rb.click flip in
  let save_click, b_save = Rb.click save_button in
  let identify_click, b_identify = Rb.click identify_button in
  let clear_click, b_clear = Rb.click choice_clear in
  let cancel_click, b_cancel = Rb.click taking_cancel in
  let some_choice = React.S.map Option.is_some choice in
  (* The card's owner follows the load as well as the choice; the save reads
     the plants afresh, as late as possible. *)
  let owner =
    React.S.l2 ~eq:(Option.equal Plant.equal)
      (fun c ps -> Option.bind c (Record_plan.choice_owner ~plants:ps))
      choice plants
  in
  let line =
    React.S.map ~eq:(Option.equal String.equal) Record_plan.identify_line gate
  in
  let bindings =
    List.concat
      [
        [
          b_close;
          b_shutter;
          b_gallery;
          b_flip;
          b_save;
          b_identify;
          b_clear;
          b_cancel;
          Rb.on_release (fun () ->
              released := true;
              Option.iter Identify.close !layer;
              finish_take None;
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
                       | Ok s -> took [s]
                       | Error e -> log "shutter" (Capture.error_to_string e))));
          Rb.act gallery_click
            (idle (fun () ->
                 let limit =
                   match !taking with Some (_ : taking) -> 1 | None -> 10
                 in
                 Fut.await (Capture.pick ~limit) (function
                   | Ok shots -> took shots
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
          Rb.act identify_click
            (idle (fun () ->
                 match React.S.value identify_enabled with
                 | true -> open_layer ()
                 | false -> ()));
          Rb.act clear_click (fun () ->
              clear_choice ();
              name.set "";
              El.set_has_focus true name.input);
          Rb.act cancel_click (fun () -> finish_take None);
          Rb.attr identify_button "aria-disabled"
            (React.S.map
               (function true -> None | false -> Some "true")
               identify_enabled);
          Rb.attr identify_button "aria-label"
            (React.S.map (fun g -> Some (Record_plan.identify_aria g)) gate);
          Rb.text identify_line (React.S.map (Option.value ~default:"") line);
          Rb.class_ identify_line "is-hidden"
            (React.S.l2 (fun l c -> Option.is_none l || c) line some_choice);
          Rb.class_ name.el "is-hidden" some_choice;
          Rb.class_ suggestion_row "is-hidden" some_choice;
          Rb.class_ choice_card "is-hidden" (React.S.map not some_choice);
          Rb.text choice_name
            (React.S.l2
               (fun c o ->
                 match c with
                 | Some (c : Choice.t) -> Choice.label ~owner:o c.proposal
                 | None -> "")
               choice owner);
          Rb.text choice_latin
            (React.S.map
               (function Some (c : Choice.t) -> c.proposal.name | None -> "")
               choice);
          Rb.text choice_score
            (React.S.map
               (function
                 | Some (c : Choice.t) ->
                     " · " ^ Record_plan.choice_score c.proposal
                 | None -> "")
               choice);
          Rb.text already
            (React.S.map
               (function Some p -> Record_plan.already_line p | None -> "")
               owner);
          Rb.class_ already "is-hidden" (React.S.map Option.is_none owner);
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
