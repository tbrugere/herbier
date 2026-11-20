(** Every département's « IGN hors-ligne » pack, measured on {!measured_on} from
    the WFS answers of {!Communes.communes_request}. Data for the estimates
    only; a later COG changes it a little. How it was measured, and how to
    measure it again: the header of [france_sizes.ml]. *)

val measured_on : string

val table : (string * int) list
(** [(code, bytes)]: the stored size of the pack
    ([String.length (Communes.to_string pack)] after
    {!Communes.pack_of_payload}). One entry per département of the WFS list on
    {!measured_on}, sorted by code (string order), codes unique, each passing
    [Communes.Code.of_string] (strings: [Code] has no total constructor for
    constants), bytes [> 0]. *)

val transfer : (string * int) list
(** [(code, bytes)]: what the WFS sent for that answer, gzip. The same codes as
    {!table}, in the same order, bytes [> 0]. *)
