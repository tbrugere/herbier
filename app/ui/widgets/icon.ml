open Brr

type t =
  | Add
  | Arrow_back
  | Check
  | Close
  | Edit
  | Grid_view
  | List
  | Map
  | More_horiz
  | My_location
  | Photo_camera
  | Refresh
  | Search
  | Settings

let all =
  [
    Add;
    Arrow_back;
    Check;
    Close;
    Edit;
    Grid_view;
    List;
    Map;
    More_horiz;
    My_location;
    Photo_camera;
    Refresh;
    Search;
    Settings;
  ]

let name = function
  | Add -> "add"
  | Arrow_back -> "arrow_back"
  | Check -> "check"
  | Close -> "close"
  | Edit -> "edit"
  | Grid_view -> "grid_view"
  | List -> "list"
  | Map -> "map"
  | More_horiz -> "more_horiz"
  | My_location -> "my_location"
  | Photo_camera -> "photo_camera"
  | Refresh -> "refresh"
  | Search -> "search"
  | Settings -> "settings"

let el ?size t =
  let size =
    match size with
    | None -> []
    | Some px -> [At.style (Jstr.v (Printf.sprintf "font-size:%dpx" px))]
  in
  El.span
    ~at:
      (At.class' (Jstr.v "icon")
      :: At.v (Jstr.v "aria-hidden") (Jstr.v "true")
      :: size)
    [El.txt' (name t)]
