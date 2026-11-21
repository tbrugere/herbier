module Cover = Herbier_ui_model.Cover
module Fr_date = Herbier_ui_model.Fr_date
module Fr_text = Herbier_ui_model.Fr_text
module Journal_day = Herbier_ui_model.Journal_day
module Plant_form = Herbier_ui_model.Plant_form
module Ref_block = Herbier_ui_model.Ref_block
module Ref_text = Herbier_ui_model.Ref_text
module Free_name = Herbier_ui_model.Free_name
module Choice = Herbier_ui_model.Identify.Choice
module Caller = Herbier_ui_model.Identify.Caller
open Brr
module Db = Herbier_store_io.Db
module Plants = Herbier_store.Plants
module Tags = Herbier_store.Tags
module Observations = Herbier_store.Observations
module Photos = Herbier_store.Photos
module Observation = Herbier_domain.Observation
module Observation_id = Herbier_domain.Ids.Observation_id
module Plant = Herbier_domain.Plant
module Tag = Herbier_domain.Tag
module Tag_id = Herbier_domain.Ids.Tag_id
module Plant_id = Herbier_domain.Ids.Plant_id
module References = Herbier_store.References
module Reference = Herbier_domain.Reference
module Projection = Herbier_refs.Projection
module Organ_photos = Herbier_refs.Organ_photos
module Ref_images = Herbier_store.Ref_images
module W = Widgets

let cls = Html.cls
let button = Html.button
let log_error = Log.db ~scope:"fiche"

