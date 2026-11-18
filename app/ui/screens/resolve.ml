module Fr_date = Herbier_ui_model.Fr_date
module Gps = Herbier_ui_model.Gps
module Intercept = Herbier_ui_model.Intercept
module Journal_day = Herbier_ui_model.Journal_day
module List_patch = Herbier_ui_model.List_patch
module Plant_link = Herbier_ui_model.Plant_link
module Plant_version = Herbier_ui_model.Plant_version
module Ref_pick = Herbier_ui_model.Ref_pick
module Record_plan = Herbier_ui_model.Record_plan
module Ref_search = Herbier_ui_model.Ref_search
module To_identify = Herbier_ui_model.To_identify
open Brr
module Db = Herbier_store_io.Db
module Plants = Herbier_store.Plants
module Tags = Herbier_store.Tags
module Search = Herbier_store.Search
module Observations = Herbier_store.Observations
module Observation = Herbier_domain.Observation
module Plant = Herbier_domain.Plant
module Plant_id = Herbier_domain.Ids.Plant_id
module Tag_id = Herbier_domain.Ids.Tag_id
module Observation_id = Herbier_domain.Ids.Observation_id
module Candidate = Herbier_refs.Resolve.Candidate
module Photo = Herbier_domain.Photo
module Photos = Herbier_store.Photos
module Choice = Herbier_ui_model.Identify.Choice
module RList = ReactiveData.RList
module W = Widgets

type mode =
  | Identify of Herbier_domain.Ids.Observation_id.t
  | Change of Herbier_domain.Ids.Observation_id.t
  | Search of string
  | Link_plant of Plant_id.t
  | Intercept of {text : string; outside : bool}

(* The two modes that move an observation. *)
type move_mode = Identify_obs | Change_obs

let cls = Html.cls
let log_error = Log.db ~scope:"identifier"

