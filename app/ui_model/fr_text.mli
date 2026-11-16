(** Counted French text. Pure. *)

val plural : int -> string -> string -> string
(** [plural n one many] is ["n one"] for [n <= 1] (French: 0 and 1 take the
    singular), ["n many"] otherwise: [plural 2 "plante" "plantes"] is
    ["2 plantes"]. *)

val size : float -> string
(** A size in bytes (a float: a sum of file sizes passes 2{^ 31}, the width of
    [int] under js_of_ocaml), French, SI units, decimal comma: below 1000 →
    ["<n> o"] (truncated); else [round(n/1000)] when below 1000 →
    ["<round(n/1000)> ko"]; else one decimal, ["1,0 Mo"] (999_500 included),
    ["1,2 Mo"], ["12,0 Mo"]. A negative size → ["0 o"]. *)
