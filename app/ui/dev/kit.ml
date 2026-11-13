open Brr

let append log text = El.append_children log [El.div [El.txt' text]]
let button label = El.button ~at:[At.type' (Jstr.v "button")] [El.txt' label]

let on_click el f =
  ignore (Ev.listen Ev.click (fun _ -> f ()) (El.as_target el) : Ev.listener)

let heading log text = El.append_children log [El.h2 [El.txt' text]]

let set_disabled el disabled =
  El.set_at At.Name.disabled
    (match disabled with true -> Some Jstr.empty | false -> None)
    el

let step log label ~detail ~error fut =
  Fut.map
    (fun r ->
      (match r with
      | Ok v -> (
          match detail v with
          | None -> append log (label ^ ": ok")
          | Some d -> append log (label ^ ": ok · " ^ d))
      | Error e -> append log (label ^ ": " ^ error e));
      r)
    fut

let action label f =
  let b = El.button [El.txt' label] in
  on_click b f;
  b
