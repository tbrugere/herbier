open Brr

type map = Herbier_geo.Style.colours = {
  point : string;
  point_border : string;
  selected : string;
  selected_halo : string;
  to_identify : string;
  accuracy_fill : string;
  accuracy_line : string;
}

type t = {map : map; status_bar : string}
type error = Missing_tokens of string list

(* Applicative over [(_, string list) result]: every read runs, and the
   names of all missing tokens are gathered. *)
let ( let+ ) r f = Result.map f r

let ( and+ ) a b =
  match (a, b) with
  | Ok x, Ok y -> Ok (x, y)
  | Error e, Ok _ | Ok _, Error e -> Error e
  | Error e, Error e' -> Error (e @ e')

let load () =
  let root = Document.root G.document in
  let get name =
    match Herbier_bindings.Css_var.get root name with
    | "" -> Error [name]
    | v -> Ok v
  in
  (let+ point = get "--map-point"
   and+ point_border = get "--map-point-border"
   and+ selected = get "--map-selected"
   and+ selected_halo = get "--map-selected-halo"
   and+ to_identify = get "--map-to-identify"
   and+ accuracy_fill = get "--map-accuracy-fill"
   and+ accuracy_line = get "--map-accuracy-line"
   and+ status_bar = get "--status-bar" in
   {
     map =
       {
         point;
         point_border;
         selected;
         selected_halo;
         to_identify;
         accuracy_fill;
         accuracy_line;
       };
     status_bar;
   })
  |> Result.map_error (fun names -> Missing_tokens names)
