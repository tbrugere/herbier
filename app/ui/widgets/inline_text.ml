open Brr

type t = {el : El.t; bindings : Rb.binding list}

let v ?cls ~label ~placeholder ~save value =
  let extra = match cls with Some c -> [At.class' (Jstr.v c)] | None -> [] in
  let shown =
    El.button
      ~at:
        (At.type' (Jstr.v "button") :: At.class' (Jstr.v "inline-text") :: extra)
      []
  in
  let area =
    El.textarea
      ~at:
        (At.class' (Jstr.v "inline-text__input")
        :: At.class' (Jstr.v "is-hidden")
        :: At.v (Jstr.v "aria-label") (Jstr.v label)
        :: extra)
      []
  in
  (* style: [editing] tells whether the textarea is open, so that its blur
     and the release do not both save; [draft] keeps the text of a save that
     failed. Both written from the listeners, the release and the save's
     callback; the release may run inside the router's update step, where a
     ref write is harmless. *)
  let editing = ref false in
  let draft = ref None in
  let show on =
    El.set_class (Jstr.v "is-hidden") on shown;
    El.set_class (Jstr.v "is-hidden") (not on) area
  in
  let set_editing on =
    editing := on;
    show on;
    match on with true -> El.set_has_focus true area | false -> ()
  in
  (* A tap on a button below the textarea blurs it at the tap's mousedown and
     hit-tests the click afterwards: collapsing the textarea at once moves the
     button up and the click lands beside it. On blur the textarea collapses
     after the tap's events, on a timer; [editing] drops at once so a second
     blur or the release does not save twice. *)
  let commit ~collapse =
    match !editing with
    | false -> ()
    | true -> (
        editing := false;
        collapse ();
        let text = String.trim (Jstr.to_string (El.prop El.Prop.value area)) in
        match String.equal text (React.S.value value) with
        | true -> draft := None
        | false ->
            Fut.await (save text) (function
              | true -> draft := None
              | false -> draft := Some text))
  in
  let open_ =
    Rb.listen shown Ev.click (fun _ ->
        let text = Option.value !draft ~default:(React.S.value value) in
        El.set_prop El.Prop.value (Jstr.v text) area;
        set_editing true)
  in
  {
    el = El.div [shown; area];
    bindings =
      [
        open_;
        Rb.listen area Ev.blur (fun _ ->
            commit ~collapse:(fun () ->
                let _ : G.timer_id =
                  G.set_timeout ~ms:0 (fun () ->
                      match !editing with false -> show false | true -> ())
                in
                ()));
        Rb.on_release (fun () -> commit ~collapse:(fun () -> show false));
        Rb.text shown
          (React.S.map (function "" -> placeholder | v -> v) value);
        Rb.class_ shown "inline-text--empty"
          (React.S.map (String.equal "") value);
      ];
  }
