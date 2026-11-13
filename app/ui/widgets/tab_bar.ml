open Brr

type tab = Collection | Map | Journal | Settings [@@deriving eq]

type t = {
  el : El.t;
  select : tab React.event;
  record : unit React.event;
  bindings : Rb.binding list;
}

let cls = Html.cls
let button = Html.button

let label = function
  | Collection -> "Collection"
  | Map -> "Carte"
  | Journal -> "Journal"
  | Settings -> "Réglages"

let icon = function
  | Collection -> Icon.Grid_view
  | Map -> Icon.Map
  | Journal -> Icon.List
  | Settings -> Icon.Settings

let equal = equal_tab

type tab_button = {
  button_el : El.t;
  press : tab React.event;
  button_bindings : Rb.binding list;
}

let tab active t =
  let el =
    button ["tab-bar__tab"]
      [Icon.el ~size:20 (icon t); El.span [El.txt' (label t)]]
  in
  let click, b = Rb.click el in
  let on = React.S.map ~eq:Bool.equal (equal t) active in
  {
    button_el = el;
    press = React.E.map (fun () -> t) click;
    button_bindings =
      [
        b;
        Rb.class_ el "tab-bar__tab--active" on;
        Rb.attr el "aria-current"
          (React.S.map (function true -> Some "page" | false -> None) on);
      ];
  }

let v ~active =
  let left = List.map (tab active) [Collection; Map] in
  let right = List.map (tab active) [Journal; Settings] in
  let tabs = left @ right in
  let record_el =
    button
      ~at:[At.v (Jstr.v "aria-label") (Jstr.v "Noter")]
      ["tab-bar__record"]
      [Icon.el ~size:30 Icon.Add]
  in
  let record, rb = Rb.click record_el in
  let els = List.map (fun t -> t.button_el) in
  {
    el = El.nav ~at:[cls "tab-bar"] (els left @ (record_el :: els right));
    select = React.E.select (List.map (fun t -> t.press) tabs);
    record;
    bindings = rb :: List.concat_map (fun t -> t.button_bindings) tabs;
  }
