(* Wire strings: @capacitor/core 8.x types/core-plugins.d.ts (SystemBarsStyle,
   SystemBarType); SystemBars.java reads call.getString("bar") and
   getString("style"). *)

type style = Light | Dark
type bar = Status_bar | Navigation_bar

let style_to_string = function Light -> "LIGHT" | Dark -> "DARK"

let bar_to_string = function
  | Status_bar -> "StatusBar"
  | Navigation_bar -> "NavigationBar"

let set_style ~bar ~style =
  let options =
    Jv.obj
      [|
        ("style", Jv.of_string (style_to_string style));
        ("bar", Jv.of_string (bar_to_string bar));
      |]
  in
  Cap_call.call "systemBars" "setStyle" [|options|] ~ok:Cap_call.unit_ok
