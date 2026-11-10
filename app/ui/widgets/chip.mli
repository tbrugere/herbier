(** Pills of the filter rows (4a, 4c): a filter chip is filled when active and
    bordered otherwise; a link chip is the trailing ["Tags ›"]. *)

(** [Ink] for tags and years; [Ochre] for ["À identifier · n"] (border 1.5 px).
*)
type tone = Ink | Ochre

type t = {
  el : Brr.El.t;  (** a [button] *)
  click : unit React.event;
  bindings : Rb.binding list;  (** release them with the screen *)
}

val filter : ?tone:tone -> label:string -> active:bool React.signal -> unit -> t
(** Default [tone] is [Ink]. The chip only shows [active]; the screen decides
    what a click changes. *)

val link : string -> t
(** Text in [moss], no border: ["Tags ›"]. *)
