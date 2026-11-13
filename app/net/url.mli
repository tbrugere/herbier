(** Building request URLs. *)

val encode : string -> string
(** Percent-encodes every byte except the RFC 3986 unreserved set
    [A-Z a-z 0-9 - . _ ~], with upper-case hex: [" "] gives ["%20"] (never
    ["+"]), ["/"] gives ["%2F"], ["é"] gives ["%C3%A9"]. *)

val strip_trailing_slashes : string -> string
(** [s] without the ['/'] it ends with, however many: ["https://x.test//"] gives
    ["https://x.test"], ["/"] gives [""]. *)
