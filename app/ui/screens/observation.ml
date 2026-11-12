open Brr
module Db = Herbier_store.Db
module Plants = Herbier_store.Plants
module Observations = Herbier_store.Observations
module Photos = Herbier_store.Photos
module Observation = Herbier_domain.Observation
module Plant = Herbier_domain.Plant
module Features = Herbier_geo.Features
module W = Widgets

let cls c = At.class' (Jstr.v c)

let log_error what e =
  Console.(error [str ("observation: " ^ what); str (Db.error_to_string e)])

type data = {
  observation : Observation.t;
  plant : Plant.t option;  (** [None]: « À identifier », or a deleted plant *)
  photos : Herbier_domain.Photo.t list;
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

let day_time t = Fr_date.day_time ~tz_offset_s:(Zone.offset_s t) t

(* The accuracy is never written: the mini-map's circle is its only
   representation (handoff 4h, architecture §8). *)
let coordinates p = Herbier_domain.Places.(point_text (of_position p))

let place (o : Observation.t) =
  let name = Herbier_domain.Places.place_name o in
  match (name, o.position) with
  | None, None ->
      [El.p ~at:[cls "t-meta"] [El.txt' "Pas de position enregistrée."]]
  | _ ->
      List.concat
        [
          Option.to_list
            (Option.map
               (fun n -> El.p ~at:[cls "observation__value"] [El.txt' n])
               name);
          Option.to_list
            (Option.map
               (fun p -> El.p ~at:[cls "t-meta"] [El.txt' (coordinates p)])
               o.position);
        ]

(* The plant's name and where tapping it goes. *)
let title (d : data) =
  match (d.observation.plant_id, d.plant) with
  | Some _, Some p -> (p.display_name ^ " ›", Some (Route.Plant p.id))
  | Some _, None -> ("Plante supprimée", None)
  | None, _ -> ("À identifier ›", Some (Route.Identify d.observation.id))

let action ?(tone = `Plain) label =
  let el =
    El.button
      ~at:
        (At.type' (Jstr.v "button")
        :: cls "observation__action"
        ::
        (match tone with
        | `Danger -> [cls "observation__action--danger"]
        | `Plain -> []))
      []
  in
  let click, b = Rb.click el in
  (el, click, [b; Rb.text el label])

let card label children =
  W.Card.panel (El.h2 ~at:[cls "t-section-label"] [El.txt' label] :: children)

type delete = Delete | Keep

let delete_dialog n =
  W.Dialog.v ~title:"Supprimer cette observation ?"
    ~text:
      (match n with
      | 0 -> "Elle quitte l'herbier et le journal."
      | n ->
          Printf.sprintf
            "Elle quitte l'herbier avec ses %s. Les originaux envoyés dans \
             Google Drive y restent."
            (Fr_text.plural n "photo" "photos"))
    [
      (W.Button.Danger, "Supprimer", Delete);
      (W.Button.Secondary, "Garder", Keep);
    ]

let render app (data : data React.signal) =
  let get () = React.S.value data in
  let id = (get ()).observation.id in
  let problem_text, problem = React.S.create ~eq:String.equal "" in
  let problem_el = El.p ~at:[cls "t-meta"; cls "observation__problem"] [] in
  (* style: [current] is the observation as this screen last wrote or read
     it, so that an edit made before the reload of the previous one builds on
     it rather than on the row the screen was given. Written by [store] and by
     reloads that bring a row at least as recent. *)
  let current = ref (get ()).observation in
  let b_current =
    Rb.on (React.S.changes data) (fun d ->
        match
          Ptime.is_earlier d.observation.updated_at ~than:!current.updated_at
        with
        | true -> ()
        | false -> current := d.observation)
  in
  (* Saves [f] of the current observation; [false] (and a line on screen)
     when the save failed. *)
  let store f what failure =
    let next =
      {(f !current) with Observation.updated_at = Ptime_clock.now ()}
    in
    current := next;
    Fut.map
      (function
        | Error e ->
            log_error what e;
            problem failure;
            false
        | Ok _ ->
            problem "";
            true)
      (App.save app [Observations.upsert next])
  in
  let back =
    El.button
      ~at:
        [
          At.type' (Jstr.v "button");
          cls "icon-button";
          At.v (Jstr.v "aria-label") (Jstr.v "Retour");
        ]
      [W.Icon.el W.Icon.Arrow_back]
  in
  let back_click, b_back = Rb.click back in
  let done_ = W.Button.text "Terminé" in
  let title_el =
    El.button ~at:[At.type' (Jstr.v "button"); cls "observation__plant"] []
  in
  let title_click, b_title = Rb.click title_el in
  let header =
    El.div
      ~at:[cls "modal-header"]
      [
        back;
        El.div
          ~at:[cls "modal-header__title"; cls "observation__title"]
          [
            El.span ~at:[cls "t-section-label"] [El.txt' "Observation"]; title_el;
          ];
        done_.el;
      ]
  in
  (* [adding] keeps a second tap on « + » from picking again while a pick and
     its save run, the picker's decoding included. *)
  let adding, set_adding = React.S.create ~eq:Bool.equal false in
  let add_photos () =
    match React.S.value adding with
    | true -> ()
    | false ->
        set_adding true;
        Fut.await (Herbier_photos.Capture.pick ~limit:10) (function
          | Error e ->
              set_adding false;
              Console.(
                error
                  [
                    str "observation: gallery";
                    str (Herbier_photos.Capture.error_to_string e);
                  ]);
              problem "Les photos n'ont pas pu être lues."
          | Ok shots ->
              Fut.await (App.save_photos app ~observation:!current shots)
                (fun failed ->
                  set_adding false;
                  match failed with
                  | [] -> problem ""
                  | _ :: _ ->
                      problem
                        (Fr_text.plural (List.length failed)
                           "photo non enregistrée" "photos non enregistrées")))
  in
  let mosaic (photos : Herbier_domain.Photo.t list) =
    let add =
      El.button
        ~at:
          [
            At.type' (Jstr.v "button");
            cls "observation__add";
            At.v (Jstr.v "aria-label") (Jstr.v "Ajouter des photos");
          ]
        [W.Icon.el W.Icon.Add]
    in
    let add_click, b_add = Rb.click add in
    let busy =
      Rb.attr add "aria-busy"
        (React.S.map (function true -> Some "true" | false -> None) adding)
    in
    (* Each tile with the listener that opens it in the viewer. *)
    let tile ~cls (ph : Herbier_domain.Photo.t) =
      let t = W.Photo_grid.tile ~cls ph in
      ( t,
        Rb.listen t Ev.click (fun _ ->
            Route.go (Route.Modal (Route.Viewer ph.id))) )
    in
    let el, tiles =
      match photos with
      | [] ->
          ( El.div
              ~at:[cls "observation__mosaic"; cls "observation__mosaic--empty"]
              [add],
            [] )
      | first :: rest ->
          let large, b_large = tile ~cls:"observation__large" first in
          let more =
            match rest with
            | [] -> []
            | second :: others ->
                let t, b = tile ~cls:"observation__small" second in
                (match others with
                | [] -> ()
                | _ ->
                    El.append_children t
                      [
                        El.span
                          ~at:[cls "observation__more"]
                          [El.txt' (Printf.sprintf "+%d" (List.length others))];
                      ]);
                [(t, b)]
          in
          ( El.div
              ~at:[cls "observation__mosaic"]
              [
                large;
                El.div
                  ~at:[cls "observation__column"]
                  (List.map fst more @ [add]);
              ],
            b_large :: List.map snd more )
    in
    (el, b_add :: busy :: Rb.act add_click add_photos :: tiles)
  in
  let mosaic_el = El.div [] in
  let modify = W.Button.text "Modifier" in
  let date_value = El.span ~at:[cls "observation__value"] [] in
  let date_input =
    El.input
      ~at:
        [
          At.type' (Jstr.v "datetime-local");
          cls "observation__date-input";
          cls "is-hidden";
          At.v (Jstr.v "aria-label") (Jstr.v "Date et heure");
        ]
      ()
  in
  let show_input on = El.set_class (Jstr.v "is-hidden") (not on) date_input in
  let b_date =
    Rb.listen date_input Ev.change (fun _ ->
        let v = Jstr.to_string (El.prop El.Prop.value date_input) in
        match Local_time.of_input ~offset:Zone.offset_s v with
        | Some at when not (Ptime.equal at !current.at) ->
            Fut.await
              (store
                 (fun o -> {o with at})
                 "date" "La date n'a pas pu être enregistrée.")
              (function true -> show_input false | false -> ())
        | Some _ | None -> ())
  in
  let date_card =
    card "Date"
      [El.div ~at:[cls "observation__line"] [date_value; modify.el]; date_input]
  in
  let place_el = El.div ~at:[cls "observation__place-text"] [] in
  (* Built once per rendering, outside [place_el]'s rebuilds: a note or date
     save moves the point instead of recreating the map. *)
  let mini_map =
    match App.theme app with
    | Error (Theme.Missing_tokens missing) ->
        Console.(
          error
            [str "observation: mini-carte"; str (String.concat ", " missing)]);
        None
    | Ok theme ->
        Some
          (W.Mini_map.v ~colours:theme.map
             (React.S.map ~eq:( == ) (fun d -> d.observation.position) data))
  in
  let move_el =
    El.button
      ~at:
        [
          At.type' (Jstr.v "button");
          cls "text-button";
          cls "text-button--moss";
          cls "observation__move";
        ]
      []
  in
  let move_click, b_move = Rb.click move_el in
  let open_map () =
    Option.iter (State.focus_map (App.state app)) (Features.bounds [!current]);
    Route.go (Route.Tab W.Tab_bar.Map)
  in
  let note =
    W.Inline_text.v ~cls:"t-notes" ~label:"Note de cette rencontre"
      ~placeholder:"Touchez pour ajouter une note."
      ~save:(fun text ->
        let note = match text with "" -> None | t -> Some t in
        store
          (fun o -> {o with note})
          "note" "La note n'a pas pu être enregistrée.")
      (React.S.map ~eq:String.equal
         (fun d -> Option.value d.observation.note ~default:"")
         data)
  in
  let change_el, change_click, b_change =
    action
      (React.S.map
         (fun d ->
           match d.observation.plant_id with
           | Some _ -> "Changer d'espèce ›"
           | None -> "Identifier ›")
         data)
  in
  let journal_el, journal_click, b_journal =
    action (React.S.const "Voir dans le journal ›")
  in
  let delete_el, delete_click, b_delete =
    action ~tone:`Danger (React.S.const "Supprimer l'observation ›")
  in
  let delete () =
    let at = Ptime_clock.now () in
    let photos =
      List.map (fun (p : Herbier_domain.Photo.t) -> p.id) (get ()).photos
    in
    Fut.await
      (App.save app (Herbier_store.Cascade.observation ~at ~photos id))
      (function
        | Error e ->
            log_error "delete" e;
            problem "L'observation n'a pas pu être supprimée."
        | Ok _ -> Route.back ())
  in
  (* The dialog's text counts the photos: built again when their number
     changes. *)
  let confirm_el = El.div [] in
  let confirm n =
    let c = delete_dialog n in
    ( c.el,
      Rb.act delete_click c.show
      :: Rb.act c.choice (function Delete -> delete () | Keep -> ())
      :: c.bindings )
  in
  let el =
    El.div
      ~at:[cls "observation__content"]
      [
        header;
        problem_el;
        mosaic_el;
        date_card;
        El.div
          ~at:[cls "observation__place"]
          [
            W.Card.panel
              (let line =
                 El.div ~at:[cls "observation__line"] [place_el; move_el]
               in
               match mini_map with Some m -> [m.el; line] | None -> [line]);
          ];
        card "Note de cette rencontre" [note.el];
        El.div
          ~at:[cls "observation__actions"]
          [change_el; journal_el; delete_el];
        confirm_el;
      ]
  in
  ( el,
    List.concat
      [
        [
          b_current;
          b_back;
          Rb.view mosaic_el mosaic
            (React.S.map ~eq:( == ) (fun d -> d.photos) data);
          b_title;
          b_date;
          Rb.act back_click Route.back;
          Rb.act done_.click Route.back;
          Rb.text title_el (React.S.map (fun d -> fst (title d)) data);
          Rb.class_ title_el "observation__plant--to-identify"
            (React.S.map (fun d -> Option.is_none d.observation.plant_id) data);
          Rb.act title_click (fun () ->
              Option.iter
                (fun r -> Route.go (Route.Modal r))
                (snd (title (get ()))));
          Rb.text date_value
            (React.S.map (fun d -> day_time d.observation.at) data);
          Rb.children place_el
            (React.S.map ~eq:( == ) (fun d -> place d.observation) data);
          b_move;
          Rb.text move_el
            (React.S.map
               (fun d ->
                 match d.observation.position with
                 | Some _ -> "Déplacer"
                 | None -> "Placer sur la carte")
               data);
          Rb.act move_click (fun () ->
              Route.go (Route.Modal (Route.Move_point id)));
          Rb.act modify.click (fun () ->
              let at = !current.at in
              El.set_prop El.Prop.value
                (Jstr.v
                   (Local_time.to_input ~tz_offset_s:(Zone.offset_s at) at))
                date_input;
              show_input true;
              El.set_has_focus true date_input);
          Rb.act change_click (fun () ->
              Route.go
                (Route.Modal
                   (match !current.plant_id with
                   | Some _ -> Route.Change_species id
                   | None -> Route.Identify id)));
          Rb.act journal_click (fun () ->
              Route.go (Route.Tab W.Tab_bar.Journal));
          Rb.view confirm_el confirm
            (React.S.map ~eq:Int.equal (fun d -> List.length d.photos) data);
          Rb.text problem_el problem_text;
          Rb.class_ problem_el "is-hidden"
            (React.S.map (String.equal "") problem_text);
        ];
        (match mini_map with
        | None -> []
        | Some m -> Rb.act m.tap open_map :: m.bindings);
        b_change;
        b_journal;
        b_delete;
        done_.bindings;
        modify.bindings;
        note.bindings;
      ] )

let v app id =
  let el = El.div ~at:[cls "screen"; cls "observation"] [] in
  {
    Screen.el;
    bindings =
      Loaded.live ~reload:(App.saved app) ~what:"observation"
        ~gone:(fun () ->
          Loaded.notice "Cette observation n'est plus dans l'herbier.")
        ~failed:(fun () -> Loaded.notice "L'observation n'a pas pu être lue.")
        el
        (fun () -> load (App.db app) id)
        (render app);
  }
