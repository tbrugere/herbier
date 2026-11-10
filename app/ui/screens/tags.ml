open Brr
module W = Widgets

let cls c = At.class' (Jstr.v c)
let top = 4

let by_use (a : Tag_usage.t) (b : Tag_usage.t) =
  Int.compare (List.length b.plants) (List.length a.plants)

let v app =
  let state = App.state app in
  let subtitle = El.p ~at:[cls "t-meta"] [] in
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
  let manage = W.Button.text "Gérer" in
  let pick (u : Tag_usage.t) () =
    State.set_filters state
      {(React.S.value (State.filters state)) with tags = [u.tag.id]};
    (* 4l is opened from Collection: going back returns there without
       leaving 4l in the history for Android back. *)
    Route.back ()
  in
  (* Cards and chips are lists filled once the tags are loaded: [Rb.rlist]
     owns their bindings. *)
  let cards, cards_handle = ReactiveData.RList.create [] in
  let chips, chips_handle = ReactiveData.RList.create [] in
  let card (u : Tag_usage.t) =
    let el =
      El.button
        ~at:[At.type' (Jstr.v "button"); cls "tag-card"]
        [
          El.div
            ~at:[cls "tag-card__names"]
            [
              El.div ~at:[cls "tag-card__name"] [El.txt' u.tag.name];
              El.div
                ~at:[cls "tag-card__count"]
                [
                  El.txt'
                    (Fr_text.plural (List.length u.plants) "plante" "plantes");
                ];
            ];
        ]
    in
    let click, b = Rb.click el in
    (el, [b; Rb.act click (pick u)])
  in
  let chip (u : Tag_usage.t) =
    let el =
      El.button
        ~at:[At.type' (Jstr.v "button"); cls "tag-chip"]
        [
          El.txt' (u.tag.name ^ " ");
          El.span
            ~at:[cls "tag-chip__count"]
            [El.txt' (string_of_int (List.length u.plants))];
        ]
    in
    let click, b = Rb.click el in
    (el, [b; Rb.act click (pick u)])
  in
  Fut.await
    (Tag_usage.load (App.db app))
    (function
      | Error e ->
          Console.(error [str "tags"; str (Herbier_store.Db.error_to_string e)]);
          El.set_children subtitle [El.txt' "Lecture impossible"]
      | Ok [] -> El.set_children subtitle [El.txt' "Aucun tag pour l’instant."]
      | Ok usage ->
          El.set_children subtitle
            [
              El.txt'
                (Fr_text.plural (List.length usage) "tag" "tags"
                ^ " · touchez pour filtrer la collection");
            ];
          let sorted = List.stable_sort by_use usage in
          ReactiveData.RList.set cards_handle
            (List.filteri (fun i _ -> i < top) sorted);
          ReactiveData.RList.set chips_handle
            (List.filteri (fun i _ -> i >= top) sorted));
  let grid = El.div ~at:[cls "tags__grid"] []
  and chip_row = El.div ~at:[cls "tags__chips"] [] in
  let el =
    El.div
      ~at:[cls "screen"; cls "tags"]
      [
        El.div ~at:[cls "modal-header"] [back; El.span []; manage.el];
        El.div [El.h1 ~at:[cls "t-screen-title"] [El.txt' "Tags"]; subtitle];
        grid;
        chip_row;
      ]
  in
  {
    Screen.el;
    bindings =
      Rb.rlist grid card cards
      :: Rb.rlist chip_row chip chips
      :: b_back
      :: Rb.act back_click Route.back
      :: Rb.act manage.click (fun () ->
          Route.go (Route.Modal Route.Manage_tags))
      :: manage.bindings;
  }