type data = {
  observation : Observation.t;
  current : Plant.t option;  (** [None]: « À identifier », or a deleted plant *)
  unidentified : Observation.t list;  (** newest first *)
  plants : Plant.t list;  (** live, for the reference rows' actions *)
  photos : Photo.t list;
      (** the observation's, for 6i's « Identifier »; [[]] in 5c *)
}

let load db mode id =
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
      let* plants = Db.all db Plants.list in
      let+ photos =
        match mode with
        | Identify_obs -> Db.all db (Photos.of_observation id)
        | Change_obs -> Fut.ok []
      in
      Some {observation = o; current; unidentified; plants; photos}

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

type orphan = Keep_plant | Delete_plant

let orphan_dialog (p : Plant.t) =
  W.Dialog.v ~title:"Garder la fiche ?"
    ~text:(Printf.sprintf "« %s » n'a plus d'observation." p.display_name)
    [
      (W.Button.Secondary, "Garder la fiche", Keep_plant);
      (W.Button.Danger, "Supprimer la fiche", Delete_plant);
    ]

let back_button () =
  let back = W.Icon_button.el ~label:"Retour" W.Icon.Arrow_back in
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
            Rb.patch rows_handle
              (List_patch.diff ~same:Plant_version.same
                 ~equal:Plant_version.equal !shown next);
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
      | Error why -> Log.error ~scope:"refs" "chosen" (unresolved_text why)
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
  (* 4k / 5c « + » and 6j « + Créer »: the plant, its GBIF link and the move
     in one save. *)
  let create_with ~name taxon =
    let at = Ptime_clock.now () in
    let plant = Plant_link.create ~id:(Plant_id.fresh ()) ~at ~name taxon in
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
  let create_free_now name =
    let plant = Plant.v ~id:(Plant_id.fresh ()) ~at:(Ptime_clock.now ()) name in
    move_now ~extra:[Plants.upsert plant] (Some plant.id)
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
                | Ref_pick.Create ->
                    create_with ~name:(Plant_link.display_name c) taxon
                | Ref_pick.Inert ->
                    release ();
                    problem "L'observation est déjà sur cette plante."
                | Ref_pick.(Open _ | Link_this) -> release ()))
    | Ref_pick.(Inert | Open _ | Link_this) -> ()
  in
  (* 6i: « Identifier avec Pl@ntNet » under the card, the layer (6j) it opens
     over the screen, and what a chosen proposal saves. *)
  let gate = App.identify_gate app in
  let n_sent = List.length (To_identify.sent d.photos) in
  let identify = W.Button.v ~kind:W.Button.Primary To_identify.identify_label in
  El.prepend_children identify.el [W.Identify_glyph.el ~size:22 ()];
  El.set_class (Jstr.v "resolve__identify") true identify.el;
  let identify_line = El.p ~at:[cls "resolve__identify-line"] [] in
  let or_by_name =
    El.div
      ~at:[cls "resolve__or"]
      [
        El.span ~at:[cls "resolve__or-rule"] [];
        El.span
          ~at:[cls "t-section-label"; cls "resolve__or-label"]
          [El.txt' To_identify.or_by_name];
        El.span ~at:[cls "resolve__or-rule"] [];
      ]
  in
  let resolving, set_resolving = React.S.create ~eq:Bool.equal false in
  let launcher = Identify.launcher ~button:identify.el ~problem in
  (* style: the layer's photos as it last closed with them (added ones, organs
     as last sent), read and written from DOM and future callbacks only. *)
  let layer_photos =
    ref
      (List.map
         (fun (p : Photo.t) ->
           {
             Identify.image = App.Stored p.id;
             organ = Herbier_identify.Organ.Auto;
           })
         (To_identify.sent d.photos))
  in
  let channel = App.channel () in
  (* GBIF's answer decides again between « Lier » and « + Créer »: a synonym
     id becomes the accepted taxon, which a plant of mine may have. *)
  let save_choice p =
    guarded (fun () ->
        set_resolving true;
        Fut.await (App.resolve_choice p) (fun r ->
            set_resolving false;
            while_here (fun () ->
                match
                  Record_plan.of_choice ~plants:d.plants
                    (Choice.resolved (Choice.v p) r)
                with
                | Existing pl -> move_now (Some pl.id)
                | Linked {name; taxon} -> create_with ~name taxon
                | Free name -> create_free_now name
                | To_identify ->
                    release ();
                    problem "Cette proposition n'a pas de nom.")))
  in
  (* [guarded] only checks that no save runs: one would leave the screen and
     take the layer with it, after a credit was spent. *)
  let open_layer host =
    match
      ( Identify.is_open launcher,
        To_identify.identify_enabled (React.S.value gate) ~photos:n_sent )
    with
    | false, true ->
        guarded (fun () ->
            release ();
            Identify.launch launcher ~on_resolve:save_choice
              (fun ~problem:deferred ~on_close ->
                Identify.open_ ~host
                  (Identify.services app channel)
                  ~caller:(To_identify.caller position)
                  ?note:o.note
                  ~add_photo:(Identify.gallery_adder app o ~problem:deferred)
                  ~on_close:(fun outcome photos ->
                    layer_photos := photos;
                    on_close outcome photos)
                  !layer_photos))
    | true, (true | false) | false, false -> ()
  in
  (* The signals on [gate] live as long as these bindings. *)
  let identify_bindings host =
    let identify_enabled =
      React.S.map ~eq:Bool.equal
        (fun g -> To_identify.identify_enabled g ~photos:n_sent)
        gate
    in
    let identify_text =
      React.S.map
        ~eq:(Option.equal String.equal)
        (fun g -> To_identify.identify_line g ~photos:n_sent)
        gate
    in
    [
      Rb.act identify.click (fun () -> open_layer host);
      Identify.release launcher;
      Rb.disabled identify.el (React.S.map not identify_enabled);
      Rb.attr identify.el "aria-label"
        (React.S.map
           (fun g -> Some (To_identify.identify_aria g ~photos:n_sent))
           gate);
      Rb.attr identify.el "aria-busy"
        (React.S.map (function true -> Some "true" | false -> None) resolving);
      Rb.text identify_line
        (React.S.map (Option.value ~default:"") identify_text);
      Rb.class_ identify_line "is-hidden"
        (React.S.map Option.is_none identify_text);
    ]
    @ identify.bindings
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
    | name -> guarded (fun () -> create_free_now name)
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
  let identify_els =
    match mode with
    | Identify_obs -> [identify.el; identify_line; or_by_name]
    | Change_obs -> []
  in
  let el =
    El.div
      ~at:[cls "resolve__content"]
      (List.concat
         [
           [header; problem_el; top];
           identify_els;
           [search.el];
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
        (match mode with
        | Identify_obs -> identify_bindings el
        | Change_obs -> []);
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

type intercepted = {
  plants : Plant.t list;  (** live *)
  tags : Herbier_domain.Tag.t list;  (** live *)
  links : Herbier_domain.Tag.Plant_tag.t list;  (** live *)
}

let load_intercepted db =
  let open Fut.Result_syntax in
  let* plants = Db.all db Plants.list in
  let* tags = Db.all db Tags.list in
  let+ links = Db.all db Tags.links in
  {plants; tags; links}

let log_refs = Log.error ~scope:"refs"

(* The app the link came from shows again; the route was popped already. *)
let minimize () =
  Fut.await (Herbier_bindings.Cap_app.minimize_app ()) (function
    | Ok () -> ()
    | Error e ->
        Console.(
          error
            [
              str "intercept: minimize";
              str (Herbier_bindings.Cap_error.to_string e);
            ]))

let close ~outside () =
  Route.back ();
  match outside with true -> minimize () | false -> ()

let toggle_button label on =
  let el = Html.button ["intercept__toggle"] [El.txt' label] in
  let click, b = Rb.click el in
  ( el,
    click,
    [
      b;
      Rb.attr el "aria-pressed"
        (React.S.map (fun b -> Some (Bool.to_string b)) on);
    ] )

(* « Première observation ici », or « Sans observation · Remettre » once
   removed. *)
let observation_card ~gps ~kept ~set_kept =
  let remove = W.Button.text "Enlever" in
  let restore = W.Button.text "Remettre" in
  let line = El.p ~at:[cls "t-meta"] [] in
  let card =
    El.div
      ~at:[cls "intercept__obs"]
      [
        El.span ~at:[cls "intercept__dot"] [];
        El.div
          ~at:[cls "intercept__obs-text"]
          [
            El.p
              ~at:[cls "intercept__obs-title"]
              [El.txt' "Première observation ici"];
            line;
          ];
        remove.el;
      ]
  in
  let removed =
    El.div
      ~at:[cls "intercept__obs-removed"]
      [El.span ~at:[cls "t-meta"] [El.txt' "Sans observation"]; restore.el]
  in
  ( [card; removed],
    List.concat
      [
        [
          Rb.text line (React.S.map Intercept.place_line gps);
          Rb.class_ card "is-hidden" (React.S.map not kept);
          Rb.class_ removed "is-hidden" kept;
          Rb.act remove.click (fun () -> set_kept false);
          Rb.act restore.click (fun () -> set_kept true);
        ];
        remove.bindings;
        restore.bindings;
      ] )

let tags_card chips ~selected ~set_selected =
  let chip ((tag : Herbier_domain.Tag.t), _) =
    let active =
      React.S.map ~eq:Bool.equal (List.exists (Tag_id.equal tag.id)) selected
    in
    let c = W.Chip.filter ~label:tag.name ~active () in
    ( c.el,
      Rb.act c.click (fun () ->
          let now = React.S.value selected in
          set_selected
            (match List.exists (Tag_id.equal tag.id) now with
            | true -> List.filter (fun id -> not (Tag_id.equal id tag.id)) now
            | false -> tag.id :: now))
      :: c.bindings )
  in
  match List.map chip chips with
  | [] -> (El.span [], [])
  | made ->
      ( El.div
          ~at:[cls "intercept__tags"]
          [
            El.p ~at:[cls "t-section-label"] [El.txt' "Tags"];
            El.div ~at:[cls "intercept__chips"] (List.map fst made);
          ],
        List.concat_map snd made )

let render_found app (d : intercepted) ~gps ~search ~problem ~while_here ~close
    (candidate : Candidate.t) (existing : Plant.t option) =
  let except =
    match existing with
    | None -> []
    | Some p ->
        List.filter_map
          (fun (l : Herbier_domain.Tag.Plant_tag.t) ->
            match Plant_id.equal l.plant_id p.id with
            | true -> Some l.tag_id
            | false -> None)
          d.links
  in
  let chips =
    Intercept.recent_tags ~now:(Ptime_clock.now ()) ~tags:d.tags ~links:d.links
      ~except
  in
  let kept, set_kept = React.S.create ~eq:Bool.equal true in
  let selected, set_selected =
    React.S.create ~eq:(List.equal Tag_id.equal)
      (List.filter_map
         (fun ((t : Herbier_domain.Tag.t), on) ->
           match on with true -> Some t.id | false -> None)
         chips)
  in
  let open_after, set_open_after = React.S.create ~eq:Bool.equal false in
  let species =
    El.div
      ~at:[cls "intercept__species"]
      [
        El.span ~at:[cls "intercept__thumb"] [];
        El.div
          ~at:[cls "intercept__species-text"]
          [
            El.p
              ~at:[cls "intercept__name"]
              [El.txt' (Intercept.name candidate ~existing)];
            El.p
              ~at:[cls "intercept__latin"]
              [El.txt' (Herbier_refs.Sources.Gbif.Taxon.latin candidate.taxon)];
            El.p ~at:[cls "t-meta"] [El.txt' (Intercept.meta candidate.taxon)];
          ];
      ]
  in
  let obs_els, obs_bindings = observation_card ~gps ~kept ~set_kept in
  let tags_el, tags_bindings = tags_card chips ~selected ~set_selected in
  let add =
    W.Button.v
      (match existing with
      | None -> "Ajouter à ma collection"
      | Some _ -> "Ajouter cette observation")
  in
  let nothing_to_add =
    React.S.l2 ~eq:Bool.equal
      (fun kept selected ->
        match (existing, kept, selected) with
        | Some _, false, [] -> true
        | Some _, true, _ | Some _, false, _ :: _ | None, _, _ -> false)
      kept selected
  in
  let research = W.Button.text "Chercher" in
  let open_el, open_click, open_bindings =
    toggle_button "Ouvrir la fiche après" open_after
  in
  let guarded, release = guard () in
  let edits ~at plant =
    let obs =
      match React.S.value kept with
      | true ->
          [
            Observations.upsert
              (Intercept.observation ~id:(Observation_id.fresh ()) ~at ~plant
                 (React.S.value gps));
          ]
      | false -> []
    in
    let selected = React.S.value selected in
    (* In chip order, whatever order they were tapped in. *)
    let tags =
      List.filter_map
        (fun ((t : Herbier_domain.Tag.t), _) ->
          match List.exists (Tag_id.equal t.id) selected with
          | true -> Some (Tags.tag ~plant ~tag:t.id ~at)
          | false -> None)
        chips
    in
    obs @ tags
  in
  let after id = function
    | Error e ->
        release ();
        log_error "4j save" e;
        problem "La plante n'a pas pu être ajoutée."
    | Ok _ ->
        while_here (fun () ->
            match React.S.value open_after with
            | true -> Route.replace (Route.Modal (Route.Plant id))
            | false -> close ())
  in
  let save () =
    let at = Ptime_clock.now () in
    match existing with
    | Some p -> (
        match edits ~at p.id with
        | [] -> ()
        | _ :: _ as edits ->
            guarded (fun () ->
                Fut.await (App.save app edits) (fun r -> after p.id r)))
    | None ->
        guarded (fun () ->
            let plant =
              Plant_link.create ~id:(Plant_id.fresh ()) ~at
                ~name:(Intercept.name candidate ~existing:None)
                candidate.taxon
            in
            Fut.await
              (App.create_linked app ~extra:(edits ~at plant.id) plant
                 candidate.taxon)
              (fun r -> after plant.id r))
  in
  let footer =
    El.div
      ~at:[cls "intercept__footer"]
      [
        El.p ~at:[cls "t-meta"] [El.txt' "Pas la bonne espèce ? "; research.el];
        open_el;
      ]
  in
  ( El.div
      ~at:[cls "intercept__found"]
      (List.concat
         [
           [species];
           obs_els;
           [tags_el];
           (match existing with
           | None -> []
           | Some _ ->
               [
                 El.p
                   ~at:[cls "intercept__already"]
                   [El.txt' "Déjà dans ma collection"];
               ]);
           [add.el; footer];
         ]),
    List.concat
      [
        [
          Rb.act add.click save;
          Rb.class_ add.el "is-inactive" nothing_to_add;
          Rb.disabled add.el nothing_to_add;
          Rb.act research.click search;
          Rb.act open_click (fun () ->
              set_open_after (not (React.S.value open_after)));
        ];
        obs_bindings;
        tags_bindings;
        add.bindings;
        research.bindings;
        open_bindings;
      ] )

let render_intercept app ~outside text (d : intercepted) =
  let network = State.network (App.state app) in
  let online () = (React.S.value network).online in
  let online_s =
    React.S.map ~eq:Bool.equal (fun (n : State.network) -> n.online) network
  in
  let problem_el, problem, problem_bindings = problem_line () in
  let while_here, left_binding = leaving () in
  let first, todo = Intercept.init ~online:(online ()) ~plants:d.plants text in
  let link = Intercept.link first in
  let close = close ~outside in
  let sheet, set_sheet = React.S.create ~eq:( == ) first in
  (* style: [alive] turns false on release, so a late answer cannot touch a
     released screen. *)
  let alive = ref true in
  let rec run = function
    | Intercept.No_effect -> ()
    | Intercept.Resolve {seq} ->
        Fut.await (Herbier_refs_io.Resolver.resolve link) (fun outcome ->
            (match outcome with
            | Herbier_refs.Resolve.Unresolved {why = Unavailable m; _} ->
                log_refs "4j" m
            | Herbier_refs.Resolve.(Taxon _ | Candidates _ | Unresolved _) -> ());
            step (Intercept.resolved ~seq outcome))
    | Intercept.Name {seq; taxon} ->
        Fut.await (Herbier_refs_io.Resolver.named taxon)
          (fun (candidate, failure) ->
            Option.iter (log_refs "4j names") failure;
            step (fun t ->
                (Intercept.named ~seq candidate t, Intercept.No_effect)))
  and step f =
    match !alive with
    | false -> ()
    | true ->
        let next, todo = f (React.S.value sheet) in
        set_sheet next;
        run todo
  in
  run todo;
  let status = React.S.map ~eq:Intercept.equal_status Intercept.status sheet in
  let search () =
    while_here (fun () ->
        Route.replace
          (Route.Modal
             (Route.Search (Intercept.search_query (React.S.value sheet)))))
  in
  let follow = function
    | Intercept.Search q ->
        while_here (fun () ->
            (match outside with true -> Intake.fell_back q | false -> ());
            Route.replace (Route.Modal (Route.Search q)))
    | Intercept.(Offline | Resolving | Failed _ | Found _) -> ()
  in
  follow (React.S.value status);
  let gps =
    match React.S.value status with
    | Intercept.Search _ -> React.S.const Gps.No_fix
    | Intercept.(Offline | Resolving | Failed _ | Found _) ->
        Gps_fix.start
          ~on_error:(fun e -> Console.(error [str "intercept: gps"; str e]))
          ()
  in
  let message text actions =
    let made =
      List.map
        (fun (label, f) -> (W.Button.v ~kind:W.Button.Secondary label, f))
        actions
    in
    ( El.div
        ~at:[cls "intercept__message"]
        (El.p
           ~at:[cls "intercept__status"; At.v (Jstr.v "role") (Jstr.v "status")]
           [El.txt' text]
        :: List.map (fun ((b : W.Button.t), _) -> b.el) made),
      List.concat_map
        (fun ((b : W.Button.t), f) -> Rb.act b.click f :: b.bindings)
        made )
  in
  let body = function
    | Intercept.Resolving -> message "Recherche de l'espèce…" []
    | Intercept.Offline ->
        message "Hors-ligne : l'espèce sera cherchée au retour du réseau."
          [("Chercher", search)]
    | Intercept.Failed _ ->
        message "La recherche de l'espèce a échoué."
          [
            ("Réessayer", fun () -> step (Intercept.retry ~online:(online ())));
            ("Chercher", search);
          ]
    | Intercept.Search _ -> (El.div [], [])
    | Intercept.Found {candidate; existing} ->
        render_found app d ~gps ~search ~problem ~while_here ~close candidate
          existing
  in
  let close_button = W.Icon_button.el ~label:"Fermer" W.Icon.Close in
  let close_click, close_b = Rb.click close_button in
  let body_el = El.div ~at:[cls "intercept__body"] [] in
  let header = "Herbier · " ^ Intercept.header link in
  let panel =
    El.div
      ~at:
        [
          cls "intercept__sheet";
          At.v (Jstr.v "role") (Jstr.v "dialog");
          At.v (Jstr.v "aria-modal") (Jstr.v "true");
          At.v (Jstr.v "aria-label") (Jstr.v header);
        ]
      [
        El.span ~at:[cls "intercept__handle"] [];
        El.div
          ~at:[cls "intercept__header"]
          [
            El.p
              ~at:[cls "t-section-label"; cls "intercept__label"]
              [El.txt' header];
            close_button;
          ];
        problem_el;
        body_el;
      ]
  in
  ( El.div ~at:[cls "intercept__scrim"] [panel],
    List.concat
      [
        [
          Rb.view body_el body status;
          Rb.act (React.S.changes status) follow;
          Rb.act (React.S.changes online_s) (fun online ->
              step (Intercept.network ~online));
          close_b;
          Rb.act close_click (fun () -> while_here close);
          Rb.on_release (fun () -> alive := false);
          left_binding;
        ];
        problem_bindings;
      ] )

let screen ~what ~failed load item =
  let el = El.div ~at:[cls "screen"; cls "resolve"] [] in
  {
    Screen.el;
    ready = Screen.now;
    bindings =
      Loaded.v ~what ~failed:(fun () -> Loaded.notice failed) el load item;
  }

let observation app mode id =
  screen ~what:"identifier" ~failed:"L'observation n'a pas pu être lue."
    (fun () -> load (App.db app) mode id)
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
  | Intercept {text; outside} ->
      screen ~what:"lien" ~failed:"Le lien n'a pas pu être ouvert."
        (fun () -> load_intercepted (App.db app))
        (render_intercept app ~outside text)
