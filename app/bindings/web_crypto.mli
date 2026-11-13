(** WebCrypto ([globalThis.crypto]): random bytes and SHA-256, the bytes as an
    OCaml [string]. Errors are the JS error's message. *)

val random_bytes : int -> (string, string) result
(** [n] bytes from [getRandomValues]. *)

val sha256 : string -> (string, string) result Fut.t
(** The 32-byte SHA-256 digest of the text's UTF-8 bytes ([subtle.digest]). A
    synchronous throw is an [Error] too; the future always resolves. *)
