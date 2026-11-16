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

let render app focus (d : data) =
  let n = List.length d.photos in
  let photos = Array.of_list d.photos in
  let start =
    List.find_index (fun (ph : Photo.t) -> Photo_id.equal ph.id !focus) d.photos
    |> Option.value ~default:0
  in
  focus := photos.(start).id;
  let zooms =
    List.mapi
      (fun i (ph : Photo.t) ->
        W.Viewer_zoom.v
          (W.Preview_img.v ~cls:["viewer__img"]
             ~alt:(Printf.sprintf "Photo %d sur %d" (i + 1) n)
             ph.preview_path))
      d.photos
  in
  let track =
    El.div
      ~at:[cls "viewer__track"]
      (List.map
         (fun (z : W.Viewer_zoom.t) -> El.div ~at:[cls "viewer__slide"] [z.el])
         zooms)
  in
  let counter = El.span ~at:[cls "viewer__counter"] [] in
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
  (* style: the slide in view, written by [show] (from the scroll listener)
     and read by the actions on the current photo. *)
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
    El.set_children counter [El.txt' (Printf.sprintf "%d / %d" (i + 1) n)];
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
      [El.txt' (match obs_of d ph with Some o -> when_where o | None -> "")];
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
  let see = chip "Voir l'observation" and remove = chip "Retirer d'Herbier" in
  let close_click, b_close = Rb.click close in
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
        track;
        El.div ~at:[cls "viewer__top"] [close; counter; more];
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
        [
          b_scroll;
          b_close;
          b_see;
          b_remove;
          Rb.act close_click Route.back;
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
        List.concat_map (fun (z : W.Viewer_zoom.t) -> z.bindings) zooms;
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
