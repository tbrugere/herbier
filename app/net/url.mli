(** Building request URLs. *)

val encode : string -> string
(** Percent-encodes every byte except the RFC 3986 unreserved set
    [A-Z a-z 0-9 - . _ ~], with upper-case hex: [" "] gives ["%20"] (never
    ["+"]), ["/"] gives ["%2F"], ["é"] gives ["%C3%A9"]. *)

val strip_trailing_slashes : string -> string
(** [s] without the ['/'] it ends with, however many: ["https://x.test//"] gives
    ["https://x.test"], ["/"] gives [""]. *)

val under : prefix:string -> string -> bool
(** [true] iff [url] starts with [prefix], has at least one byte after it, and
    contains no whitespace, control character, DEL, ['"'], ['<'], ['>'] or
    backslash: such characters are refused, not escaped, since the URL may
    become an [<img src>] or a native download path. Bytes [>= 0x80] (UTF-8
    text) are accepted. With [prefix = "https://bs.plantnet.org/"]: [http://…],
    another host, a host suffix (["https://bs.plantnet.org.evil.com/x"]),
    userinfo and a port are all [false]. *)
