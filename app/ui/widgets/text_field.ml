open Brr

type t = {
  el : El.t;
  input : El.t;
  value : string React.signal;
  action : unit React.event;
  set : string -> unit;
  bindings : Rb.binding list;
}

let cls = Html.cls

let v ?icon ?action ?(value = "") ~placeholder () =
  let input =
    El.input
      ~at:
        [
          cls "text-field__input";
          At.type' (Jstr.v "text");
          At.value (Jstr.v value);
          At.v (Jstr.v "placeholder") (Jstr.v placeholder);
          At.v (Jstr.v "aria-label") (Jstr.v placeholder);
        ]
      ()
  in
  let inputs, bi = Rb.ev input Ev.input in
  let read _ = Jstr.to_string (El.prop El.Prop.value input) in
  let sets, send = React.E.create () in
  let typed =
    React.S.hold ~eq:String.equal value
      (React.E.select [React.E.map read inputs; sets])
  in
  let set text =
    El.set_prop El.Prop.value (Jstr.v text) input;
    send text
  in
  let lead = match icon with None -> [] | Some i -> [Icon.el ~size:20 i] in
  let pressed, trail, ba =
    match action with
    | None -> (React.E.never, [], [])
    | Some label ->
        let b = Html.button ["text-field__action"] [El.txt' label] in
        let e, ba = Rb.click b in
        (e, [b], [ba])
  in
  {
    el = El.div ~at:[cls "text-field"] (lead @ (input :: trail));
    input;
    value = typed;
    action = pressed;
    set;
    bindings = bi :: ba;
  }
