module Fr_date = Herbier_ui_model.Fr_date
module Fr_text = Herbier_ui_model.Fr_text
module Drive_text = Herbier_ui_model.Drive_text
open Brr
module Db = Herbier_store_io.Db
module Plants = Herbier_store.Plants
module Observations = Herbier_store.Observations
module Photos = Herbier_store.Photos
module Observation = Herbier_domain.Observation
module Photo = Herbier_domain.Photo
module Plant = Herbier_domain.Plant
module W = Widgets

let cls = Html.cls

type data = {
  observation : Observation.t;
  plant : Plant.t option;
  photos : Photo.t list;
}

let load db id =
  let open Fut.Result_syntax in
  let* o = Db.find db (Observations.get id) in
  match o with
  | None -> Fut.ok None
  | Some (o : Observation.t) ->
      let* plant =
        match o.plant_id with
        | Some p -> Db.find db (Plants.get p)
        | None -> Fut.ok None
      in
      let+ photos = Db.all db (Photos.of_observation id) in
      Some {observation = o; plant; photos}

(* The Drive card follows the access, the network and the queue without a
   reload; the photos, and so whether there is a card, come with each
   reload. *)
let drive_card app (photos : Photo.t list) =
  match Drive_text.has_drive_photo photos with
  | false -> ([], [])
  | true ->
      let state = App.state app in
      let card =
        React.S.l4
          ~eq:(Option.equal Drive_text.equal_card)
          (fun access (n : State.network) (a : State.account)
               (q : Drive_text.queue) ->
            Drive_text.saved_card access ~online:n.online ~wifi_only:a.wifi_only
              ~queued:q.queued photos)
          (App.drive_access app) (State.network state) (State.account state)
          (App.upload_queue app)
      in
      let title = El.p ~at:[cls "saved__card-title"] [] in
      let detail = El.p ~at:[cls "t-meta"] [] in
      let text f =
        React.S.map ~eq:String.equal
          (function Some c -> f c | None -> "")
          card
      in
      ( [W.Card.panel [title; detail]],
        [
          Rb.text title (text (fun (c : Drive_text.card) -> c.title));
          Rb.text detail (text (fun (c : Drive_text.card) -> c.detail));
        ] )

