module Fr_text = Herbier_ui_model.Fr_text
module List_patch = Herbier_ui_model.List_patch
module Tag_edits = Herbier_ui_model.Tag_edits
module Tag = Herbier_domain.Tag
module Plant_id = Herbier_domain.Ids.Plant_id
module Tag_id = Herbier_domain.Ids.Tag_id
open Brr
module W = Widgets

let cls = Html.cls
let top = 4

let by_use (a : Tag_usage.t) (b : Tag_usage.t) =
  Int.compare (List.length b.plants) (List.length a.plants)

let same (a : Tag_usage.t) (b : Tag_usage.t) = Tag_id.equal a.tag.id b.tag.id

(* Everything a card or chip shows, and the plants its editor opens on. *)
let unchanged (a : Tag_usage.t) (b : Tag_usage.t) =
  Tag.equal a.tag b.tag && List.equal Plant_id.equal a.plants b.plants

let editing (u : Tag_usage.t) = Tag_edits.Edit {tag = u.tag; plants = u.plants}
let count (u : Tag_usage.t) = List.length u.plants

let v app =
  let state = App.state app in
  let tags, set_tags = React.S.create ~eq:( == ) [] in
  (* [tags] is the store's as of a read that succeeded and no save of the box
     came after it: only then can a name be checked against it. *)
  let fresh, set_fresh = React.S.create false in
  let when_fresh f () =
    match React.S.value fresh with true -> f () | false -> ()
  in
  let subtitle, set_subtitle = React.S.create "" in
  let editor = Tag_editor.v app ~tags in
  let back = W.Icon_button.el ~label:"Retour" W.Icon.Arrow_back in
  let back_click, b_back = Rb.click back in
  let add = W.Fab.v ~label:"Nouveau tag" W.Icon.Add in
  let pick (u : Tag_usage.t) () =
    State.set_filters state
      {(React.S.value (State.filters state)) with tags = [u.tag.id]};
    (* 4l is opened from Collection: going back returns there without
       leaving 4l in the history for Android back. *)
    Route.back ()
  in
  let edit u = when_fresh (fun () -> editor.open_ (editing u)) in
  (* The pencil is a sibling of the main button: a button inside a button is
     invalid HTML, and its click would also reach the main one and filter. *)
  let press main pencil u =
    let press = Long_press.v main in
    let pencil_click, b_pencil = Rb.click pencil in
    b_pencil
    :: Rb.act press.tap (pick u)
    :: Rb.act press.long (edit u)
    :: Rb.act pencil_click (edit u)
    :: press.bindings
  in
  (* Cards and chips are lists filled once the tags are loaded: [Rb.rlist]
     owns their bindings. *)
  let cards, cards_handle = ReactiveData.RList.create [] in
  let chips, chips_handle = ReactiveData.RList.create [] in
  let card (u : Tag_usage.t) =
    let main =
      Html.button ["tag-card__main"]
        [
          El.div
            ~at:[cls "tag-card__names"]
            [
              El.div ~at:[cls "tag-card__name"] [El.txt' u.tag.name];
              El.div
                ~at:[cls "tag-card__count"]
                [El.txt' (Fr_text.plural (count u) "plante" "plantes")];
            ];
        ]
    in
    let pencil =
      W.Icon_button.el ~classes:["tag-card__edit"]
        ~label:(Tag_edits.edit_label u.tag)
        W.Icon.Edit
    in
    (El.div ~at:[cls "tag-card"] [main; pencil], press main pencil u)
  in
  let chip (u : Tag_usage.t) =
    let main =
      Html.button ["tag-chip__main"]
        [
          El.txt' (u.tag.name ^ " ");
          El.span
            ~at:[cls "tag-chip__count"]
            [El.txt' (string_of_int (count u))];
        ]
    in
    let pencil =
      Html.button
        ~label:(Tag_edits.edit_label u.tag)
        ["tag-chip__edit"]
        [W.Icon.el ~size:18 W.Icon.Edit]
    in
    (El.span ~at:[cls "tag-chip"] [main; pencil], press main pencil u)
  in
  (* style: the number of the last read started, written from [load] only
     (DOM handlers and future callbacks): a slower earlier read never
     overwrites a later one; [shown_*]: the cards' and chips' current content,
     patched rather than rebuilt so that a reload keeps a press under way and
     the focus. *)
  let reads = ref 0 and shown_cards = ref [] and shown_chips = ref [] in
  let patch handle shown next =
    Rb.patch handle (List_patch.diff ~same ~equal:unchanged !shown next);
    shown := next
  in
  let load () =
    incr reads;
    let read = !reads in
    Fut.await
      (Tag_usage.load (App.db app))
      (fun result ->
        match Int.equal read !reads with
        | false -> ()
        | true -> (
            set_subtitle (Tag_edits.subtitle (Result.map List.length result));
            match result with
            | Error e ->
                Console.(
                  error
                    [str "tags"; str (Herbier_store_io.Db.error_to_string e)]);
                set_fresh false
            | Ok usage ->
                let sorted = List.stable_sort by_use usage in
                let step = React.Step.create () in
                set_tags ~step (List.map (fun (u : Tag_usage.t) -> u.tag) usage);
                set_fresh ~step true;
                React.Step.execute step;
                patch cards_handle shown_cards (List.take top sorted);
                patch chips_handle shown_chips (List.drop top sorted)))
  in
  load ();
  let subtitle_el = El.p ~at:[cls "t-meta"] [] in
  let grid = El.div ~at:[cls "tags__grid"] []
  and chip_row = El.div ~at:[cls "tags__chips"] [] in
  let el =
    El.div
      ~at:[cls "screen"; cls "tags"]
      [
        El.div ~at:[cls "modal-header"] [back; El.span []];
        El.div [El.h1 ~at:[cls "t-screen-title"] [El.txt' "Tags"]; subtitle_el];
        grid;
        chip_row;
        add.el;
        editor.el;
      ]
  in
  {
    Screen.el;
    ready = Screen.now;
    bindings =
      Rb.rlist grid card cards
      :: Rb.rlist chip_row chip chips
      :: Rb.text subtitle_el subtitle
      :: b_back
      :: Rb.act back_click Route.back
      :: Rb.disabled add.el (React.S.map not fresh)
      :: Rb.act add.click (when_fresh (fun () -> editor.open_ Tag_edits.New))
      :: Rb.act editor.saved (fun (_ : Tag_edits.change) ->
          set_fresh false;
          load ())
      :: Rb.act (App.saved app) load
      :: (add.bindings @ editor.bindings);
  }
