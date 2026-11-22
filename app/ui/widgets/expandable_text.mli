(** A paragraph of 4f that may be long (« Utilisations », Habitat, toxicity):
    collapsed to about three lines with a fade, expanded by a tap and collapsed
    again by the next one. A short text
    ({!Herbier_ui_model.Long_text.collapsible} false) is shown in full. The open
    state is the caller's, so it survives a rebuild of the rows. *)

type t = {el : Brr.El.t; bindings : Rb.binding list}

val v :
  ?cls:string list ->
  opened:bool React.signal ->
  set_opened:(bool -> unit) ->
  string ->
  t
(** Not collapsible: a [div] with the text (plus [cls]), no binding, [opened]
    unused. Collapsible: a [button type="button"] of class [expandable-text]
    (plus [cls]) holding the text in a [span.expandable-text__body],
    [aria-expanded] bound to [opened] and class [is-open] when opened; a tap
    calls [set_opened (not current)]. Closed, the CSS clamps the body to three
    lines with a fade on the last one; open, the whole text. The button reads as
    a paragraph (font, colour, alignment, border and background reset). *)
