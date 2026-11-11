(** Cards. [plant] is the 3:4 cover card of the Collection grid (4a); [panel] is
    the [sand] container of secondary content (4h date, 5a fields, the reference
    block). *)

(** What fills the cover. [Photo url] (a local preview or reference thumbnail,
    never an unchecked remote URL) shows the image under the 5f scrim with the
    names in cream; [Preview path] a device preview file ([previews/<id>.jpg]),
    read and shown like [Photo], striped while it loads; [Loading label] the
    striped placeholder with a monospace label (["Google Photos…"]);
    [No_photo mention] a plain [sand] card with a line such as
    ["sans photo · 4 obs."]. *)
type cover =
  | Photo of string
  | Preview of string
  | Loading of string
  | No_photo of string

type t = {el : Brr.El.t; click : unit React.event; bindings : Rb.binding list}

val plant : name:string -> sci:string option -> cover -> t
(** [sci] is the scientific name, shown in Newsreader italic when present. *)

val panel : Brr.El.t list -> Brr.El.t