(* What the fiche shows, loaded on entry and after each save. *)
type data = {
  plant : Plant.t;
  tags : Tag.t list;
  all_tags : Tag.t list;
  observations : Observation.t list; (* newest first *)
  photos : Herbier_domain.Photo.t list;
  references : Reference.t list;
  plant_refs : Reference.Plant_ref.t list;
  ref_images : Reference.Image.t list;
  loaded_at : Ptime.t; (* the « mis à jour il y a … » reference instant *)
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
      let* photos = Db.all db (Photos.of_plant id) in
      let* references = Db.all db (References.of_plant id) in
      let* plant_refs = Db.all db (References.plant_refs id) in
      (* A device-only cache the next sync rebuilds: a read error shows no
         organ photos rather than no fiche. *)
      let+ ref_images =
        Fut.map
          (function
            | Ok rows -> Ok rows
            | Error e ->
                log_error "ref_images" e;
                Ok [])
          (Db.all db (Ref_images.of_plant id))
      in
      Some
        {
          plant;
          tags;
          all_tags;
          observations;
          photos;
          references;
          plant_refs;
          ref_images;
          loaded_at = Ptime_clock.now ();
        }

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
    Html.button ["species__obs"]
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
  (* style: the page in view, written by the scroll listener. *)
  let page = ref 0 in
  let b_page_tap =
    Rb.listen pager Ev.click (fun _ ->
        match List.nth_opt ordered !page with
        | Some (ph : Herbier_domain.Photo.t) ->
            Route.go (Route.Modal (Route.Viewer ph.id))
        | None -> ())
  in
  let b_pager =
    Rb.listen pager Ev.scroll (fun _ ->
        let w = El.bound_w pager in
        match w > 0. with
        | false -> ()
        | true ->
            let i = Float.to_int (Float.round (El.scroll_x pager /. w)) in
            let i = max 0 (min (List.length ordered - 1) i) in
            page := i;
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
    [b_pager; b_page_tap] )

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

(* 4g / 6k: [host] is the screen root, so the layer is neither clipped by the
   scrolled body nor re-rendered with this block. *)
let unlinked app ~host ~problem (data : data React.signal) id () =
  let state = App.state app in
  let offline_text = El.span [] in
  let identify = W.Button.v ~kind:W.Button.Primary Free_name.identify_label in
  El.prepend_children identify.el [W.Identify_glyph.el ~size:20 ()];
  El.set_class (Jstr.v "species__identify") true identify.el;
  let search = W.Button.v ~kind:W.Button.Secondary Free_name.search_label in
  let line = El.p ~at:[cls "species__identify-line"] [] in
  let online =
    React.S.map ~eq:Bool.equal
      (fun (n : State.network) -> n.online)
      (State.network state)
  in
  let gate = App.identify_gate app in
  let sent_of (d : data) =
    Free_name.sent ~observations:d.observations ~photos:d.photos
  in
  let n_sent =
    React.S.map ~eq:Int.equal
      (fun d ->
        match sent_of d with Some s -> List.length s.photos | None -> 0)
      data
  in
  let enabled =
    React.S.l2 ~eq:Bool.equal
      (fun g photos -> Free_name.identify_enabled g ~photos)
      gate n_sent
  in
  let line_text =
    React.S.l2
      ~eq:(Option.equal String.equal)
      (fun g photos -> Free_name.identify_line g ~photos)
      gate n_sent
  in
  let resolving, set_resolving = React.S.create ~eq:Bool.equal false in
  let launcher = Identify.launcher ~button:identify.el ~problem in
  let channel = App.channel () in
  let ended ?message () =
    match Identify.released launcher with
    | true -> ()
    | false ->
        set_resolving false;
        Option.iter problem message
  in
  let linked_to taxon name =
    Fut.await (App.link app ~name id taxon) (function
      | Ok () -> ended ()
      | Error App.Plant_gone -> ended ~message:Free_name.plant_gone ()
      | Error (App.Store e) ->
          log_error "lier" e;
          ended ~message:Free_name.link_failed ())
  in
  (* Nothing is written before GBIF answers, so a fiche left meanwhile drops
     the choice, as 6i does. *)
  let choose p =
    set_resolving true;
    Fut.await (App.resolve_choice p) (fun r ->
        match Identify.released launcher with
        | true -> ()
        | false -> (
            match Free_name.link Choice.(resolved (v p) r) with
            | Link {name; taxon} -> linked_to taxon name
            | (Unknown_to_gbif | Gbif_unavailable) as l ->
                ended ?message:(Free_name.problem l) ()))
  in
  let open_layer () =
    match
      ( Identify.is_open launcher,
        React.S.value resolving,
        React.S.value enabled,
        sent_of (React.S.value data) )
    with
    | false, false, true, Some s ->
        problem "";
        let photos =
          List.map
            (fun (p : Herbier_domain.Photo.t) ->
              {
                Identify.image = App.Stored p.id;
                organ = Herbier_identify.Organ.Auto;
              })
            s.photos
        in
        Identify.launch launcher ~on_resolve:choose
          (fun ~problem:deferred ~on_close ->
            Identify.open_ ~host
              (Identify.services app channel)
              ~caller:(Caller.Free_name id)
              ~add_photo:
                (Identify.gallery_adder app s.observation ~problem:deferred)
              ~on_close photos)
    | true, _, _, _
    | false, true, _, _
    | false, false, false, _
    | false, false, true, None ->
        ()
  in
  ( El.section
      ~at:[cls "species__reference"]
      [
        El.h2 ~at:[cls "t-section-label-ref"] [El.txt' "Référence"];
        El.p
          ~at:[cls "t-body"]
          [El.txt' "Aucune espèce de référence liée."; offline_text];
        El.div ~at:[cls "species__reference-actions"] [identify.el; search.el];
        line;
      ],
    List.concat
      [
        [
          Rb.text offline_text
            (React.S.map
               (fun online ->
                 Herbier_ui_model.Network_text.unlinked_offline ~online)
               online);
          Rb.act identify.click open_layer;
          Identify.release launcher;
          Rb.disabled identify.el (React.S.map not enabled);
          Rb.attr identify.el "aria-label"
            (React.S.l2
               (fun g photos -> Some (Free_name.identify_aria g ~photos))
               gate n_sent);
          Rb.attr identify.el "aria-busy"
            (React.S.map
               (function true -> Some "true" | false -> None)
               resolving);
          Rb.text line (React.S.map (Option.value ~default:"") line_text);
          Rb.class_ line "is-hidden" (React.S.map Option.is_none line_text);
          (* The search needs GBIF. *)
          Rb.disabled search.el (React.S.map not online);
          Rb.act search.click (fun () ->
              match React.S.value online with
              | true -> Route.go (Route.Modal (Route.Link_species id))
              | false -> ());
        ];
        identify.bindings;
        search.bindings;
      ] )

(* The projection and the thumbnails 4f shows, from one load. *)
let project (d : data) =
  let p =
    Projection.project ~references:d.references ~plant_refs:d.plant_refs
  in
  let wanted = Projection.organ_photos_wanted p in
  (p, Organ_photos.shown ~wanted ~stored:d.ref_images)

let ref_row key ?(key_cls = []) value sources =
  El.div
    ~at:[cls "species__ref-row"]
    [
      El.div ~at:(List.map cls ("species__ref-key" :: key_cls)) [El.txt' key];
      El.div
        ~at:[cls "species__ref-value"]
        (value
        @
        match sources with
        | "" -> []
        | s -> [El.div ~at:[cls "species__ref-sources"] [El.txt' s]]);
    ]

let origin_side label = function
  | None -> []
  | Some names -> [El.div [El.b [El.txt' label]; El.txt' (" " ^ names)]]

(* 5e read-only over the organ photos, at this organ. *)
let organ_tile id (organ, path) =
  let label = Ref_text.organ_label organ in
  let tile =
    button
      ~label:(Printf.sprintf "Voir la photo %s en plein écran" label)
      ["species__organ"]
      [
        W.Preview_img.v ~cls:["species__organ-img"] path;
        El.span ~at:[cls "species__organ-label"] [El.txt' label];
      ]
  in
  let click, b_click = Rb.click tile in
  ( tile,
    [
      b_click;
      Rb.act click (fun () ->
          Route.go (Route.Modal (Route.Reference_photo {plant = id; organ})));
    ] )

let link_anchor (l : Ref_block.link) =
  El.a
    ~at:
      [
        cls "species__ref-link";
        At.href (Jstr.v l.url);
        At.v (Jstr.v "target") (Jstr.v "_blank");
        At.v (Jstr.v "rel") (Jstr.v "noopener noreferrer");
      ]
    [El.txt' l.label]

let names_others_id = "species-names-others"

(* « Noms »: the French names, the other languages behind « Autres langues »;
   without French names, the others are shown directly. *)
let names_row ~opened ~set_opened ~french ~others sources =
  let line (v : Projection.vernacular) =
    El.div
      [
        El.b [El.txt' (Projection.Lang.to_string v.lang)];
        El.txt' (" " ^ Ref_text.names_line v);
      ]
  in
  match (french, others) with
  | [], _ -> (ref_row "Noms" (List.map line others) sources, [])
  | _ :: _, [] ->
      (ref_row "Noms" [El.div [El.txt' (String.concat ", " french)]] sources, [])
  | _ :: _, _ :: _ ->
      let more =
        button
          ~at:[At.v (Jstr.v "aria-controls") (Jstr.v names_others_id)]
          ["species__names-more"]
          [
            El.span [El.txt' Ref_text.other_languages];
            El.span
              ~at:[cls "species__names-chevron"]
              [W.Icon.el W.Icon.Chevron_right];
          ]
      in
      let list =
        El.div
          ~at:[cls "species__names-others"; At.id (Jstr.v names_others_id)]
          (List.map line others)
      in
      let click, b_click = Rb.click more in
      ( ref_row "Noms"
          [El.div [El.txt' (String.concat ", " french)]; more; list]
          sources,
        [
          b_click;
          Rb.act click (fun () -> set_opened (not (React.S.value opened)));
          Rb.attr more "aria-expanded"
            (React.S.map (fun o -> Some (Bool.to_string o)) opened);
          Rb.class_ list "is-hidden" (React.S.map not opened);
        ] )

(* Full width, its caption above the grid (handoff 4f): not a key/value
   row. *)
let organ_block id ~photos ~credits ~sources =
  let tiles = List.map (organ_tile id) photos in
  ( El.div
      ~at:[cls "species__organ-block"]
      [
        El.div
          ~at:[cls "species__organ-caption"]
          [El.txt' ("Photos par organe · " ^ sources)];
        El.div ~at:[cls "species__organs"] (List.map fst tiles);
        El.div ~at:[cls "species__ref-sources"] [El.txt' credits];
      ],
    List.concat_map snd tiles )

let row_el ~opened ~set_opened id = function
  | Ref_block.Names {french; others; sources} ->
      names_row ~opened ~set_opened ~french ~others sources
  | Organ_photos {photos; credits; sources} ->
      organ_block id ~photos ~credits ~sources
  | Life_form {text; sources} ->
      (ref_row "Type" [El.div [El.txt' text]] sources, [])
  | Origin {native; introduced; sources} ->
      ( ref_row "Origine"
          (origin_side "Indigène :" native
          @ origin_side "Introduite :" introduced)
          sources,
        [] )
  | Red_list {chip; sources} ->
      ( ref_row "Liste rouge"
          [
            El.div
              ~at:[cls "species__ref-chips"]
              [El.span ~at:[cls "species__ref-chip"] [El.txt' chip]];
          ]
          sources,
        [] )
  | Flowering {months; text; sources} ->
      ( ref_row "Floraison"
          [W.Month_grid.v months; El.div [El.txt' text]]
          sources,
        [] )
  | Habitat {phrase; chips; sources} ->
      ( ref_row "Habitat"
          (List.map (fun p -> El.div [El.txt' p]) (Option.to_list phrase)
          @
          match chips with
          | [] -> []
          | _ :: _ ->
              [
                El.div
                  ~at:[cls "species__ref-chips"]
                  (List.map
                     (fun c ->
                       El.span ~at:[cls "species__habitat-chip"] [El.txt' c])
                     chips);
              ])
          sources,
        [] )
  | Toxicity {text; sources} ->
      (ref_row "Toxicité" [El.div [El.txt' text]] sources, [])
  | Links links ->
      (El.div ~at:[cls "species__ref-links"] (List.map link_anchor links), [])

(* 4f *)
let linked app (data : data React.signal) () =
  let id = (React.S.value data).plant.id in
  let online =
    React.S.map ~eq:Bool.equal
      (fun (n : State.network) -> n.online)
      (State.network (App.state app))
  in
  let fetching =
    React.S.map ~eq:Bool.equal
      (List.exists (Plant_id.equal id))
      (App.fetching app)
  in
  let projection = React.S.map ~eq:( == ) project data in
  let meta = El.span ~at:[cls "t-meta"; cls "species__ref-meta"] [] in
  let refresh =
    W.Icon_button.el ~label:"Mettre à jour la référence" W.Icon.Refresh
  in
  let click, b_click = Rb.click refresh in
  let rows = El.div ~at:[cls "species__ref-slot"] [] in
  let opened, set_opened = React.S.create ~eq:Bool.equal false in
  let set_opened o = set_opened o in
  let rows_of ((p, shown), fetching) =
    let content =
      match (Ref_block.rows p ~organ_photos:shown, fetching) with
      | (_ :: _ as rows), _ -> List.map (row_el ~opened ~set_opened id) rows
      | [], true ->
          [
            ( El.p ~at:[cls "t-meta"] [El.txt' "Récupération de la référence…"],
              [] );
          ]
      | [], false ->
          [
            ( El.p
                ~at:[cls "t-meta"]
                [El.txt' "Référence indisponible pour l'instant."],
              [] );
          ]
    in
    ( El.div ~at:[cls "species__ref-rows"] (List.map fst content),
      List.concat_map snd content )
  in
  ( El.section
      ~at:[cls "species__reference"]
      [
        El.div
          ~at:[cls "species__ref-head"]
          [
            El.h2 ~at:[cls "t-section-label-ref"] [El.txt' "Référence"];
            meta;
            refresh;
          ];
        rows;
      ],
    [
      b_click;
      Rb.act click (fun () -> App.refresh app id);
      Rb.disabled refresh
        (React.S.l2 ~eq:Bool.equal
           (fun fetching online -> fetching || not online)
           fetching online);
      Rb.class_ refresh "is-offline" (React.S.map not online);
      Rb.text meta
        (React.S.l4 ~eq:String.equal
           (fun d ((p : Projection.t), _) fetching online ->
             let date =
               match (fetching, p.fetched_at) with
               | true, _ -> "mise à jour…"
               | false, Some t -> "mis à jour " ^ Fr_date.ago ~now:d.loaded_at t
               | false, None -> "pas encore récupérée"
             in
             match online with true -> date | false -> date ^ " · hors-ligne")
           data projection fetching online);
      Rb.view rows rows_of
        (React.S.l2 ~eq:( == ) (fun p f -> (p, f)) projection fetching);
    ] )

(* The fiche of a live plant. The parts [data] shows are updated in place on
   each reload, so an editor open on the fiche (the notes, « + tag ») stays
   open across one. *)
let render app ~host (data : data React.signal) =
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
  Transition.mark_hero hero id;
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
          Rb.act grid.tap (fun (ph : Herbier_domain.Photo.t) ->
              Route.go (Route.Modal (Route.Viewer ph.id)))
          :: grid.bindings )
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
  let reference = El.div ~at:[cls "species__reference-slot"] [] in
  let reference_of = function
    | false -> unlinked app ~host ~problem data id ()
    | true -> linked app data ()
  in
  (* The block is swapped once the update step that changed [data] is over:
     [linked] derives signals from [data] (its [Rb.view] reads the first
     value), and a signal derived from [data] in the step where [data]
     changes has no value yet ([Failure "signal value undefined yet"]). A
     link made from 6k, with this fiche shown, is such a step. *)
  let is_linked (d : data) = Option.is_some d.plant.gbif_key in
  let linked_s, set_linked =
    React.S.create ~eq:Bool.equal (is_linked (React.S.value data))
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
          Rb.act
            (React.S.changes (React.S.map ~eq:Bool.equal is_linked data))
            (fun v -> set_linked v);
          Rb.view reference reference_of linked_s;
        ];
        adder.bindings;
        notes_bindings;
      ] )

(* A plant that is not (or no longer) live, or a fiche that could not be
   read: the reason under ←. *)
let notice text =
  let back = W.Icon_button.el ~label:"Retour" W.Icon.Arrow_back in
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
  (* Once per entry, never on the reloads the fetch itself causes, which
     would loop on a plant still due. *)
  App.refresh_if_due app id;
  (* [ready] once the first load is shown, whatever it found ([Loaded.live]
     renders again after a reload): the hero transition from Collection waits
     for the hero. *)
  let ready, mark_ready = Screen.once () in
  {
    Screen.el;
    bindings =
      Loaded.live ~reload:(App.saved app) ~what:"fiche"
        ~gone:(fun () ->
          mark_ready ();
          notice "Cette plante n'est plus dans l'herbier.")
        ~failed:(fun () ->
          mark_ready ();
          notice "La fiche n'a pas pu être lue.")
        el
        (fun () -> load (App.db app) id)
        (fun data ->
          mark_ready ();
          render app ~host:el data);
    ready;
  }
