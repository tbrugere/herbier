(** A list row (4c journal, 4b drawer, 4i results): thumbnail, a bold title, one
    line of metadata and a chevron. About 72 px high; pressed = [sand]. *)

(** [Image url] (a local preview or reference thumbnail, never an unchecked
    remote URL), or the striped placeholder while there is none yet. *)
type thumb = Image of string | Placeholder

(** [To_identify] writes the title in [ochre] (["À identifier"]). *)
type tone = Normal | To_identify

type t = {el : Brr.El.t; click : unit React.event; bindings : Rb.binding list}

val v : ?thumb:thumb -> ?tone:tone -> title:string -> meta:string -> unit -> t
(** Without [thumb] the row has no thumbnail column. Default [tone] is [Normal].
*)
