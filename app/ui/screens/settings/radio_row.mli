(** A 4m « Où vont mes photos » radio: a [role="radio"] button ([.radio-row])
    with its dot, then a column of the title, the detail and [extra] (further
    lines, built and bound by the caller). [selected] drives [.radio-row--on]
    and [aria-checked]. *)

type t = {el : Brr.El.t; click : unit React.event; bindings : Rb.binding list}

val v :
  ?extra:Brr.El.t list ->
  title:string React.signal ->
  detail:string React.signal ->
  bool React.signal ->
  t
