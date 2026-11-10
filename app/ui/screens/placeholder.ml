open Brr

let v tab =
  let field =
    Widgets.Text_field.v ~icon:Widgets.Icon.Search ~placeholder:"Rechercher…" ()
  in
  let echo = El.p ~at:[At.class' (Jstr.v "t-meta")] [] in
  let el =
    El.div
      ~at:[At.class' (Jstr.v "screen")]
      [
        El.h1
          ~at:[At.class' (Jstr.v "t-screen-title")]
          [El.txt' (Widgets.Tab_bar.label tab)];
        field.el;
        echo;
      ]
  in
  {Screen.el; bindings = Rb.text echo field.value :: field.bindings}
