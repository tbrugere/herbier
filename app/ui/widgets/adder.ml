open Brr

type t = {el : El.t; added : string React.event; bindings : Rb.binding list}

let v ~label ~placeholder () =
  let pill =
    El.button
      ~at:[At.type' (Jstr.v "button"); At.class' (Jstr.v "adder__pill")]
      [El.txt' ("+ " ^ label)]
  in
  let input =
    El.input
      ~at:
        [
          At.type' (Jstr.v "text");
          At.class' (Jstr.v "adder__input");
          At.class' (Jstr.v "is-hidden");
          At.placeholder (Jstr.v placeholder);
          At.v (Jstr.v "aria-label") (Jstr.v placeholder);
          At.v (Jstr.v "enterkeyhint") (Jstr.v "done");
        ]
      ()
  in
  let el = El.span ~at:[At.class' (Jstr.v "adder")] [pill; input] in
  (* The listeners send on [added] from DOM callbacks, outside update steps;
     their closures keep the event alive. *)
  let added, send = React.E.create () in
  let editing on =
    El.set_class (Jstr.v "is-hidden") on pill;
    El.set_class (Jstr.v "is-hidden") (not on) input;
    match on with
    | true -> El.set_has_focus true input
    | false -> El.set_prop El.Prop.value Jstr.empty input
  in
  (* style: [open_] guards against the blur that hiding the input fires after
     Enter or Escape already closed it. *)
  let open_ = ref false in
  let close ~commit =
    match !open_ with
    | false -> ()
    | true -> (
        open_ := false;
        let text = String.trim (Jstr.to_string (El.prop El.Prop.value input)) in
        editing false;
        match (commit, text) with
        | true, "" | false, _ -> ()
        | true, t -> send t)
  in
  let b_pill =
    Rb.listen pill Ev.click (fun _ ->
        open_ := true;
        editing true)
  in
  let b_key =
    Rb.listen input Ev.keydown (fun e ->
        match Jstr.to_string (Ev.Keyboard.key (Ev.as_type e)) with
        | "Enter" -> close ~commit:true
        | "Escape" -> close ~commit:false
        | _ -> ())
  in
  let b_blur = Rb.listen input Ev.blur (fun _ -> close ~commit:true) in
  {el; added; bindings = [b_pill; b_key; b_blur]}
