open Brr

let cls c = At.class' (Jstr.v c)

let button ?label ?(at = []) classes children =
  let aria =
    match label with
    | Some l -> [At.v (Jstr.v "aria-label") (Jstr.v l)]
    | None -> []
  in
  El.button
    ~at:((At.type' (Jstr.v "button") :: aria) @ List.map cls classes @ at)
    children

let enter ev = Jstr.equal (Ev.Keyboard.key (Ev.as_type ev)) (Jstr.v "Enter")
let escape ev = Jstr.equal (Ev.Keyboard.key (Ev.as_type ev)) (Jstr.v "Escape")
