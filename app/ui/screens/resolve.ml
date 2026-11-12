open Brr
module Db = Herbier_store.Db
module Plants = Herbier_store.Plants
module Tags = Herbier_store.Tags
module Search = Herbier_store.Search
module Observations = Herbier_store.Observations
module Observation = Herbier_domain.Observation
module Plant = Herbier_domain.Plant
module Plant_id = Herbier_domain.Ids.Plant_id
module Candidate = Herbier_refs.Resolve.Candidate
module RList = ReactiveData.RList
module W = Widgets

type mode =
  | Identify of Herbier_domain.Ids.Observation_id.t
  | Change of Herbier_domain.Ids.Observation_id.t
  | Search of string
  | Link_plant of Plant_id.t

(* The two modes that move an observation. *)
type move_mode = Identify_obs | Change_obs

let cls c = At.class' (Jstr.v c)

let log_error what e =
  Console.(error [str ("identifier: " ^ what); str (Db.error_to_string e)])

type data = {
  observation : Observation.t;
  current : Plant.t option;  (** [None]: « À identifier », or a deleted plant *)
  unidentified : Observation.t list;  (** newest first *)
  plants : Plant.t list;  (** live, for the reference rows' actions *)
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
      let* unidentified = Db.all db Observations.unidentified in
      let+ plants = Db.all db Plants.list in
      Some {observation = o; current; unidentified; plants}

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

let back_button () =
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
  let click, b = Rb.click back in
  (back, [b; Rb.act click Route.back])

let header ~title ~right =
  let back, bindings = back_button () in
  ( El.div
      ~at:[cls "modal-header"]
      [
        back;
        El.div ~at:[cls "modal-header__title"; cls "resolve__title"] title;
        right;
      ],
    bindings )

let problem_line () =
  let text, set = React.S.create ~eq:String.equal "" in
  let el = El.p ~at:[cls "t-meta"; cls "resolve__problem"] [] in
  ( el,
    set,
    [
      Rb.text el text;
      Rb.class_ el "is-hidden" (React.S.map (String.equal "") text);
    ] )

(* « Dans ma collection · n »: my plants matching the search text, queried
   again as it changes. *)
let collection db ~problem ~(search : W.Text_field.t) row =
  let rows, rows_handle = RList.create [] in
  (* [None] until the first result. *)
  let found, set_found = React.S.create None in
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
            Rb.patch rows_handle (List_patch.diff ~same ~equal !shown next);
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
  ( [
      El.h2 ~at:[cls "t-section-label"] [El.txt' "Dans ma collection · "; count];
      rows_el;
      empty;
    ],
    [
      Rb.rlist rows_el row rows;
      Rb.act (React.S.changes search.value) (fun _ -> refresh ());
      Rb.text count
        (React.S.map (function None -> "…" | Some n -> string_of_int n) found);
      Rb.class_ empty "is-hidden"
        (React.S.map (function Some 0 -> false | Some _ | None -> true) found);
    ] )

(* style: [busy] keeps a second tap from starting the same save again while
   the first is saved and the screen leaves; written by [guarded] and the
   callbacks of what it starts, outside any reaction. *)
let guard () =
  let busy = ref false in
  let release () = busy := false in
  let guarded f =
    match !busy with
    | true -> ()
    | false ->
        busy := true;
        f ()
  in
  (guarded, release)

(* style: [left] turns true when the screen is released, so a future that
   ends later (a GBIF hop, a save) does not navigate away from whatever
   screen is shown by then: [Route.back] would pop it. *)
let leaving () =
  let left = ref false in
  let while_here f = match !left with true -> () | false -> f () in
  (while_here, Rb.on_release (fun () -> left := true))

let chosen_problem = function
  | Herbier_refs.Resolve.No_species -> "L'espèce n'a pas pu être lue."
  | Herbier_refs.Resolve.(Unavailable _ | Observation_link) ->
      "Le réseau ne répond pas."

let unresolved_text = function
  | Herbier_refs.Resolve.No_species -> "no species"
  | Herbier_refs.Resolve.Observation_link -> "observation link"
  | Herbier_refs.Resolve.Unavailable msg -> msg

(* The taxon a reference row stands for, after the synonym hop, with the
   row's action again: the accepted taxon may be one a plant already has.
   Nothing is saved yet, so a screen left meanwhile drops the choice. *)
let choose ~while_here ~mode ~current ~plants ~problem ~release
    (c : Candidate.t) k =
  Fut.await (Herbier_refs_io.Resolver.chosen c.taxon) (fun result ->
      (match result with
      | Error why ->
          Console.(error [str "refs: chosen"; str (unresolved_text why)])
      | Ok _ -> ());
      while_here (fun () ->
          match result with
          | Error why ->
              release ();
              problem (chosen_problem why)
          | Ok taxon -> k (Ref_pick.action mode ~current ~plants taxon) taxon))

let render app mode (d : data) =
  let db = App.db app in
  let o = d.observation in
  let problem_el, problem, problem_bindings = problem_line () in
  let while_here, left_binding = leaving () in
  let position = To_identify.position o d.unidentified in
  let go_next () =
    match position with
    | Some {next = Some n; _} ->
        Route.replace (Route.Modal (Route.Identify n.id))
    | Some {next = None; _} | None -> Route.back ()
  in
  let finish () =
    while_here (fun () ->
        match mode with
        | Change_obs -> Route.back ()
        | Identify_obs -> go_next ())
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
            | Ok [] -> while_here dialog.show
            | Ok (_ :: _) -> finish ()
            | Error e ->
                log_error "orphan check" e;
                finish ())
  in
  let guarded, release = guard () in
  let moved = function
    | Error e ->
        release ();
        log_error "link" e;
        problem "L'observation n'a pas pu être déplacée."
    | Ok _ -> after_move ()
  in
  (* [extra] goes first: a new plant must exist before the observation's
     plant_id references it. *)
  let move_now ?(extra = []) target =
    let at = Ptime_clock.now () in
    Fut.await
      (App.save app
         (extra
         @ [Observations.upsert {o with plant_id = target; updated_at = at}]))
      moved
  in
  let move ?extra target = guarded (fun () -> move_now ?extra target) in
  (* 4k / 5c « + »: the plant, its GBIF link and the move in one save. *)
  let create_with (c : Candidate.t) taxon =
    let at = Ptime_clock.now () in
    let plant =
      Plant_link.create ~id:(Plant_id.fresh ()) ~at
        ~name:(Plant_link.display_name c)
        taxon
    in
    Fut.await
      (App.create_linked app
         ~extra:
           [
             Observations.upsert
               {o with plant_id = Some plant.id; updated_at = at};
           ]
         plant taxon)
      moved
  in
  let current = Option.map (fun (p : Plant.t) -> p.id) d.current in
  let pick action (c : Candidate.t) =
    match (action : Ref_pick.action) with
    | Ref_pick.Attach_to p -> move (Some p.id)
    | Ref_pick.Create ->
        guarded (fun () ->
            choose ~while_here ~mode:Ref_pick.Attach ~current ~plants:d.plants
              ~problem ~release c (fun action taxon ->
                match action with
                | Ref_pick.Attach_to p -> move_now (Some p.id)
                | Ref_pick.Create -> create_with c taxon
                | Ref_pick.Inert ->
                    release ();
                    problem "L'observation est déjà sur cette plante."
                | Ref_pick.(Open _ | Link_this) -> release ()))
    | Ref_pick.(Inert | Open _ | Link_this) -> ()
  in
  let next = W.Button.text "Suivante ›" in
  let title, right =
    match mode with
    | Identify_obs -> (
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
    | Change_obs ->
        ( [
            El.span ~at:[cls "t-section-label"] [El.txt' "Changer d'espèce"];
            El.span
              ~at:[cls "resolve__subtitle"]
              [El.txt' ("Observation du " ^ Fr_date.day_month (Zone.date o.at))];
          ],
          El.span [] )
  in
  let header, header_bindings = header ~title ~right in
  let top =
    match mode with
    | Identify_obs -> observation_card o
    | Change_obs ->
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
      ~placeholder:"Chercher dans ma collection ou GBIF" ()
  in
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
  let collection_els, collection_bindings =
    collection db ~problem ~search row
  in
  let reference =
    Ref_results.v app ~mode:Ref_pick.Attach ~current ~plants:d.plants
      ~query:search.value ~pick
  in
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
    | Identify_obs ->
        [El.div ~at:[cls "resolve__footer"] [paste.el; free.el]; free_hint]
    | Change_obs ->
        [
          El.div ~at:[cls "resolve__footer"] [free.el];
          free_hint;
          (match o.plant_id with Some _ -> unlink.el | None -> El.span []);
        ]
  in
  let el =
    El.div
      ~at:[cls "resolve__content"]
      (List.concat
         [
           [header; problem_el; top; search.el];
           collection_els;
           [reference.el];
           footer;
           Option.to_list
             (Option.map
                (fun (_, (dialog : orphan W.Dialog.t)) -> dialog.el)
                left);
         ])
  in
  ( el,
    List.concat
      [
        [
          Rb.act next.click go_next;
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
        ];
        (match left with
        | None -> []
        | Some (p, dialog) ->
            Rb.act dialog.choice (function
              | Delete_plant -> delete_orphan p
              | Keep_plant -> finish ())
            :: dialog.bindings);
        [left_binding];
        header_bindings;
        problem_bindings;
        collection_bindings;
        reference.bindings;
        next.bindings;
        search.bindings;
        free.bindings;
        paste.bindings;
        unlink.bindings;
      ] )

(* 4i: my collection and GBIF, from the « Chercher » entries. *)
let render_search app q (plants : Plant.t list) =
  let db = App.db app in
  let problem_el, problem, problem_bindings = problem_line () in
  let header, header_bindings =
    header
      ~title:[El.span ~at:[cls "t-section-label"] [El.txt' "Chercher"]]
      ~right:(El.span [])
  in
  let search =
    W.Text_field.v ~icon:W.Icon.Search ~value:q
      ~placeholder:"Chercher dans ma collection ou GBIF" ()
  in
  let row (p : Plant.t) =
    let r =
      W.List_row.v ~thumb:W.List_row.Placeholder ~title:p.display_name
        ~meta:(Option.value p.scientific_name ~default:"nom libre" ^ " · Ouvrir")
        ()
    in
    ( r.el,
      Rb.act r.click (fun () -> Route.go (Route.Modal (Route.Plant p.id)))
      :: r.bindings )
  in
  let collection_els, collection_bindings =
    collection db ~problem ~search row
  in
  let guarded, release = guard () in
  let while_here, left_binding = leaving () in
  (* A creation: ← from the new fiche does not come back to 4i. *)
  let saved_then_open (plant : Plant.t) = function
    | Error e ->
        release ();
        log_error "create" e;
        problem "La fiche n'a pas pu être créée."
    | Ok _ ->
        while_here (fun () ->
            Route.replace (Route.Modal (Route.Plant plant.id)))
  in
  let create (c : Candidate.t) taxon =
    let plant =
      Plant_link.create ~id:(Plant_id.fresh ()) ~at:(Ptime_clock.now ())
        ~name:(Plant_link.display_name c)
        taxon
    in
    Fut.await (App.create_linked app plant taxon) (saved_then_open plant)
  in
  let pick action (c : Candidate.t) =
    match (action : Ref_pick.action) with
    | Ref_pick.Open p -> Route.go (Route.Modal (Route.Plant p.id))
    | Ref_pick.Create ->
        guarded (fun () ->
            choose ~while_here ~mode:Ref_pick.Browse ~current:None ~plants
              ~problem ~release c (fun action taxon ->
                match action with
                | Ref_pick.Open p ->
                    release ();
                    Route.go (Route.Modal (Route.Plant p.id))
                | Ref_pick.Create -> create c taxon
                | Ref_pick.(Inert | Attach_to _ | Link_this) -> release ()))
    | Ref_pick.(Inert | Attach_to _ | Link_this) -> ()
  in
  let reference =
    Ref_results.v app ~mode:Ref_pick.Browse ~current:None ~plants
      ~query:search.value ~pick
  in
  (* 4g: without GBIF, the plant can still be noted by its free name. *)
  let free = W.Button.v ~kind:W.Button.Secondary "Créer avec un nom libre" in
  let free_shown =
    React.S.l2 ~eq:Bool.equal
      (fun status text ->
        match (status, String.trim text) with
        | Ref_search.(Blank | Pending | Found _ | Offline | Failed _), "" ->
            false
        | Ref_search.(Offline | Failed _), _ -> true
        | Ref_search.(Blank | Pending | Found _), _ -> false)
      reference.status search.value
  in
  let free_name () =
    match String.trim (React.S.value search.value) with
    | "" -> ()
    | name ->
        guarded (fun () ->
            let plant =
              Plant.v ~id:(Plant_id.fresh ()) ~at:(Ptime_clock.now ()) name
            in
            Fut.await
              (App.save app [Plants.upsert plant])
              (saved_then_open plant))
  in
  let el =
    El.div
      ~at:[cls "resolve__content"]
      (List.concat
         [
           [header; problem_el; search.el];
           collection_els;
           [reference.el; free.el];
         ])
  in
  ( el,
    List.concat
      [
        [
          Rb.act free.click free_name;
          Rb.class_ free.el "is-hidden" (React.S.map not free_shown);
          left_binding;
        ];
        header_bindings;
        problem_bindings;
        collection_bindings;
        reference.bindings;
        search.bindings;
        free.bindings;
      ] )

(* 4i for one plant: 4g « Lier », 5a « Changer › ». *)
let render_link app ((plant : Plant.t), plants) =
  let problem_el, problem, problem_bindings = problem_line () in
  let title =
    match plant.scientific_name with
    | None -> Printf.sprintf "Lier « %s »" plant.display_name
    | Some _ -> "Changer d'espèce de référence"
  in
  let header, header_bindings =
    header
      ~title:[El.span ~at:[cls "t-section-label"] [El.txt' title]]
      ~right:(El.span [])
  in
  let search =
    W.Text_field.v ~icon:W.Icon.Search
      ~value:(Option.value plant.scientific_name ~default:plant.display_name)
      ~placeholder:"Chercher une espèce dans GBIF" ()
  in
  let guarded, release = guard () in
  let while_here, left_binding = leaving () in
  let current = Some plant.id in
  let link (c : Candidate.t) taxon =
    Fut.await
      (App.link app ~name:(Plant_link.display_name c) plant.id taxon)
      (function
        | Ok () -> while_here Route.back
        | Error App.Plant_gone ->
            release ();
            problem "Cette plante n'est plus dans l'herbier."
        | Error (App.Store e) ->
            release ();
            Console.(error [str "lier la fiche:"; str (Db.error_to_string e)]);
            problem "La fiche n'a pas pu être liée.")
  in
  let pick action (c : Candidate.t) =
    match (action : Ref_pick.action) with
    | Ref_pick.Link_this ->
        guarded (fun () ->
            choose ~while_here ~mode:Ref_pick.Relink ~current ~plants ~problem
              ~release c (fun action taxon ->
                match action with
                | Ref_pick.Link_this -> link c taxon
                | Ref_pick.Inert ->
                    release ();
                    problem "La fiche est déjà liée à cette espèce."
                | Ref_pick.(Open _ | Attach_to _ | Create) -> release ()))
    | Ref_pick.(Inert | Open _ | Attach_to _ | Create) -> ()
  in
  let reference =
    Ref_results.v app ~mode:Ref_pick.Relink ~current ~plants ~query:search.value
      ~pick
  in
  ( El.div
      ~at:[cls "resolve__content"]
      [header; problem_el; search.el; reference.el],
    List.concat
      [
        [left_binding];
        header_bindings;
        problem_bindings;
        reference.bindings;
        search.bindings;
      ] )

let screen ~what ~failed load item =
  let el = El.div ~at:[cls "screen"; cls "resolve"] [] in
  {
    Screen.el;
    bindings =
      Loaded.v ~what ~failed:(fun () -> Loaded.notice failed) el load item;
  }

let observation app mode id =
  screen ~what:"identifier" ~failed:"L'observation n'a pas pu être lue."
    (fun () -> load (App.db app) id)
    (function
      | None -> Loaded.notice "Cette observation n'est plus dans l'herbier."
      | Some d -> render app mode d)

let v app = function
  | Identify id -> observation app Identify_obs id
  | Change id -> observation app Change_obs id
  | Search q ->
      screen ~what:"chercher" ~failed:"La collection n'a pas pu être lue."
        (fun () -> Db.all (App.db app) Plants.list)
        (render_search app q)
  | Link_plant id ->
      let db = App.db app in
      screen ~what:"lier" ~failed:"La plante n'a pas pu être lue."
        (fun () ->
          let open Fut.Result_syntax in
          let* plant = Db.find db (Plants.get id) in
          let+ plants = Db.all db Plants.list in
          Option.map (fun p -> (p, plants)) plant)
        (function
          | None -> Loaded.notice "Cette plante n'est plus dans l'herbier."
          | Some loaded -> render_link app loaded)
