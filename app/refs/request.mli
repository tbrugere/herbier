(** A GET to one reference source: what [refs_io/http.ml] fetches. Pure. *)

type t = private {source : Herbier_domain.Reference.Source.t; url : string}

val make :
  Herbier_domain.Reference.Source.t ->
  base:string ->
  path:string list ->
  query:(string * string) list ->
  t
(** [make source ~base ~path ~query] is [base] (written as given, no trailing
    slash, e.g. ["https://api.gbif.org/v1"]), then ["/" ^ encode seg] for each
    segment of [path], then, when [query] is not empty, ["?"] and the
    [encode k ^ "=" ^ encode v] pairs joined by ["&"], in the given order;
    [encode] is {!Herbier_net.Url.encode}. *)

val equal : t -> t -> bool

val to_string : t -> string
(** ["<source> <url>"], for logs and test diffs. *)
