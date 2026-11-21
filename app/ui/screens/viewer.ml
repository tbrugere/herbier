module Cover = Herbier_ui_model.Cover
module Fr_date = Herbier_ui_model.Fr_date
module Journal_day = Herbier_ui_model.Journal_day
module Drive_text = Herbier_ui_model.Drive_text
open Brr
module Db = Herbier_store_io.Db
module Plants = Herbier_store.Plants
module Observations = Herbier_store.Observations
module Photos = Herbier_store.Photos
module Photo = Herbier_domain.Photo
module Photo_id = Herbier_domain.Ids.Photo_id
module Plant = Herbier_domain.Plant
module Observation = Herbier_domain.Observation
module Observation_id = Herbier_domain.Ids.Observation_id
module References = Herbier_store.References
module Ref_images = Herbier_store.Ref_images
module Projection = Herbier_refs.Projection
module Ref_photos = Herbier_ui_model.Ref_photos
module W = Widgets

let cls = Html.cls
let log_error = Log.db ~scope:"visionneuse"

type data = {
  plant : Plant.t option;
  photos : Photo.t list;  (** in viewing order *)
  observations : Observation.t list;
      (** the photos' and, for a move, the plant's *)
}

let load db id =
  let open Fut.Result_syntax in
  let* photo = Db.find db (Photos.get id) in
  match photo with
  | None -> Fut.ok None
  | Some (ph : Photo.t) -> (
      let* o = Db.find db (Observations.get ph.observation_id) in
      match o with
      | None -> Fut.ok None
      | Some (o : Observation.t) -> (
          let* plant =
            match o.plant_id with
            | Some p -> Db.find db (Plants.get p)
            | None -> Fut.ok None
          in
          match plant with
          | Some p ->
              let* photos = Db.all db (Photos.of_plant p.id) in
              let+ observations = Db.all db (Observations.of_plant p.id) in
              Some
                {
                  plant;
                  photos = Cover.ordered p.cover_photo_id photos;
                  observations;
                }
          | None ->
              let+ photos = Db.all db (Photos.of_observation o.id) in
              Some {plant = None; photos; observations = [o]}))

let obs_of (d : data) (ph : Photo.t) =
  List.find_opt
    (fun (o : Observation.t) -> Observation_id.equal o.id ph.observation_id)
    d.observations

let when_where (o : Observation.t) =
  String.concat " · "
    (Fr_date.day_time ~tz_offset_s:(Zone.offset_s o.at) o.at
    :: Option.to_list (Journal_day.place [o]))

