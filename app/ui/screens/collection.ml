open Brr
module Db = Herbier_store.Db
module Plants = Herbier_store.Plants
module Tags = Herbier_store.Tags
module Search = Herbier_store.Search
module Observations = Herbier_store.Observations
module Plant = Herbier_domain.Plant
module Tag = Herbier_domain.Tag
module Plant_id = Herbier_domain.Ids.Plant_id
module Tag_id = Herbier_domain.Ids.Tag_id
module RList = ReactiveData.RList
module W = Widgets
module Filter = Collection_filter

type item = {plant : Plant.t; observations : int}

let same a b = Plant_id.equal a.plant.id b.plant.id

let equal a b =
  same a b
  && Ptime.equal a.plant.updated_at b.plant.updated_at
  && Int.equal a.observations b.observations

(* French: 0 and 1 take the singular. *)
let plural n one many =
  Printf.sprintf "%d %s" n (match n with 0 | 1 -> one | _ -> many)

let card item =
  let mention = Printf.sprintf "sans photo · %d obs." item.observations in
  let c =
    W.Card.plant ~name:item.plant.display_name ~sci:item.plant.scientific_name
      (W.Card.No_photo mention)
  in
  (c.el, c.bindings)

let log_error what e =
  Console.(error [str ("collection: " ^ what); str (Db.error_to_string e)])

(* The plants of the grid for a search text and a set of tags (all
   required), in the store's order. *)
let visible db ~counts ~text ~tags =
  let open Fut.Result_syntax in
  let base =
    match Search.plants text with None -> Plants.list | Some q -> q
  in
  let* plants = Db.all db base in
  let+ tagged =
    List.fold_left
      (fun acc tag ->
        let* acc = acc in
        let+ ps = Db.all db (Plants.with_tag tag) in
        List.map (fun (p : Plant.t) -> p.id) ps :: acc)
      (Fut.ok []) tags
  in
  List.filter_map
    (fun (p : Plant.t) ->
      match Filter.has_all_tags ~tagged p.id with
      | false -> None
      | true -> Some {plant = p; observations = Filter.count counts p.id})
    plants

let apply handle =
  List.iter (function
    | List_patch.Remove i -> RList.remove i handle
    | List_patch.Insert (i, v) -> RList.insert v i handle
    | List_patch.Update (i, v) -> RList.update v i handle)

let toggle tag tags =
  match List.exists (Tag_id.equal tag) tags with
  | true -> List.filter (fun t -> not (Tag_id.equal t tag)) tags
  | false -> tag :: tags

let v app =
  let db = App.db app and state = App.state app in
  let grid, grid_handle = RList.create [] in
  let tags, tags_handle = RList.create [] in
  let counter, set_counter = React.S.create "" in
  let failure, set_failure = React.S.create "" in
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
          State.set_filters state {f with tags = toggle tag.id f.tags})
    in
    (chip.el, set :: chip.bindings)
  in
  let chip_list = El.div ~at:[At.class' (Jstr.v "chip-row__items")] [] in
  (* style: [shown] is the grid's current content, [seq] the number of the
     latest query and [counts] the observations per plant from the last load,
     all read and written from future callbacks and [Rb.act] handlers only
     (outside update steps); a reply to an older query is dropped. *)
  let shown = ref [] and seq = ref 0 and counts = ref (Filter.counts []) in
  let refresh () =
    incr seq;
    let mine = !seq in
    let text = React.S.value search.value in
    let tags = React.S.value active_tags in
    Fut.await (visible db ~counts:!counts ~text ~tags) (function
      | Error e when mine = !seq ->
          log_error "query" e;
          set_failure
            "Recherche impossible : la grille montre le résultat précédent."
      | Ok next when mine = !seq ->
          set_failure "";
          apply grid_handle (List_patch.diff ~same ~equal !shown next);
          shown := next
      | Error _ | Ok _ -> ())
  in
  (* The load's result arrives through [loaded], so that a released screen
     ([Rb.act] stopped) neither writes its state nor starts a query. *)
  let loaded, send_loaded = React.E.create () in
  let on_loaded = function
    | Error e ->
        log_error "load" e;
        set_counter "Lecture impossible"
    | Ok (observations, plants, all_tags) ->
        counts := Filter.counts observations;
        set_counter
          (plural (List.length plants) "plante" "plantes"
          ^ " · "
          ^ plural (List.length observations) "observation" "observations");
        RList.set tags_handle all_tags;
        refresh ()
  in
  let load () =
    let open Fut.Result_syntax in
    let fut =
      let* observations = Db.all db Observations.list in
      let* plants = Db.all db Plants.list in
      let+ all_tags = Db.all db Tags.list in
      (observations, plants, all_tags)
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
        search.el;
        chips_el;
        failure_el;
        grid_el;
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
        search.bindings;
        all.bindings;
        tags_link.bindings;
      ]
  in
  {Screen.el; bindings}
