open Brr

let cls = Html.cls

let v ?trailing ~title ~detail () =
  El.div
    ~at:[cls "settings__row"]
    (El.span
       ~at:[cls "settings__text"]
       [
         El.span ~at:[cls "settings__title"] [El.txt' title];
         El.span ~at:[cls "t-meta"] [El.txt' detail];
       ]
    :: Option.to_list trailing)
