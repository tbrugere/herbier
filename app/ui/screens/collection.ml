module Collection_filter = Herbier_ui_model.Collection_filter
module Cover = Herbier_ui_model.Cover
module Fr_text = Herbier_ui_model.Fr_text
module List_patch = Herbier_ui_model.List_patch
module Plant_version = Herbier_ui_model.Plant_version
open Brr
module Db = Herbier_store_io.Db
module Plants = Herbier_store.Plants
module Tags = Herbier_store.Tags
module Search = Herbier_store.Search
module Observations = Herbier_store.Observations
module Photos = Herbier_store.Photos
module Plant = Herbier_domain.Plant
module Tag = Herbier_domain.Tag
module Tag_id = Herbier_domain.Ids.Tag_id
module RList = ReactiveData.RList
module W = Widgets
module Filter = Collection_filter

type item = {plant : Plant.t; observations : int; cover_preview : string option}

let same a b = Plant_version.same a.plant b.plant

let equal a b =
  Plant_version.equal a.plant b.plant
  && Int.equal a.observations b.observations
  && Option.equal String.equal a.cover_preview b.cover_preview

let card item =
  let mention = Printf.sprintf "sans photo · %d obs." item.observations in
  let cover =
    match item.cover_preview with
    | Some path -> W.Card.Preview path
    | None -> W.Card.No_photo mention
  in
  let c =
    W.Card.plant ~name:item.plant.display_name ~sci:item.plant.scientific_name
      cover
  in
  let open_ =
    Rb.act c.click (fun () ->
        Route.go (Route.Modal (Route.Plant item.plant.id)))
  in
  Transition.mark_hero c.el item.plant.id;
  (c.el, open_ :: c.bindings)

let log_error = Log.db ~scope:"collection"

