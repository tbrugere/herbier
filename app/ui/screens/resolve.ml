open Brr
module Db = Herbier_store.Db
module Plants = Herbier_store.Plants
module Tags = Herbier_store.Tags
module Search = Herbier_store.Search
module Observations = Herbier_store.Observations
module Observation = Herbier_domain.Observation
module Plant = Herbier_domain.Plant
module Plant_id = Herbier_domain.Ids.Plant_id
module RList = ReactiveData.RList
module W = Widgets

type mode = Identify | Change

let cls c = At.class' (Jstr.v c)

let log_error what e =
  Console.(error [str ("identifier: " ^ what); str (Db.error_to_string e)])

type data = {
  observation : Observation.t;
  current : Plant.t option;  (** [None]: « À identifier », or a deleted plant *)
  unidentified : Observation.t list;  (** newest first *)
}

let load db id =
  let open Fut.Result_syntax in
  let* o = Db.find db (Observations.get id) in
  match o with
  | None -> Fut.ok None
  | Some (o : Observation.t) ->
      let* current =
        match o.plant_id with
        | None -> Fut.ok None
        | Some p -> Db.find db (Plants.get p)
      in
      let+ unidentified = Db.all db Observations.unidentified in
      Some {observation = o; current; unidentified}

let observation_card (o : Observation.t) =
  W.Card.panel
    (List.concat
       [
         [
           El.p
             ~at:[cls "resolve__obs-date"]
             [El.txt' (Fr_date.day_time ~tz_offset_s:(Zone.offset_s o.at) o.at)];
         ];
         Option.to_list
           (Option.map
              (fun p -> El.p ~at:[cls "t-meta"] [El.txt' p])
              (Journal_day.place [o]));
         Option.to_list
           (Option.map
              (fun n ->
                El.p ~at:[cls "resolve__note"] [El.txt' ("« " ^ n ^ " »")])
              o.note);
       ])

let apply handle =
  List.iter (function
    | List_patch.Remove i -> RList.remove i handle
    | List_patch.Insert (i, v) -> RList.insert v i handle
    | List_patch.Update (i, v) -> RList.update v i handle)

let same (a : Plant.t) (b : Plant.t) = Plant_id.equal a.id b.id

let equal (a : Plant.t) (b : Plant.t) =
  same a b && Ptime.equal a.updated_at b.updated_at

type orphan = Keep_plant | Delete_plant

let orphan_dialog (p : Plant.t) =
  W.Dialog.v ~title:"Garder la fiche ?"
    ~text:(Printf.sprintf "« %s » n'a plus d'observation." p.display_name)
    [
      (W.Button.Secondary, "Garder la fiche", Keep_plant);
      (W.Button.Danger, "Supprimer la fiche", Delete_plant);
    ]

let render app mode (d : data) =
  let db = App.db app in
  let o = d.observation in
  let problem_text, problem = React.S.create ~eq:String.equal "" in
  let problem_el = El.p ~at:[cls "t-meta"; cls "resolve__problem"] [] in
  let position = To_identify.position o d.unidentified in
  let go_next () =
    match position with
    | Some {next = Some n; _} ->
        Route.replace (Route.Modal (Route.Identify n.id))
    | Some {next = None; _} | None -> Route.back ()
  in
  let finish () =
    match mode with Change -> Route.back () | Identify -> go_next ()
  in
  (* The plant the observation leaves, with the dialog asked when it has no
     observation left. *)
  let left = Option.map (fun p -> (p, orphan_dialog p)) d.current in
  let delete_orphan (p : Plant.t) =
    let at = Ptime_clock.now () in
    (* A plant that could not be deleted is kept, as « Garder la fiche »
       would. *)
    Fut.await
      (Db.all db (Tags.of_plant p.id))
      (function
        | Error e ->
            log_error "orphan tags" e;
            finish ()
        | Ok tags ->
            Fut.await
              (App.save app
                 (Herbier_store.Cascade.plant ~at ~photos:[] ~observations:[]
                    ~tags:
                      (List.map (fun (t : Herbier_domain.Tag.t) -> t.id) tags)
                    p.id))
              (function
                | Error e ->
                    log_error "orphan" e;
                    finish ()
                | Ok _ -> finish ()))
  in
  (* Read once the observation has moved: it no longer counts. *)
  let after_move () =
    match left with
    | None -> finish ()
    | Some (p, dialog) ->
        Fut.await
          (Db.all db (Observations.of_plant p.id))
          (function
            | Ok [] -> dialog.show ()
            | Ok (_ :: _) -> finish ()
            | Error e ->
                log_error "orphan check" e;
                finish ())
  in
  (* style: [busy] keeps a second tap from moving the observation again
     while the first move is saved and the screen leaves; written by [move]
     and its save's callback, outside any reaction. *)
  let busy = ref false in
  (* [extra] goes first: a new plant must exist before the observation's
     plant_id references it. *)
  let move ?(extra = []) target =
    match !busy with
    | true -> ()
    | false ->
        busy := true;
        let at = Ptime_clock.now () in
        let edits =
          extra
          @ [Observations.upsert {o with plant_id = target; updated_at = at}]
        in
        Fut.await (App.save app edits) (function
          | Error e ->
              busy := false;
              log_error "link" e;
              problem "L'observation n'a pas pu être déplacée."
          | Ok _ -> after_move ())
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
  let next = W.Button.text "Suivante ›" in
  let title, right =
    match mode with
    | Identify -> (
        let label =
          match position with
          | Some p -> Printf.sprintf "À identifier · %d / %d" p.index p.total
          | None -> "À identifier"
        in
        ( [
            El.span
              ~at:[cls "t-section-label"; cls "resolve__ochre"]
              [El.txt' label];
          ],
          match position with
          | Some {next = Some _; _} -> next.el
          | Some {next = None; _} | None -> El.span [] ))
    | Change ->
        ( [
            El.span ~at:[cls "t-section-label"] [El.txt' "Changer d'espèce"];
            El.span
              ~at:[cls "resolve__subtitle"]
              [El.txt' ("Observation du " ^ Fr_date.day_month (Zone.date o.at))];
          ],
          El.span [] )
  in
  let header =
    El.div
      ~at:[cls "modal-header"]
      [
        back;
        El.div ~at:[cls "modal-header__title"; cls "resolve__title"] title;
        right;
      ]
  in
  let top =
    match mode with
    | Identify -> observation_card o
    | Change ->
        W.Card.panel
          [
            El.p
              [
                El.txt' "Actuellement ";
                El.strong
                  [
                    El.txt'
                      (match (o.plant_id, d.current) with
                      | Some _, Some p -> p.display_name
                      | Some _, None -> "Plante supprimée"
                      | None, _ -> "À identifier");
                  ];
              ];
            El.p
              ~at:[cls "t-meta"]
              [El.txt' "Les photos et la note suivent l'observation."];
          ]
  in
  let search =
    W.Text_field.v ~icon:W.Icon.Search
      ~placeholder:"Chercher dans ma collection" ()
  in
  let rows, rows_handle = RList.create [] in
  (* [None] until the first result. *)
  let found, set_found = React.S.create None in
  let is_current (p : Plant.t) =
    match d.current with Some c -> Plant_id.equal c.id p.id | None -> false
  in
  let row (p : Plant.t) =
    let r =
      W.List_row.v ~thumb:W.List_row.Placeholder ~title:p.display_name
        ~meta:(Option.value p.scientific_name ~default:"nom libre")
        ()
    in
    El.set_class (Jstr.v "is-current") (is_current p) r.el;
    ( r.el,
      Rb.act r.click (fun () ->
          match is_current p with true -> () | false -> move (Some p.id))
      :: r.bindings )
  in
  (* style: [shown] is the rows' current content and [seq] numbers the
     queries; read and written from future callbacks and [refresh] only
     (outside update steps). *)
  let shown = ref [] and seq = ref 0 in
  let refresh () =
    incr seq;
    let mine = !seq in
    Fut.await
      (Db.all db (Search.plants_or_all (React.S.value search.value)))
      (function
        | Error e when mine = !seq ->
            log_error "search" e;
            problem "La recherche n'a pas pu se faire."
        | Ok next when mine = !seq ->
            apply rows_handle (List_patch.diff ~same ~equal !shown next);
            shown := next;
            set_found (Some (List.length next))
        | Error _ | Ok _ -> ())
  in
  refresh ();
  let count = El.span [] in
  let empty =
    El.p ~at:[cls "t-meta"] [El.txt' "Aucune plante ne correspond."]
  in
  let rows_el = El.div ~at:[cls "resolve__rows"] [] in
  let free = W.Button.v ~kind:W.Button.Secondary "Nom libre" in
  let blank =
    React.S.map ~eq:Bool.equal
      (fun t -> String.equal (String.trim t) "")
      search.value
  in
  let free_name () =
    match String.trim (React.S.value search.value) with
    | "" -> El.set_has_focus true search.input
    | name ->
        let plant =
          Plant.v ~id:(Plant_id.fresh ()) ~at:(Ptime_clock.now ()) name
        in
        move ~extra:[Plants.upsert plant] (Some plant.id)
  in
  let free_hint = El.p ~at:[cls "t-meta"] [] in
  let paste = W.Button.v ~kind:W.Button.Secondary "Coller un lien" in
  El.set_at (Jstr.v "aria-disabled") (Some (Jstr.v "true")) paste.el;
  let unlink = W.Button.v ~kind:W.Button.Secondary "Remettre “À identifier”" in
  El.set_class (Jstr.v "button--ochre") true unlink.el;
  let footer =
    match mode with
    | Identify ->
        [El.div ~at:[cls "resolve__footer"] [paste.el; free.el]; free_hint]
    | Change ->
        [
          El.div ~at:[cls "resolve__footer"] [free.el];
          free_hint;
          (match o.plant_id with Some _ -> unlink.el | None -> El.span []);
        ]
  in
  let el =
    El.div
      ~at:[cls "resolve__content"]
      ([
         header;
         problem_el;
         top;
         search.el;
         El.h2
           ~at:[cls "t-section-label"]
           [El.txt' "Dans ma collection · "; count];
         rows_el;
         empty;
       ]
      @ footer
      @ Option.to_list
          (Option.map (fun (_, (dialog : orphan W.Dialog.t)) -> dialog.el) left)
      )
  in
  ( el,
    List.concat
      [
        [
          b_back;
          Rb.act back_click Route.back;
          Rb.act next.click go_next;
          Rb.rlist rows_el row rows;
          Rb.act (React.S.changes search.value) (fun _ -> refresh ());
          Rb.text count
            (React.S.map
               (function None -> "…" | Some n -> string_of_int n)
               found);
          Rb.class_ empty "is-hidden"
            (React.S.map
               (function Some 0 -> false | Some _ | None -> true)
               found);
          Rb.act free.click free_name;
          Rb.text free_hint
            (React.S.map
               (fun t ->
                 match String.trim t with
                 | "" -> "« Nom libre » crée une fiche avec le texte cherché."
                 | n -> Printf.sprintf "« Nom libre » crée la fiche « %s »." n)
               search.value);
          Rb.class_ free.el "is-inactive" blank;
          Rb.act unlink.click (fun () -> move None);
          Rb.text problem_el problem_text;
          Rb.class_ problem_el "is-hidden"
            (React.S.map (String.equal "") problem_text);
        ];
        (match left with
        | None -> []
        | Some (p, dialog) ->
            Rb.act dialog.choice (function
              | Delete_plant -> delete_orphan p
              | Keep_plant -> finish ())
            :: dialog.bindings);
        next.bindings;
        search.bindings;
        free.bindings;
        paste.bindings;
        unlink.bindings;
      ] )

let v app mode id =
  let el = El.div ~at:[cls "screen"; cls "resolve"] [] in
  let item = function
    | None -> Loaded.notice "Cette observation n'est plus dans l'herbier."
    | Some d -> render app mode d
  in
  {
    Screen.el;
    bindings =
      Loaded.v ~what:"identifier"
        ~failed:(fun () -> Loaded.notice "L'observation n'a pas pu être lue.")
        el
        (fun () -> load (App.db app) id)
        item;
  }
