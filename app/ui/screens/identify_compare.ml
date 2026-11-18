open Brr
module Organ = Herbier_identify.Organ
module Plantnet = Herbier_identify.Plantnet
module Proposal = Herbier_identify.Proposal
module Caller = Herbier_ui_model.Identify.Caller
module Owned = Herbier_ui_model.Identify.Owned
module Compare = Herbier_ui_model.Identify.Compare
module Text = Herbier_ui_model.Identify.Text
module W = Widgets

type t = {close : unit -> unit}

let cls = Html.cls
let attr name value = At.v (Jstr.v name) (Jstr.v value)

let txt_el tag classes text =
  El.v (Jstr.v tag) ~at:(List.map cls classes) [El.txt' text]

let pill ?(right = false) text =
  txt_el "span"
    ("identify-compare__pill"
    ::
    (match right with
    | true -> ["identify-compare__pill--right"]
    | false -> []))
    text

let loading_label () =
  txt_el "span" ["identify-compare__loading"] Text.skeleton_label

(* My photos, each built once and shown while it is the one on top, so going
   back and forth between organs does not read a stored preview again. *)
let mine_el photo =
  El.div
    ~at:[cls "identify-compare__mine"]
    (Option.to_list (photo ~cls:"identify-compare__img"))

type slide = {el : El.t; img : El.t; url : string}

let slide_el (p : Plantnet.proposal) ~count k (image : Plantnet.image) =
  let alt =
    match image.organ with
    | Some o -> p.name ^ ", " ^ Organ.label o
    | None -> p.name
  in
  let img =
    El.img
      ~at:[cls "identify-compare__img"; attr "alt" alt; attr "decoding" "async"]
      ()
  in
  let el =
    El.div
      ~at:[cls "identify-compare__slide"]
      [
        loading_label ();
        img;
        pill (Text.compare_species image.organ);
        pill ~right:true (Text.compare_image_position ~index:(k + 1) ~count);
        txt_el "span" ["identify-compare__credit"] (Proposal.credit image);
      ]
  in
  ( {el; img; url = image.medium},
    [
      Rb.listen img Ev.load (fun _ -> El.set_class (Jstr.v "is-loaded") true el);
      Rb.listen img Ev.error (fun _ ->
          El.set_class (Jstr.v "is-failed") true el;
          Console.(warn [str ("Pl@ntNet image " ^ image.medium); str "failed"]));
    ] )

let empty_slide () =
  El.div
    ~at:[cls "identify-compare__slide"; cls "identify-compare__slide--empty"]
    [txt_el "p" ["identify-compare__empty"] Text.compare_no_image]

let round ~label icon =
  Html.button ~label ["identify-compare__round"] [W.Icon.el icon]

(* [aria-disabled], not [disabled]: a disabled button loses the focus, which
   would fall out of the dialog when ‹ or › reaches an end. *)
let set_disabled el disabled =
  El.set_at (Jstr.v "aria-disabled")
    (match disabled with true -> Some (Jstr.v "true") | false -> None)
    el

let open_ ~host ~caller ~owned ~choose ~on_close ~photos c =
  (* style: the shown value, the slides of its proposal and whether 6d is
     closed live in refs, as in the viewer: they change only from DOM
     callbacks (scroll, taps), which then write the DOM themselves. *)
  let state = ref c in
  let closed = ref false in
  let slides = ref [] in
  let slide_bindings = ref [] in
  let close_b = round ~label:Text.compare_close W.Icon.Close in
  let position = txt_el "span" ["identify-compare__position"] "" in
  let mines = List.map mine_el photos in
  let mine_pill = pill "" in
  let top =
    El.div
      ~at:[cls "identify-compare__frame"; cls "identify-compare__frame--mine"]
      (mines @ [mine_pill])
  in
  let track = El.div ~at:[cls "identify-compare__track"] [] in
  let bottom =
    El.div
      ~at:
        [cls "identify-compare__frame"; cls "identify-compare__frame--species"]
      [track]
  in
  let latin = El.div ~at:[cls "identify-compare__latin"] [] in
  let names = El.div ~at:[cls "identify-compare__names"] [] in
  let owned_el = El.div ~at:[cls "identify-compare__owned"] [] in
  let percent = txt_el "span" ["identify-compare__percent"] "" in
  let previous = round ~label:Text.compare_previous W.Icon.Chevron_left in
  let next = round ~label:Text.compare_next W.Icon.Chevron_right in
  let action = Html.button ["identify-compare__action"] [] in
  let root =
    El.div
      ~at:
        [cls "identify-compare"; attr "role" "dialog"; attr "aria-modal" "true"]
      [
        El.div ~at:[cls "identify-compare__header"] [close_b; position];
        top;
        bottom;
        El.div
          ~at:[cls "identify-compare__info"]
          [
            El.div
              ~at:[cls "identify-compare__summary"]
              [
                El.div
                  ~at:[cls "identify-compare__text"]
                  [latin; names; owned_el];
                percent;
              ];
            El.div ~at:[cls "identify-compare__nav"] [previous; action; next];
          ];
      ]
  in
  let show_image () =
    let c = !state in
    let mine =
      match Compare.mine_index c < List.length mines with
      | true -> Compare.mine_index c
      | false -> 0
    in
    List.iteri
      (fun i el -> El.set_class (Jstr.v "is-hidden") (i <> mine) el)
      mines;
    El.set_children mine_pill
      [El.txt' (Text.compare_mine (Compare.mine_organ c))];
    let load = Compare.to_load c in
    List.iteri
      (fun k s ->
        match (List.mem k load, El.at At.Name.src s.img) with
        | true, None -> El.set_at At.Name.src (Some (Jstr.v s.url)) s.img
        | true, Some _ | false, (Some _ | None) -> ())
      !slides
  in
  let show_owned () =
    let p = Compare.proposal !state in
    let owns = React.S.value owned p in
    El.set_children owned_el
      (match owns with
      | Some o ->
          [
            W.Icon.el ~size:16 W.Icon.Check;
            El.txt' (Text.compare_owned caller o);
          ]
      | None -> []);
    El.set_class (Jstr.v "is-hidden") (Option.is_none owns) owned_el;
    El.set_children action
      [
        El.txt'
          (Text.compare_action
             (Caller.action caller ~owned:(Option.is_some owns)));
      ]
  in
  let show_proposal () =
    let c = !state in
    let p = Compare.proposal c in
    let label =
      Text.compare_position
        ~index:(Compare.index c + 1)
        ~count:(Compare.count c)
    in
    El.set_children position [El.txt' label];
    El.set_at (Jstr.v "aria-label") (Some (Jstr.v label)) root;
    Rb.release !slide_bindings;
    let images = Compare.images c in
    let count = List.length images in
    let built = List.mapi (slide_el p ~count) images in
    slides := List.map fst built;
    slide_bindings := List.concat_map snd built;
    El.set_children track
      (match !slides with
      | [] -> [empty_slide ()]
      | _ :: _ -> List.map (fun s -> s.el) !slides);
    El.set_children latin
      (El.txt' p.name
      ::
      (match p.author with
      | "" -> []
      | author ->
          [El.txt' " "; txt_el "span" ["identify-compare__author"] author]));
    El.set_children names
      (match Text.compare_names p with Some n -> [El.txt' n] | None -> []);
    show_owned ();
    El.set_children percent [El.txt' (Text.percent p.score)];
    set_disabled previous (not (Compare.can_previous c));
    set_disabled next (not (Compare.can_next c));
    show_image ()
  in
  let scroll_to k =
    El.set_prop
      (El.Prop.float (Jstr.v "scrollLeft"))
      (Float.of_int k *. El.bound_w track)
      track
  in
  let move event =
    let next = Compare.step !state event in
    match Compare.equal next !state with
    | true -> ()
    | false ->
        state := next;
        show_proposal ();
        scroll_to 0
  in
  let overlay = ref None in
  let bindings = ref [] in
  let finish () =
    match !closed with
    | true -> ()
    | false ->
        closed := true;
        Rb.release !slide_bindings;
        Rb.release !bindings;
        El.remove root;
        Option.iter Overlay.remove !overlay;
        on_close ()
  in
  let tap el f = Rb.listen el Ev.click (fun _ -> f ()) in
  bindings :=
    [
      tap close_b finish;
      tap previous (fun () -> move Previous);
      tap next (fun () -> move Next);
      tap action (fun () ->
          choose (Compare.index !state);
          finish ());
      Rb.on (React.S.changes owned) (fun (_ : Plantnet.proposal -> _) ->
          show_owned ());
      Rb.listen track Ev.scroll (fun _ ->
          let w = El.bound_w track in
          match w > 0. with
          | false -> ()
          | true -> (
              let k = Float.to_int (Float.round (El.scroll_x track /. w)) in
              let next = Compare.step !state (Shown k) in
              match
                Int.equal (Compare.image_index next)
                  (Compare.image_index !state)
              with
              | true -> ()
              | false ->
                  state := next;
                  show_image ()));
    ];
  show_proposal ();
  El.append_children host [root];
  El.set_has_focus true close_b;
  (* Once laid out, the track starts at the tapped image. *)
  ignore
    (G.request_animation_frame (fun (_ : float) ->
         match !closed with
         | true -> ()
         | false -> scroll_to (Compare.image_index !state)));
  let t = {close = finish} in
  overlay := Some (Overlay.push ~close:finish);
  t

let close t = t.close ()