let round ~label icon = Html.button ~label ["viewer__round"] [W.Icon.el icon]
let chip label = Html.button ["viewer__chip"] [El.txt' label]

type remove = Remove | Keep
type menu = Cover | Move | Cancel

(* The part both modes share: the track of slides (swipe, pinch), « i / n »
   and ✕. [on_show i] runs for the slide in view, first for [start]. *)
type frame = {track : El.t; top : El.t; bindings : Rb.binding list}

let frame ~n ~start ~slide ~on_show ~right =
  let zooms = List.init n (fun i -> W.Viewer_zoom.v (slide i)) in
  let track =
    El.div
      ~at:[cls "viewer__track"]
      (List.map
         (fun (z : W.Viewer_zoom.t) -> El.div ~at:[cls "viewer__slide"] [z.el])
         zooms)
  in
  let counter = El.span ~at:[cls "viewer__counter"] [] in
  (* style: the slide in view, written by [show] from the scroll listener. *)
  let index = ref start in
  let show i =
    index := i;
    El.set_children counter [El.txt' (Printf.sprintf "%d / %d" (i + 1) n)];
    on_show i;
    List.iteri (fun j (z : W.Viewer_zoom.t) -> if j <> i then z.reset ()) zooms
  in
  show start;
  let b_scroll =
    Rb.listen track Ev.scroll (fun _ ->
        let w = El.bound_w track in
        match w > 0. with
        | false -> ()
        | true ->
            let i = Float.to_int (Float.round (El.scroll_x track /. w)) in
            let i = max 0 (min (n - 1) i) in
            if i <> !index then show i)
  in
  (* Once laid out, the track starts at the focused photo. *)
  ignore
    (G.request_animation_frame (fun _ ->
         El.set_prop
           (El.Prop.float (Jstr.v "scrollLeft"))
           (Float.of_int start *. El.bound_w track)
           track));
  let close = round ~label:"Fermer" W.Icon.Close in
  let close_click, b_close = Rb.click close in
  {
    track;
    top = El.div ~at:[cls "viewer__top"] [close; counter; right];
    bindings =
      b_scroll
      :: b_close
      :: Rb.act close_click Route.back
      :: List.concat_map (fun (z : W.Viewer_zoom.t) -> z.bindings) zooms;
  }

let render app focus (d : data) =
  let n = List.length d.photos in
  let photos = Array.of_list d.photos in
  let start =
    List.find_index (fun (ph : Photo.t) -> Photo_id.equal ph.id !focus) d.photos
    |> Option.value ~default:0
  in
  focus := photos.(start).id;
  let badge = El.span ~at:[cls "viewer__badge"] [] in
  let cover_badge =
    El.span
      ~at:[cls "viewer__badge"; cls "viewer__badge--cover"]
      [El.txt' "Couverture"]
  in
  let when_el = El.p ~at:[cls "viewer__when"] [] in
  let missing =
    El.p
      ~at:[cls "t-meta"; cls "viewer__missing"]
      [El.txt' "original introuvable"]
  in
  (* An external link: Capacitor hands it to Android, which offers the Drive
     app when installed. *)
  let drive =
    El.a
      ~at:
        [
          cls "viewer__chip";
          At.v (Jstr.v "target") (Jstr.v "_blank");
          At.v (Jstr.v "rel") (Jstr.v "noopener noreferrer");
        ]
      [El.txt' "Ouvrir dans Google Drive ↗"]
  in
  let name =
    El.h2
      ~at:[cls "viewer__name"]
      [
        El.txt'
          (match d.plant with
          | Some p -> p.display_name
          | None -> "À identifier");
      ]
  in
  (* style: the slide in view, written by [show] (the frame's [on_show]) and
     read by the actions on the current photo. *)
  let index = ref start in
  let cover =
    Option.bind d.plant (fun p -> Cover.choose p.cover_photo_id d.photos)
    |> Option.map (fun (c : Photo.t) -> c.id)
  in
  let is_cover (ph : Photo.t) =
    Option.equal Photo_id.equal cover (Some ph.id)
  in
  let show i =
    index := i;
    let ph = photos.(i) in
    focus := ph.id;
    El.set_children badge [El.txt' (Drive_text.viewer_badge ph)];
    let show_drive href ~missing:is_missing =
      El.set_at At.Name.href (Option.map Jstr.v href) drive;
      El.set_class (Jstr.v "is-hidden") (Option.is_none href) drive;
      El.set_class (Jstr.v "is-hidden") (not is_missing) missing
    in
    (match Drive_text.viewer_drive ph with
    | Open file_id ->
        show_drive
          (Some (Herbier_photos.Drive.view_url ~file_id))
          ~missing:false
    | Missing -> show_drive None ~missing:true
    | Hidden -> show_drive None ~missing:false);
    El.set_class (Jstr.v "is-hidden") (not (is_cover ph)) cover_badge;
    El.set_children when_el
      [El.txt' (match obs_of d ph with Some o -> when_where o | None -> "")]
  in
  let see = chip "Voir l'observation" and remove = chip "Retirer d'Herbier" in
  let see_click, b_see = Rb.click see in
  let remove_click, b_remove = Rb.click remove in
  let confirm =
    W.Dialog.v ~title:"Retirer cette photo d'Herbier ?"
      ~text:
        "Elle quitte la fiche et l'observation. Un original envoyé dans Google \
         Drive y reste."
      [
        (W.Button.Danger, "Retirer", Remove);
        (W.Button.Secondary, "Garder", Keep);
      ]
  in
  (* Both actions need a plant: without one, no ⋯ at all. *)
  let actions =
    match d.plant with
    | None -> []
    | Some _ ->
        (W.Button.Secondary, "Définir comme couverture", Cover)
        ::
        (match d.observations with
        | _ :: _ :: _ ->
            [(W.Button.Secondary, "Déplacer vers une autre observation", Move)]
        | [] | [_] -> [])
  in
  let menu =
    W.Dialog.v ~title:"Photo"
      (actions @ [(W.Button.Secondary, "Annuler", Cancel)])
  in
  let more, b_more =
    match actions with
    | [] -> (El.span ~at:[cls "viewer__spacer"] [], [])
    | _ :: _ ->
        let b = round ~label:"Plus d'actions" W.Icon.More_horiz in
        let click, b_click = Rb.click b in
        (b, [b_click; Rb.act click menu.show])
  in
  let frame =
    frame ~n ~start
      ~slide:(fun i ->
        W.Preview_img.v ~cls:["viewer__img"]
          ~alt:(Printf.sprintf "Photo %d sur %d" (i + 1) n)
          photos.(i).preview_path)
      ~on_show:show ~right:more
  in
  let current () = photos.(!index) in
  (* Built once with every observation of the plant; [show_only] leaves out
     the one of the photo in view. *)
  let mover =
    W.Dialog.v ~title:"Déplacer vers…"
      ~text:"La photo rejoint cette observation de la plante."
      (List.map
         (fun o -> (W.Button.Secondary, when_where o, Some o))
         d.observations
      @ [(W.Button.Secondary, "Annuler", None)])
  in
  let save edits what =
    Fut.await (App.save app edits) (function
      | Error e -> log_error what e
      | Ok _ -> ())
  in
  let set_cover () =
    match d.plant with
    | None -> ()
    | Some p -> (
        let ph = current () in
        match Option.equal Photo_id.equal p.cover_photo_id (Some ph.id) with
        | true -> ()
        | false ->
            let at = Ptime_clock.now () in
            save
              [
                Plants.upsert
                  {p with cover_photo_id = Some ph.id; updated_at = at};
              ]
              "cover")
  in
  let move_to (o : Observation.t) =
    let ph = current () in
    match Observation_id.equal o.id ph.observation_id with
    | true -> ()
    | false ->
        let at = Ptime_clock.now () in
        save
          [Photos.upsert {ph with observation_id = o.id; updated_at = at}]
          "move"
  in
  let remove_current () =
    let ph = current () in
    (match n with
    | 1 -> ()
    | _ ->
        let next =
          match !index + 1 < n with true -> !index + 1 | false -> !index - 1
        in
        focus := photos.(next).id);
    let at = Ptime_clock.now () in
    let uncover =
      match d.plant with
      | Some p when Option.equal Photo_id.equal p.cover_photo_id (Some ph.id) ->
          [Plants.upsert {p with cover_photo_id = None; updated_at = at}]
      | Some _ | None -> []
    in
    Fut.await
      (App.save app (Photos.soft_delete ph.id ~at :: uncover))
      (function
        | Error e ->
            focus := ph.id;
            log_error "remove" e
        | Ok _ -> ( match n with 1 -> Route.back () | _ -> ()))
  in
  let el =
    El.div
      ~at:[cls "viewer__content"]
      [
        frame.track;
        frame.top;
        El.div
          ~at:[cls "viewer__bottom"]
          [
            El.div ~at:[cls "viewer__badges"] [badge; cover_badge];
            name;
            when_el;
            missing;
            El.div ~at:[cls "viewer__chips"] [see; drive; remove];
          ];
        confirm.el;
        menu.el;
        mover.el;
      ]
  in
  ( el,
    List.concat
      [
        frame.bindings;
        [
          b_see;
          b_remove;
          Rb.act see_click (fun () ->
              Route.go
                (Route.Modal (Route.Observation (current ()).observation_id)));
          Rb.act remove_click confirm.show;
          Rb.act confirm.choice (function
            | Remove -> remove_current ()
            | Keep -> ());
          Rb.act menu.choice (function
            | Cover -> set_cover ()
            | Move ->
                let own = (current ()).observation_id in
                mover.show_only (function
                  | Some (o : Observation.t) ->
                      not (Observation_id.equal o.id own)
                  | None -> true)
            | Cancel -> ());
          Rb.act mover.choice (function Some o -> move_to o | None -> ());
        ];
        b_more;
        confirm.bindings;
        menu.bindings;
        mover.bindings;
      ] )

let gone () =
  let back = W.Button.text ~tone:`Ink "Retour" in
  ( El.div
      [
        El.div ~at:[cls "modal-header"] [back.el];
        El.p
          ~at:[cls "t-body"]
          [El.txt' "Cette photo n'est plus dans l'herbier."];
      ],
    Rb.act back.click Route.back :: back.bindings )

let v app id =
  (* style: the photo in view, kept across reloads (after a cover change, a
     move or a removal). *)
  let focus = ref id in
  let el = El.div ~at:[cls "viewer"] [] in
  let item = function
    | None -> gone ()
    | Some {photos = []; _} -> gone ()
    | Some d -> render app focus d
  in
  {
    Screen.el;
    ready = Screen.now;
    bindings =
      Loaded.v ~reload:(App.saved app) ~what:"visionneuse" el
        (fun () -> load (App.db app) !focus)
        item;
  }

(* 5e read-only: the reference photos of 4f, no owner action. *)

let load_reference db plant =
  let open Fut.Result_syntax in
  let* p = Db.find db (Plants.get plant) in
  match p with
  | None -> Fut.ok []
  | Some (_ : Plant.t) ->
      let* references = Db.all db (References.of_plant plant) in
      let+ stored = Db.all db (Ref_images.of_plant plant) in
      Ref_photos.slides (Projection.project ~references ~plant_refs:[]) ~stored

(* The thumbnail at once (offline too); online, the full image over it once
   it has loaded, an error leaving the thumbnail. [full_url] is a checked
   bs.plantnet.org URL ({!Herbier_refs.Organ_photos.downloadable}). *)
let reference_slide ~online (s : Ref_photos.slide) =
  let thumb = W.Preview_img.v ~cls:["viewer__img"] ~alt:s.alt s.thumb_path in
  match online with
  | false -> (El.div ~at:[cls "viewer__ref"] [thumb], [])
  | true ->
      let full =
        El.img
          ~at:
            [
              cls "viewer__full";
              At.src (Jstr.v s.full_url);
              (* the thumbnail under it carries the text alternative *)
              At.v (Jstr.v "alt") Jstr.empty;
              At.v (Jstr.v "referrerpolicy") (Jstr.v "no-referrer");
            ]
          ()
      in
      ( El.div ~at:[cls "viewer__ref"] [thumb; full],
        [
          Rb.listen full Ev.load (fun _ ->
              El.set_class (Jstr.v "is-loaded") true full);
        ] )

let render_reference focus (online, (slides : Ref_photos.slide list)) =
  let n = List.length slides in
  let start = Ref_photos.start slides !focus in
  let slides = Array.of_list slides in
  let built = Array.map (reference_slide ~online) slides in
  let label = El.h2 ~at:[cls "viewer__name"] [] in
  let credit = El.p ~at:[cls "viewer__credit"] [] in
  let show i =
    let s = slides.(i) in
    focus := s.organ;
    El.set_children label [El.txt' s.label];
    El.set_children credit [El.txt' s.credit]
  in
  let frame =
    frame ~n ~start
      ~slide:(fun i -> fst built.(i))
      ~on_show:show
      ~right:(El.span ~at:[cls "viewer__spacer"] [])
  in
  ( El.div
      ~at:[cls "viewer__content"]
      [
        frame.track; frame.top; El.div ~at:[cls "viewer__bottom"] [label; credit];
      ],
    frame.bindings @ List.concat_map snd (Array.to_list built) )

let reference app plant organ =
  (* style: the organ in view, kept across reloads (a thumbnail sync). *)
  let focus = ref organ in
  let el = El.div ~at:[cls "viewer"] [] in
  let item = function
    | _, [] -> gone ()
    | shown -> render_reference focus shown
  in
  let network = State.network (App.state app) in
  let online () = (React.S.value network).online in
  (* Online again: the full images can load now. *)
  let back_online =
    React.S.changes
      (React.S.map ~eq:Bool.equal (fun (n : State.network) -> n.online) network)
    |> React.E.fmap (function true -> Some () | false -> None)
  in
  (* A save that changes none of the slides (another plant's fetch) keeps the
     rendering, its zoom and its loaded images; so does going offline (what
     has loaded stays). Only coming back online renders the full images. *)
  let eq (shown_online, shown) (online, slides) =
    (shown_online || not online)
    && List.equal Ref_photos.equal_slide shown slides
  in
  {
    Screen.el;
    ready = Screen.now;
    bindings =
      Loaded.v ~eq
        ~reload:(React.E.select [App.saved app; back_online])
        ~failed:gone ~what:"visionneuse" el
        (fun () ->
          Fut.map
            (Result.map (fun slides -> (online (), slides)))
            (load_reference (App.db app) plant))
        item;
  }
