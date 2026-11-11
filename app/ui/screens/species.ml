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
  let el =
    El.button
      ~at:[At.type' (Jstr.v "button"); cls "species__obs"]
      [
        El.div ~at:[cls "species__obs-date"] [El.txt' when_];
        El.div ~at:[cls "t-meta"] [El.txt' (String.concat " · " details)];
      ]
  in
  let click, b = Rb.click el in
  ( el,
    [
      b; Rb.act click (fun () -> Route.go (Route.Modal (Route.Observation o.id)));
    ] )

let observation_list (d : data) =
  match d.observations with
  | [] ->
      ( El.p ~at:[cls "t-meta"] [El.txt' "Aucune observation pour l'instant."],
        [] )
  | obs ->
      let rows = List.map (observation_row d) obs in
      ( El.div ~at:[cls "species__obs-list"] (List.map fst rows),
        List.concat_map snd rows )

(* A column of more dots than this would run into the buttons and names of a
   phone-sized hero; past it the hero shows none. *)
let max_dots = 10

(* Paging is CSS scroll-snap (species.sass). *)
let hero_media (d : data) =
  let ordered = Cover.ordered d.plant.cover_photo_id d.photos in
  let pages =
    List.map
      (fun (ph : Herbier_domain.Photo.t) ->
        W.Preview_img.v ~cls:["species__page"] ph.preview_path)
      ordered
  in
  let pager = El.div ~at:[cls "species__pager"] pages in
  let dots =
    List.mapi
      (fun i _ ->
        El.span
          ~at:
            (cls "species__dot"
            :: (match i with 0 -> [cls "is-active"] | _ -> []))
          [])
      ordered
  in
  let b_pager =
    Rb.listen pager Ev.scroll (fun _ ->
        let w = El.bound_w pager in
        match w > 0. with
        | false -> ()
        | true ->
            let i = Float.to_int (Float.round (El.scroll_x pager /. w)) in
            List.iteri
              (fun j dot -> El.set_class (Jstr.v "is-active") (i = j) dot)
              dots)
  in
  ( El.div
      ~at:[cls "species__hero-media"]
      [
        pager;
        El.div ~at:[cls "species__scrim"] [];
        El.div
          ~at:[cls "species__dots"]
          (let n = List.length dots in
           match n >= 2 && n <= max_dots with true -> dots | false -> []);
      ],
    [b_pager] )

let names (d : data) =
  let p = d.plant in
  (* Where the cover's original is kept (original_target), whatever its
     upload state. *)
  let provenance =
    match Cover.choose p.cover_photo_id d.photos with
    | None -> "local"
    | Some ph -> (
        match ph.original_target with
        | Drive -> "Google Drive"
        | App_only -> "local")
  in
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
      (El.span ~at:[cls "species__badge"] [El.txt' provenance]
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

let notes app ~problem data =
  let save text =
    let at = Ptime_clock.now () in
    let p = (React.S.value data).plant in
    let plant =
      {p with notes = text; notes_updated_at = Some at; updated_at = at}
    in
    Fut.map
      (function
        | Error e ->
            log_error "notes" e;
            problem "La note n'a pas pu être enregistrée.";
            false
        | Ok _ ->
            problem "";
            true)
      (App.save app [Plants.upsert plant])
  in
  let t =
    W.Inline_text.v ~cls:"t-notes" ~label:"Mes notes"
      ~placeholder:"Touchez pour écrire une note." ~save
      (React.S.map ~eq:String.equal (fun d -> d.plant.Plant.notes) data)
  in
  (t.el, t.bindings)

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
  let media = El.div ~at:[cls "species__hero-media"] [] in
  let hero_names = El.div ~at:[cls "species__hero-names"] [] in
  let hero =
    El.div
      ~at:[cls "species__hero"]
      [media; El.div ~at:[cls "species__hero-buttons"] [back; edit]; hero_names]
  in
  let photos = El.div ~at:[cls "species__photos"] [] in
  let photos_section (d : data) =
    match d.photos with
    | [] -> (El.div ~at:[cls "species__photos"] [], [])
    | _ :: _ ->
        let grid =
          W.Photo_grid.v (Cover.ordered d.plant.cover_photo_id d.photos)
        in
        ( El.div
            ~at:[cls "species__photos"]
            [
              section
                (Printf.sprintf "Mes photos · %d" (List.length d.photos))
                [] [grid.el];
            ],
          grid.bindings )
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
            photos;
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
          Rb.view media hero_media data;
          Rb.class_ hero "species__hero--photo"
            (React.S.map (fun d -> not (List.is_empty d.photos)) data);
          Rb.view photos photos_section data;
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
          Rb.view obs_list observation_list data;
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

let v app id =
  let el = El.div ~at:[cls "screen"; cls "species"] [] in
  {
    Screen.el;
    bindings =
      Loaded.live ~reload:(App.saved app) ~what:"fiche"
        ~gone:(fun () -> notice "Cette plante n'est plus dans l'herbier.")
        ~failed:(fun () -> notice "La fiche n'a pas pu être lue.")
        el
        (fun () -> load (App.db app) id)
        (render app);
  }
