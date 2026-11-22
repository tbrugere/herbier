open Brr
module Tag_pick = Herbier_ui_model.Tag_pick

type t = {el : El.t; added : string React.event; bindings : Rb.binding list}

let cls = Html.cls
let set el name v = El.set_at (Jstr.v name) (Option.map Jstr.v v) el
let bool = function true -> "true" | false -> "false"

(* style: a counter for the ids aria-controls and aria-activedescendant point
   to, unique across the pickers of the page. *)
let count = ref 0

let v ~placeholder ~suggest () =
  incr count;
  let list_id = Printf.sprintf "tag-picker-%d" !count in
  let option_id i = Printf.sprintf "%s-%d" list_id i in
  let pill = Html.button ["adder__pill"] [El.txt' "+ tag"] in
  let input =
    El.input
      ~at:
        [
          At.type' (Jstr.v "text");
          cls "adder__input";
          cls "is-hidden";
          At.placeholder (Jstr.v placeholder);
          At.v (Jstr.v "aria-label") (Jstr.v placeholder);
          At.v (Jstr.v "enterkeyhint") (Jstr.v "done");
          At.v (Jstr.v "autocomplete") (Jstr.v "off");
          At.v (Jstr.v "role") (Jstr.v "combobox");
          At.v (Jstr.v "aria-autocomplete") (Jstr.v "list");
          At.v (Jstr.v "aria-expanded") (Jstr.v "false");
          At.v (Jstr.v "aria-controls") (Jstr.v list_id);
        ]
      ()
  in
  let listbox =
    El.ul
      ~at:
        [
          At.id (Jstr.v list_id);
          At.v (Jstr.v "role") (Jstr.v "listbox");
          At.v (Jstr.v "aria-label") (Jstr.v "Tags");
          cls "tag-picker__list";
          cls "is-hidden";
        ]
      []
  in
  let el = El.span ~at:[cls "adder"; cls "tag-picker"] [pill; input; listbox] in
  (* The listeners send on [added] from DOM callbacks, outside update steps;
     their closures keep the event alive. *)
  let added, send = React.E.create () in
  (* style: the rows shown, the highlighted one and whether the field is
     open, written by the DOM listeners only. *)
  let entries = ref [||] and active = ref None and open_ = ref false in
  let text () = Jstr.to_string (El.prop El.Prop.value input) in
  let mark () =
    Array.iteri
      (fun i row ->
        let on = Option.equal Int.equal (Some i) !active in
        El.set_class (Jstr.v "is-active") on row;
        set row "aria-selected" (Some (bool on));
        match on with
        (* [~behavior] given: brr 0.0.9 passes [null] for a missing one, which
           the WebView rejects. *)
        | true -> El.scroll_into_view ~align_v:`Nearest ~behavior:`Auto row
        | false -> ())
      (Array.of_list (El.children ~only_els:true listbox));
    set input "aria-activedescendant" (Option.map option_id !active)
  in
  let show_list on =
    El.set_class (Jstr.v "is-hidden") (not on) listbox;
    set input "aria-expanded" (Some (bool on))
  in
  let render () =
    entries := Array.of_list (suggest (text ()));
    let n = Array.length !entries in
    (active :=
       match (String.trim (text ()), n) with
       | "", _ | _, 0 -> None
       | _ -> Some 0);
    El.set_children listbox
      (List.mapi
         (fun i e ->
           El.li
             ~at:
               [
                 At.id (Jstr.v (option_id i));
                 At.v (Jstr.v "role") (Jstr.v "option");
                 At.v (Jstr.v "data-index") (Jstr.of_int i);
                 cls "tag-picker__option";
                 At.if'
                   (match e with Tag_pick.Create _ -> true | Pick _ -> false)
                   (cls "tag-picker__option--create");
               ]
             [El.txt' (Tag_pick.label e)])
         (Array.to_list !entries));
    show_list (n > 0);
    mark ()
  in
  let finish () =
    match !open_ with
    | false -> ()
    | true ->
        open_ := false;
        entries := [||];
        active := None;
        El.set_children listbox [];
        show_list false;
        set input "aria-activedescendant" None;
        El.set_prop El.Prop.value Jstr.empty input;
        El.set_class (Jstr.v "is-hidden") false pill;
        El.set_class (Jstr.v "is-hidden") true input
  in
  (* The screen takes [added] in a microtask ({!Rb.act}): the rows are read
     again once it has, so the tag just added is no longer offered. *)
  let pick i =
    match i < Array.length !entries with
    | false -> ()
    | true ->
        let name = Tag_pick.name !entries.(i) in
        El.set_prop El.Prop.value Jstr.empty input;
        send name;
        Fut.await (Fut.tick ~ms:0) (fun () ->
            match !open_ with true -> render () | false -> ())
  in
  let move by =
    let n = Array.length !entries in
    match n with
    | 0 -> ()
    | _ ->
        active :=
          Some
            (match !active with
            | None -> if by > 0 then 0 else n - 1
            | Some i -> (i + by + n) mod n);
        mark ()
  in
  let b_pill =
    Rb.listen pill Ev.click (fun _ ->
        open_ := true;
        El.set_class (Jstr.v "is-hidden") true pill;
        El.set_class (Jstr.v "is-hidden") false input;
        El.set_has_focus true input;
        render ())
  in
  let b_input = Rb.listen input Ev.input (fun _ -> render ()) in
  let b_key =
    Rb.listen input Ev.keydown (fun e ->
        let k = Ev.as_type e in
        match Jstr.to_string (Ev.Keyboard.key k) with
        | "ArrowDown" ->
            Ev.prevent_default e;
            move 1
        | "ArrowUp" ->
            Ev.prevent_default e;
            move (-1)
        | "Enter" -> (
            Ev.prevent_default e;
            match (!active, String.trim (text ())) with
            | Some i, _ -> pick i
            | None, "" -> finish ()
            | None, _ -> ())
        | "Escape" -> finish ()
        | _ -> ())
  in
  (* A press on a row must not take the focus from the field: its blur would
     close the list before the click lands. *)
  let b_down = Rb.listen listbox Ev.mousedown Ev.prevent_default in
  let b_click =
    Rb.listen listbox Ev.click (fun e ->
        (* A row holds only its text: the target is the row itself. *)
        let row = El.of_jv (Ev.target_to_jv (Ev.target e)) in
        match Option.bind (El.at (Jstr.v "data-index") row) Jstr.to_int with
        | Some i -> pick i
        | None -> ())
  in
  let b_blur = Rb.listen input Ev.blur (fun _ -> finish ()) in
  {el; added; bindings = [b_pill; b_input; b_key; b_down; b_click; b_blur]}
