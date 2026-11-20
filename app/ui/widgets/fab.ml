type t = {el : Brr.El.t; click : unit React.event; bindings : Rb.binding list}

let v ~label icon =
  let el = Html.button ~label ["fab"] [Icon.el ~size:30 icon] in
  let click, b = Rb.click el in
  {el; click; bindings = [b]}