let render app (d : data) =
  let o = d.observation in
  let tz_offset_s = Zone.offset_s o.at in
  let where =
    List.concat
      [
        Option.to_list (Herbier_domain.Places.display_name o);
        Option.to_list
          (Option.map
             (fun p -> Herbier_domain.Places.(point_text (of_position p)))
             o.position);
        [
          (let now = Ptime_clock.now () in
           let now_offset_s = Zone.offset_s now in
           let day = Fr_date.local_date ~tz_offset_s o.at in
           match day = Fr_date.local_date ~tz_offset_s:now_offset_s now with
           | true -> Fr_date.time ~tz_offset_s o.at
           | false ->
               Fr_date.day_header
                 ~this_year:(Fr_date.year ~tz_offset_s:now_offset_s now)
                 day
               ^ " "
               ^ Fr_date.time ~tz_offset_s o.at);
        ];
      ]
  in
  let added =
    match d.plant with
    | Some p ->
        [El.txt' "Observation ajoutée à "; El.strong [El.txt' p.display_name]]
    | None -> [El.txt' "Observation à identifier"]
  in
  let thumb (p : Photo.t) =
    let box = W.Preview_img.v ~cls:["saved__thumb"] p.preview_path in
    (match Photo.awaiting_drive p with
    | true ->
        El.append_children box
          [El.span ~at:[cls "badge-pending"] [El.txt' "↑ en attente"]]
    | false -> ());
    box
  in
  let app_only =
    List.length
      (List.filter
         (fun (p : Photo.t) ->
           match p.original_target with Drive -> false | App_only -> true)
         d.photos)
  in
  let card title meta =
    W.Card.panel
      [
        El.p ~at:[cls "saved__card-title"] [El.txt' title];
        El.p ~at:[cls "t-meta"] [El.txt' meta];
      ]
  in
  let drive_cards, drive_b = drive_card app d.photos in
  let where_cards =
    List.concat
      [
        drive_cards;
        (match app_only with
        | 0 -> []
        | n ->
            [
              card
                (Fr_text.plural n "photo gardée" "photos gardées"
                ^ " dans Herbier")
                (Printf.sprintf
                   "Compressées à %d px, sur le téléphone seulement."
                   Herbier_photos.Preview_size.max_side);
            ]);
      ]
  in
  let note_row =
    Html.button ["saved__action"]
      [
        El.span [El.txt' "Ajouter une note à cette observation"];
        El.span ~at:[cls "saved__chevron"] [El.txt' "›"];
      ]
  in
  let note_click, b_note = Rb.click note_row in
  let move_row =
    Html.button ["saved__action"]
      [
        El.span [El.txt' "Corriger la position sur la carte"];
        El.span ~at:[cls "saved__chevron"] [El.txt' "›"];
      ]
  in
  let move_click, b_move = Rb.click move_row in
  let again = W.Button.v ~icon:W.Icon.Add "Noter une autre plante" in
  let fiche =
    match d.plant with
    | Some p ->
        Some
          ( p,
            W.Button.v ~kind:W.Button.Secondary
              ("Voir la fiche " ^ p.display_name) )
    | None -> None
  in
  let close = W.Icon_button.el ~label:"Fermer" W.Icon.Close in
  let close_click, b_close = Rb.click close in
  let el =
    El.div
      ~at:[cls "saved__content"]
      (List.concat
         [
           [
             El.div ~at:[cls "modal-header"] [close];
             El.div
               ~at:[cls "saved__summary"]
               [
                 El.div
                   ~at:[cls "saved__check"]
                   [W.Icon.el ~size:36 W.Icon.Check];
                 El.h1 ~at:[cls "saved__title"] [El.txt' "Enregistré"];
                 El.p ~at:[cls "t-body"] added;
                 El.p ~at:[cls "t-meta"] [El.txt' (String.concat " · " where)];
               ];
             El.div ~at:[cls "saved__thumbs"] (List.map thumb d.photos);
           ];
           where_cards;
           [note_row; move_row; El.div ~at:[cls "saved__spacer"] []; again.el];
           (match fiche with Some (_, b) -> [b.el] | None -> []);
         ])
  in
  ( el,
    List.concat
      [
        [
          b_note;
          b_move;
          b_close;
          Rb.act close_click Route.back;
          Rb.act note_click (fun () ->
              Route.replace (Route.Modal (Route.Observation o.id)));
          (* [go], not [replace]: back from 5b returns here, rebuilt with the
             new coordinates. *)
          Rb.act move_click (fun () ->
              Route.go (Route.Modal (Route.Move_point o.id)));
          Rb.act again.click (fun () ->
              Route.replace (Route.Modal Route.Record));
        ];
        again.bindings;
        drive_b;
        (match fiche with
        | Some (p, b) ->
            Rb.act b.click (fun () ->
                Route.replace (Route.Modal (Route.Plant p.id)))
            :: b.bindings
        | None -> []);
      ] )

let gone () =
  let back = W.Button.text ~tone:`Ink "Retour" in
  ( El.div
      [
        El.div ~at:[cls "modal-header"] [back.el];
        El.p
          ~at:[cls "t-body"]
          [El.txt' "Cette observation n'est plus dans l'herbier."];
      ],
    Rb.act back.click Route.back :: back.bindings )

let v app id =
  let el = El.div ~at:[cls "screen"; cls "saved"] [] in
  let item = function None -> gone () | Some d -> render app d in
  {
    Screen.el;
    ready = Screen.now;
    bindings =
      Loaded.v ~reload:(App.saved app) ~what:"enregistré" el
        (fun () -> load (App.db app) id)
        item;
  }
