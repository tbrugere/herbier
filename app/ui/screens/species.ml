open Brr
module Db = Herbier_store.Db
module Plants = Herbier_store.Plants
module Tags = Herbier_store.Tags
module Observations = Herbier_store.Observations
module Photos = Herbier_store.Photos
module Observation = Herbier_domain.Observation
module Observation_id = Herbier_domain.Ids.Observation_id
module Plant = Herbier_domain.Plant
module Tag = Herbier_domain.Tag
module Tag_id = Herbier_domain.Ids.Tag_id
module RList = ReactiveData.RList
module W = Widgets

let cls c = At.class' (Jstr.v c)

let button ?label classes children =
  let aria =
    match label with
    | Some l -> [At.v (Jstr.v "aria-label") (Jstr.v l)]
    | None -> []
  in
  El.button
    ~at:((At.type' (Jstr.v "button") :: aria) @ List.map cls classes)
    children

let log_error what e =
  Console.(error [str ("fiche: " ^ what); str (Db.error_to_string e)])

(* What the fiche shows, loaded on entry and after each save. *)
type data = {
  plant : Plant.t;
  tags : Tag.t list;
  all_tags : Tag.t list;
  observations : Observation.t list; (* newest first *)
  photos : Herbier_domain.Photo.t list;
}

let load db id =
  let open Fut.Result_syntax in
  let* plant = Db.find db (Plants.get id) in
  match plant with
  | None -> Fut.ok None
  | Some plant ->
      let* tags = Db.all db (Tags.of_plant id) in
      let* all_tags = Db.all db Tags.list in
      let* observations = Db.all db (Observations.of_plant id) in
      let+ photos = Db.all db (Photos.of_plant id) in
      Some {plant; tags; all_tags; observations; photos}

let has_tag ts (t : Tag.t) =
  List.exists (fun (u : Tag.t) -> Tag_id.equal u.id t.id) ts

(* [a], then the tags of [b] that [a] lacks. *)
let union a b = a @ List.filter (fun t -> not (has_tag a t)) b

let observation_row (d : data) (o : Observation.t) =
  let off = Zone.offset_s o.at in
  let when_ =
    Fr_date.full_date (Fr_date.local_date ~tz_offset_s:off o.at)
    ^ " · "
    ^ Fr_date.time ~tz_offset_s:off o.at
  in
  let photos =
    List.length
      (List.filter
         (fun (p : Herbier_domain.Photo.t) ->
           Observation_id.equal p.observation_id o.id)
         d.photos)
  in
  let details =
    List.concat
      [
        Option.to_list (Journal_day.place [o]);
        (match photos with 0 -> [] | n -> [Fr_text.plural n "photo" "photos"]);
        (match o.note with Some _ -> ["note"] | None -> []);
      ]
  in
  El.li
    ~at:[cls "species__obs"]
    [
      El.div ~at:[cls "species__obs-date"] [El.txt' when_];
      El.div ~at:[cls "t-meta"] [El.txt' (String.concat " · " details)];
    ]

let observation_list (d : data) =
  match d.observations with
  | [] ->
      [El.p ~at:[cls "t-meta"] [El.txt' "Aucune observation pour l'instant."]]
  | obs ->
      [El.ul ~at:[cls "species__obs-list"] (List.map (observation_row d) obs)]

let names (d : data) =
  let p = d.plant in
  let where =
    match d.observations with
    | [] -> []
    | (o : Observation.t) :: _ ->
        let date = Fr_date.day_month (Zone.date o.at) in
        [String.concat " · " (Option.to_list (Journal_day.place [o]) @ [date])]
  in
  let sci =
    match p.scientific_name with
    | Some s ->
        El.p
          ~at:[cls "t-hero-sci"]
          (El.txt' s
          ::
          (match p.authorship with
          | Some a -> [El.txt' " "; El.span ~at:[cls "author"] [El.txt' a]]
          | None -> []))
    | None ->
        El.p
          ~at:[cls "species__free-name"]
          [El.txt' "nom libre — espèce non liée"]
  in
  [
    El.p
      ~at:[cls "species__provenance"]
      (El.span ~at:[cls "species__badge"] [El.txt' "local"]
      :: List.map (fun w -> El.span [El.txt' w]) where);
    El.h1 ~at:[cls "t-hero-name"] [El.txt' p.display_name];
    sci;
  ]

let section title extra children =
  El.section
    ~at:[cls "species__section"]
    (El.div
       ~at:[cls "species__section-head"]
       (El.h2 ~at:[cls "t-section-label"] [El.txt' title] :: extra)
    :: children)

(* The field is saved when it is left, and also when the fiche is torn down
   while it is open: removing a focused element fires no [blur] (Android
   back). *)
let notes app ~problem data =
  let notes =
    React.S.map ~eq:String.equal (fun d -> d.plant.Plant.notes) data
  in
  let shown = button ["species__notes"; "t-notes"] [] in
  let area =
    El.textarea
      ~at:[cls "species__notes-input"; cls "t-notes"; cls "is-hidden"]
      []
  in
  (* style: [editing] tells whether the textarea is open, so that its blur
     and the release do not both save; [draft] keeps the text of a save that
     failed, offered again on the next tap. Both written from the listeners,
     the release and the save's callback; the release may run inside the
     router's update step, where a ref write is harmless. *)
  let editing = ref false in
  let draft = ref None in
  let set_editing on =
    editing := on;
    El.set_class (Jstr.v "is-hidden") on shown;
    El.set_class (Jstr.v "is-hidden") (not on) area;
    match on with true -> El.set_has_focus true area | false -> ()
  in
  let save text =
    let at = Ptime_clock.now () in
    let p = (React.S.value data).plant in
    let plant =
      {p with notes = text; notes_updated_at = Some at; updated_at = at}
    in
    Fut.await
      (App.save app [Plants.upsert plant])
      (function
        | Error e ->
            log_error "notes" e;
            draft := Some text;
            problem "La note n'a pas pu être enregistrée."
        | Ok _ ->
            draft := None;
            problem "")
  in
  let commit () =
    match !editing with
    | false -> ()
    | true -> (
        set_editing false;
        let text = String.trim (Jstr.to_string (El.prop El.Prop.value area)) in
        match String.equal text (React.S.value notes) with
        | true -> ()
        | false -> save text)
  in
  let open_ =
    Rb.listen shown Ev.click (fun _ ->
        let text = Option.value !draft ~default:(React.S.value notes) in
        El.set_prop El.Prop.value (Jstr.v text) area;
        set_editing true)
  in
  ( El.div [shown; area],
    [
      open_;
      Rb.listen area Ev.blur (fun _ -> commit ());
      Rb.on_release commit;
      Rb.text shown
        (React.S.map
           (function "" -> "Touchez pour écrire une note." | n -> n)
           notes);
      Rb.class_ shown "species__notes--empty"
        (React.S.map (String.equal "") notes);
    ] )

(* The fiche of a live plant. The parts [data] shows are updated in place on
   each reload, so an editor open on the fiche (the notes, « + tag ») stays
   open across one. *)
let render app (data : data React.signal) =
  let state = App.state app in
  let id = (React.S.value data).plant.id in
  let problem_text, problem = React.S.create ~eq:String.equal "" in
  let problem_el = El.p ~at:[cls "t-meta"; cls "species__problem"] [] in
  let back =
    button ~label:"Retour" ["round-button"] [W.Icon.el W.Icon.Arrow_back]
  in
  let edit =
    button ~label:"Modifier la fiche" ["round-button"] [W.Icon.el W.Icon.Edit]
  in
  let back_click, b_back = Rb.click back in
  let edit_click, b_edit = Rb.click edit in
  let hero_names = El.div ~at:[cls "species__hero-names"] [] in
  let hero =
    El.div
      ~at:[cls "species__hero"]
      [El.div ~at:[cls "species__hero-buttons"] [back; edit]; hero_names]
  in
  let adder = W.Adder.v ~label:"tag" ~placeholder:"Nom du tag" () in
  (* style: [known] holds the tags this fiche put on the plant, so that a tag
     added before the reload shows the previous one neither creates a second
     tag of that name nor links one twice. Written by [add_tag] and its save's
     callback, outside any reaction. *)
  let known = ref [] in
  let add_tag name =
    let d = React.S.value data in
    let tags = union d.tags !known and all_tags = union d.all_tags !known in
    let form =
      Plant_form.add_tag ~all:all_tags name (Plant_form.of_plant d.plant tags)
    in
    let c = Plant_form.diff ~before:d.plant ~before_tags:tags form in
    match Plant_edits.of_change ~at:(Ptime_clock.now ()) ~plant:id c with
    | _, [] -> ()
    | created, edits ->
        let put =
          created
          @ List.filter
              (fun (t : Tag.t) -> List.exists (Tag_id.equal t.id) c.link)
              all_tags
        in
        known := union !known put;
        Fut.await (App.save app edits) (function
          | Error e ->
              log_error "tag" e;
              known := List.filter (fun t -> not (has_tag put t)) !known;
              problem
                (Printf.sprintf "Le tag « %s » n'a pas pu être ajouté." name)
          | Ok _ -> problem "")
  in
  let chips = El.span ~at:[cls "species__chips"] [] in
  let obs_title = El.h2 ~at:[cls "t-section-label"] [] in
  let obs_list = El.div [] in
  let notes_el, notes_bindings = notes app ~problem data in
  let modified = El.span ~at:[cls "t-meta"] [] in
  let offline_text = El.span [] in
  let link =
    W.Button.v ~kind:W.Button.Secondary "Lier à une espèce de référence"
  in
  El.set_at (Jstr.v "aria-disabled") (Some (Jstr.v "true")) link.el;
  let online =
    React.S.map ~eq:Bool.equal
      (fun (n : State.network) -> n.online)
      (State.network state)
  in
  let reference =
    El.section
      ~at:[cls "species__reference"]
      [
        El.h2 ~at:[cls "t-section-label-ref"] [El.txt' "Référence"];
        El.p
          ~at:[cls "t-body"]
          [El.txt' "Aucune espèce de référence liée."; offline_text];
        link.el;
      ]
  in
  let el =
    El.div
      ~at:[cls "species__content"]
      [
        hero;
        El.div
          ~at:[cls "species__body"]
          [
            problem_el;
            El.div ~at:[cls "species__tags"] [chips; adder.el];
            El.section
              ~at:[cls "species__section"]
              [El.div ~at:[cls "species__section-head"] [obs_title]; obs_list];
            section "Mes notes" [modified] [notes_el];
          ];
        reference;
      ]
  in
  ( el,
    List.concat
      [
        [
          b_back;
          b_edit;
          Rb.act back_click Route.back;
          Rb.act edit_click (fun () ->
              Route.go (Route.Modal (Route.Edit_plant id)));
          Rb.act adder.added add_tag;
          Rb.children hero_names (React.S.map ~eq:( == ) names data);
          Rb.children chips
            (React.S.map ~eq:( == )
               (fun d -> List.map (fun (t : Tag.t) -> W.Chip.tag t.name) d.tags)
               data);
          Rb.text obs_title
            (React.S.map
               (fun d ->
                 Printf.sprintf "Mes observations · %d"
                   (List.length d.observations))
               data);
          Rb.children obs_list (React.S.map ~eq:( == ) observation_list data);
          (* An emptied note keeps its date in the row, not on screen. *)
          Rb.text modified
            (React.S.map
               (fun d ->
                 match (d.plant.notes, d.plant.notes_updated_at) with
                 | "", _ | _, None -> ""
                 | _, Some t -> "modifié le " ^ Fr_date.day_month (Zone.date t))
               data);
          Rb.text problem_el problem_text;
          Rb.class_ problem_el "is-hidden"
            (React.S.map (String.equal "") problem_text);
          Rb.text offline_text
            (React.S.map
               (function
                 | true -> ""
                 | false ->
                     " Hors-ligne : la recherche de noms reviendra avec le \
                      réseau.")
               online);
          Rb.class_ link.el "is-offline" (React.S.map not online);
        ];
        adder.bindings;
        notes_bindings;
        link.bindings;
      ] )

(* A plant that is not (or no longer) live, or a fiche that could not be
   read: the reason under ←. *)
let notice text =
  let back =
    button ~label:"Retour" ["icon-button"] [W.Icon.el W.Icon.Arrow_back]
  in
  let click, b = Rb.click back in
  ( El.div
      ~at:[cls "species__gone"]
      [
        El.div ~at:[cls "modal-header"] [back];
        El.p ~at:[cls "t-body"] [El.txt' text];
      ],
    [b; Rb.act click Route.back] )

type shown = Fiche of data React.signal | Gone | Unreadable

let v app id =
  let content, handle = RList.create [] in
  (* style: [update] sets the data of the fiche on screen, if one is: a reload
     updates that fiche rather than rendering a new one. Written by the
     loads' callbacks only. *)
  let update = ref None in
  let reload () =
    Fut.await
      (load (App.db app) id)
      (function
        | Error e -> (
            log_error "load" e;
            match !update with
            | Some _ -> ()
            | None -> RList.set handle [Unreadable])
        | Ok None ->
            update := None;
            RList.set handle [Gone]
        | Ok (Some d) -> (
            match !update with
            | Some set -> set d
            | None ->
                let data, set = React.S.create ~eq:( == ) d in
                update := Some set;
                RList.set handle [Fiche data]))
  in
  reload ();
  let el = El.div ~at:[cls "screen"; cls "species"] [] in
  let item = function
    | Fiche data -> render app data
    | Gone -> notice "Cette plante n'est plus dans l'herbier."
    | Unreadable -> notice "La fiche n'a pas pu être lue."
  in
  {
    Screen.el;
    bindings = [Rb.rlist el item content; Rb.act (App.saved app) reload];
  }
