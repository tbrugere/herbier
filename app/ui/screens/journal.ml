module Collection_filter = Herbier_ui_model.Collection_filter
module Fr_date = Herbier_ui_model.Fr_date
module Fr_text = Herbier_ui_model.Fr_text
module Journal_day = Herbier_ui_model.Journal_day
module Journal_filter = Herbier_ui_model.Journal_filter
open Brr
module Db = Herbier_store_io.Db
module Plants = Herbier_store.Plants
module Tags = Herbier_store.Tags
module Observations = Herbier_store.Observations
module Observation = Herbier_domain.Observation
module Plant = Herbier_domain.Plant
module Tag = Herbier_domain.Tag
module Plant_id = Herbier_domain.Ids.Plant_id
module Tag_id = Herbier_domain.Ids.Tag_id
module RList = ReactiveData.RList
module W = Widgets

let cls = Html.cls
let offset (o : Observation.t) = Zone.offset_s o.at
let date (o : Observation.t) = Zone.date o.at
let year (o : Observation.t) = Zone.year o.at

(* What the list is built from, loaded on entry and after each save. *)
type data = {
  observations : Observation.t list;
  names : (Plant_id.t * string) list;
  tags : Tag.t list;
  links : Tag.Plant_tag.t list;
}

let row names (o : Observation.t) =
  let time = Fr_date.time ~tz_offset_s:(offset o) o.at in
  let r =
    match o.plant_id with
    | Some id ->
        let title = Journal_day.plant_name names id in
        let meta =
          match o.note with Some _ -> time ^ " · note" | None -> time
        in
        W.List_row.v ~thumb:W.List_row.Placeholder ~title ~meta ()
    | None ->
        let meta =
          match o.note with
          | Some n -> Printf.sprintf "%s · « %s »" time n
          | None -> time
        in
        W.List_row.v ~thumb:W.List_row.Placeholder ~tone:W.List_row.To_identify
          ~title:"À identifier" ~meta ()
  in
  let target =
    match o.plant_id with
    | Some _ -> Route.Observation o.id
    | None -> Route.Identify o.id
  in
  (r.el, Rb.act r.click (fun () -> Route.go (Route.Modal target)) :: r.bindings)

let day_place state (d : Observation.t Journal_day.t) =
  match (Journal_day.place d.items, Herbier_geo.Features.bounds d.items) with
  | None, _ -> ([], [])
  | Some p, None -> ([El.span ~at:[cls "journal__place"] [El.txt' p]], [])
  | Some p, Some b ->
      let button =
        Html.button
          ~label:("Voir sur la carte : " ^ p)
          ["journal__place"]
          [El.txt' (p ^ " "); W.Icon.el ~size:14 W.Icon.My_location]
      in
      let click, b_click = Rb.click button in
      ( [button],
        [
          b_click;
          Rb.act click (fun () ->
              State.focus_map state b;
              Route.go (Route.Tab W.Tab_bar.Map));
        ] )

let day state ~this_year names (d : Observation.t Journal_day.t) =
  let place, place_bindings = day_place state d in
  let rows = List.map (row names) d.items in
  let el =
    El.section
      ~at:[cls "journal__day"]
      (El.div
         ~at:[cls "journal__day-header"]
         (El.h2
            ~at:[cls "journal__date"]
            [El.txt' (Fr_date.day_header ~this_year d.date)]
         :: place)
      :: List.map fst rows)
  in
  (el, place_bindings @ List.concat_map snd rows)

let log_error e = Log.db "journal" e

let v app =
  let db = App.db app and state = App.state app in
  let days, days_handle = RList.create [] in
  let chips, chips_handle = RList.create [] in
  let counter, set_counter = React.S.create "" in
  let empty_text, set_empty_text = React.S.create "" in
  let filters = State.filters state in
  (* style: the loaded data, read and written only outside update steps
     ([Rb.act] handlers, future callbacks). *)
  let data = ref {observations = []; names = []; tags = []; links = []} in
  let render () =
    let f = React.S.value filters and d = !data in
    let tagged = Collection_filter.tagged d.links f.tags in
    let shown =
      List.filter
        (Journal_filter.keep ~year_of:year ~year:f.year
           ~to_identify_only:f.to_identify_only ~tagged)
        d.observations
    in
    set_empty_text
      (match (shown, d.observations) with
      | _ :: _, _ -> ""
      | [], [] -> "Aucune observation pour l’instant."
      | [], _ :: _ -> "Aucune observation pour ces filtres.");
    RList.set days_handle (Journal_day.group ~date shown)
  in
  let load () =
    let open Fut.Result_syntax in
    let fut =
      let* observations = Db.all db Observations.list in
      let* plants = Db.all db Plants.list in
      let* tags = Db.all db Tags.list in
      let+ links = Db.all db Tags.links in
      {
        observations;
        names = List.map (fun (p : Plant.t) -> (p.id, p.display_name)) plants;
        tags;
        links;
      }
    in
    Fut.await fut (function
      | Error e ->
          log_error e;
          set_counter "Lecture impossible"
      | Ok d ->
          data := d;
          set_counter
            (Fr_text.plural
               (List.length d.observations)
               "observation" "observations");
          (* Chips are rebuilt with the data: years and the « À identifier »
             count change with it. *)
          RList.set chips_handle
            (Filter_chips.chips ~year_of:year (React.S.value filters)
               d.observations d.tags);
          render ())
  in
  load ();
  let counter_el = El.p ~at:[cls "journal__counter"] [] in
  let chips_el = El.div ~at:[cls "chip-row"] [] in
  let list_el = El.div ~at:[cls "journal__days"] [] in
  let empty = El.p ~at:[cls "journal__empty"; cls "t-meta"] [] in
  let el =
    El.div
      ~at:[cls "screen"; cls "journal"]
      [
        El.div
          ~at:[cls "journal__header"]
          [El.h1 ~at:[cls "t-screen-title"] [El.txt' "Journal"]; counter_el];
        chips_el;
        list_el;
        empty;
      ]
  in
  let names () = !data.names in
  let this_year () = Zone.this_year () in
  {
    Screen.el;
    bindings =
      [
        Rb.text counter_el counter;
        Rb.rlist chips_el (Filter_chips.el state) chips;
        Rb.rlist list_el
          (fun d -> day state ~this_year:(this_year ()) (names ()) d)
          days;
        Rb.text empty empty_text;
        Rb.class_ empty "is-hidden" (React.S.map (String.equal "") empty_text);
        Rb.act (React.S.changes filters) (fun _ -> render ());
        Rb.act (App.saved app) load;
      ];
  }