(* The plants of the grid for a search text and a set of tags (all
   required), in the store's order. *)
let visible db ~counts ~photos ~text ~tags =
  let open Fut.Result_syntax in
  let* plants = Db.all db (Search.plants_or_all text) in
  let+ links =
    match tags with [] -> Fut.ok [] | _ :: _ -> Db.all db Tags.links
  in
  let tagged = Filter.tagged links tags in
  List.filter_map
    (fun (p : Plant.t) ->
      match Filter.has_all_tags ~tagged p.id with
      | false -> None
      | true ->
          let cover_preview =
            Option.map
              (fun (ph : Herbier_domain.Photo.t) -> ph.preview_path)
              (Cover.choose p.cover_photo_id (photos p.id))
          in
          Some
            {plant = p; observations = Filter.count counts p.id; cover_preview})
    plants

let v app =
  let db = App.db app and state = App.state app in
  let grid, grid_handle = RList.create [] in
  let tags, tags_handle = RList.create [] in
  let counter, set_counter = React.S.create "" in
  let failure, set_failure = React.S.create "" in
  let empty, set_empty = React.S.create false in
  (* [ready] once the first query's grid (or a read failure) is shown: the
     hero transition from a fiche waits for its card. *)
  let ready, mark_ready = Screen.once () in
  let search =
    W.Text_field.v ~icon:W.Icon.Search ~action:"Coller un lien"
      ~placeholder:"Nom, tag, lieu…" ()
  in
  let active_tags =
    React.S.map ~eq:(List.equal Tag_id.equal)
      (fun (f : State.filters) -> f.tags)
      (State.filters state)
  in
  let all =
    W.Chip.filter ~label:"Toutes"
      ~active:
        (React.S.map (function [] -> true | _ :: _ -> false) active_tags)
      ()
  in
  let tags_link = W.Chip.link "Tags ›" in
  let tag_chip (tag : Tag.t) =
    let active = React.S.map (List.exists (Tag_id.equal tag.id)) active_tags in
    let chip = W.Chip.filter ~label:tag.name ~active () in
    let set =
      Rb.act chip.click (fun () ->
          let f = React.S.value (State.filters state) in
          State.set_filters state
            {f with tags = Filter.toggle_tag tag.id f.tags})
    in
    (chip.el, set :: chip.bindings)
  in
  let chip_list = El.div ~at:[At.class' (Jstr.v "chip-row__items")] [] in
  (* style: [shown] is the grid's current content, [seq] the number of the
     latest query, [counts] the observations per plant and [photos] the photos
     per plant from the last load, all read and written from future callbacks
     and [Rb.act] handlers only (outside update steps); a reply to an older
     query is dropped. *)
  let shown = ref []
  and seq = ref 0
  and counts = ref (Filter.counts [])
  and photos = ref (fun _ -> []) in
  let refresh () =
    incr seq;
    let mine = !seq in
    let text = React.S.value search.value in
    let tags = React.S.value active_tags in
    Fut.await (visible db ~counts:!counts ~photos:!photos ~text ~tags) (function
      | Error e when mine = !seq ->
          log_error "query" e;
          set_failure
            "Recherche impossible : la grille montre le résultat précédent.";
          mark_ready ()
      | Ok next when mine = !seq ->
          set_failure "";
          Rb.patch grid_handle (List_patch.diff ~same ~equal !shown next);
          shown := next;
          mark_ready ()
      | Error _ | Ok _ -> ())
  in
  (* The load's result arrives through [loaded], so that a released screen
     ([Rb.act] stopped) neither writes its state nor starts a query. *)
  let loaded, send_loaded = React.E.create () in
  let on_loaded = function
    | Error e ->
        log_error "load" e;
        set_counter "Lecture impossible";
        mark_ready ()
    | Ok (observations, plants, all_photos, all_tags) ->
        counts := Filter.counts observations;
        photos := Cover.by_plant observations all_photos;
        set_empty (match plants with [] -> true | _ :: _ -> false);
        set_counter
          (Fr_text.plural (List.length plants) "plante" "plantes"
          ^ " · "
          ^ Fr_text.plural (List.length observations) "observation"
              "observations");
        RList.set tags_handle all_tags;
        refresh ()
  in
  let load () =
    let open Fut.Result_syntax in
    (* Covers are decoration: a failed photo read leaves the cards without
       them, not the whole screen empty. *)
    let covers =
      Fut.map
        (function
          | Ok l -> l
          | Error e ->
              log_error "covers" e;
              [])
        (Db.all db Photos.live)
    in
    let fut =
      let* observations = Db.all db Observations.list in
      let* plants = Db.all db Plants.list in
      let* all_photos = Fut.map Result.ok covers in
      let+ all_tags = Db.all db Tags.list in
      (observations, plants, all_photos, all_tags)
    in
    Fut.await fut send_loaded
  in
  load ();
  let counter_el = El.p ~at:[At.class' (Jstr.v "collection__counter")] [] in
  let failure_el = El.p ~at:[At.class' (Jstr.v "collection__failure")] [] in
  let chips_el =
    El.div ~at:[At.class' (Jstr.v "chip-row")] [all.el; chip_list; tags_link.el]
  in
  let grid_el = El.div ~at:[At.class' (Jstr.v "card-grid")] [] in
  let first = W.Button.v ~icon:W.Icon.Add "Noter ma première plante" in
  let paste =
    W.Button.v ~kind:W.Button.Secondary "Coller un lien Pl@ntNet / GBIF"
  in
  let empty_el =
    El.div
      ~at:[At.class' (Jstr.v "collection__empty")]
      [
        El.div ~at:[At.class' (Jstr.v "collection__illustration")] [];
        El.h2
          ~at:[At.class' (Jstr.v "collection__empty-title")]
          [El.txt' "La première plante s'ajoute dehors ou depuis un lien."];
        El.p
          ~at:[At.class' (Jstr.v "t-body")]
          [
            El.txt'
              "Prenez une photo sur le terrain, ou collez un lien d'une espèce \
               vue sur Pl@ntNet, GBIF ou Wikipédia.";
          ];
        first.el;
        paste.el;
        El.p
          ~at:[At.class' (Jstr.v "t-meta")]
          [El.txt' "Google Photos se connecte plus tard, à la première photo."];
      ]
  in
  let filled =
    El.div
      ~at:[At.class' (Jstr.v "collection__filled")]
      [search.el; chips_el; failure_el; grid_el]
  in
  let el =
    El.div
      ~at:[At.class' (Jstr.v "screen"); At.class' (Jstr.v "collection")]
      [
        El.div
          [
            El.h1
              ~at:[At.class' (Jstr.v "t-screen-title")]
              [El.txt' "Collection"];
            counter_el;
          ];
        filled;
        empty_el;
      ]
  in
  let changes =
    React.E.select
      [
        React.E.map ignore (React.S.changes search.value);
        React.E.map ignore (React.S.changes active_tags);
      ]
  in
  let bindings =
    List.concat
      [
        [
          Rb.text counter_el counter;
          Rb.text failure_el failure;
          Rb.act loaded on_loaded;
          Rb.rlist chip_list tag_chip tags;
          Rb.rlist grid_el card grid;
          Rb.act changes refresh;
          Rb.act (App.saved app) load;
          Rb.act all.click (fun () ->
              let f = React.S.value (State.filters state) in
              State.set_filters state {f with tags = []});
        ];
        [
          Rb.class_ empty_el "is-hidden" (React.S.map not empty);
          Rb.class_ filled "is-hidden" empty;
          Rb.act tags_link.click (fun () -> Route.go (Route.Modal Route.Tags));
          Rb.act first.click (fun () -> Route.go (Route.Modal Route.Record));
        ];
        search.bindings;
        first.bindings;
        paste.bindings;
        all.bindings;
        tags_link.bindings;
      ]
  in
  {Screen.el; bindings; ready}
