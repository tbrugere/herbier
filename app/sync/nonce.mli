(** Encoding of the sign-in nonce. The random bytes and the SHA-256 are
    WebCrypto, in {!Auth}. *)

val hex : string -> string
(** Lowercase hexadecimal of the bytes, two digits each ([""] → [""]). *)
