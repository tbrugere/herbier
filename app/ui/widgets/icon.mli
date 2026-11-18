(** Material Symbols Outlined glyphs from the bundled subset
    ([web/fonts/material-symbols.woff2]). The constructors are exactly the names
    of [web/fonts/icons.txt]: adding one means adding the name there and running
    [scripts/subset-icons.sh], or the glyph renders as its name. *)

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

val all : t list
(** Every icon, in [icons.txt] order. *)

val name : t -> string
(** The ligature name, as in [icons.txt]: ["arrow_back"]. *)

val el : ?size:int -> t -> Brr.El.t
(** A [span.icon] hidden from screen readers (the ligature text would be read
    out). [size] in px, default 24 (the font's optical size). *)
