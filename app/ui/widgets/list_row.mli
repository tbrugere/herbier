(** A list row (4c journal, 4b drawer, 4i results): thumbnail, a bold title, one
    line of metadata and a chevron. About 72 px high; pressed = [sand]. *)

(** [Image url] (a local preview or reference thumbnail, never an unchecked
    remote URL); [Preview path] a device preview ([previews/<id>.jpg]) shown
    through {!Preview_img}; or the striped placeholder while there is none yet.
*)
type thumb = Image of string | Preview of string | Placeholder

(** [To_identify] writes the title in [ochre] (["À identifier"]). *)
type tone = Normal | To_identify

type t = {
  el : Brr.El.t;
  click : unit React.event;
  long : unit React.event;
  bindings : Rb.binding list;
}

val v :
  ?long_press:bool ->
  ?thumb:thumb ->
  ?tone:tone ->
  title:string ->
  meta:string ->
  unit ->
  t
(** Without [thumb] the row has no thumbnail column. Default [tone] is [Normal].
    [long_press] (default [false]): [click] and [long] are {!Long_press.v}'s
    [tap] and [long] on the row (a keyboard or assistive activation is a
    [click]); otherwise [click] is {!Rb.click} and [long] is [React.E.never]. *)
