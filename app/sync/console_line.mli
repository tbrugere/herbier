(** Sync's console lines: one string, prefixed with the part of sync that writes
    it (["auth: …"], ["sync: …"], ["keepalive: …"]). *)

type scope = Auth | Sync | Keepalive

val log : scope -> string -> unit
(** [log scope m]: [console.log("<scope>: " ^ m)]. *)

val warn : scope -> string -> unit
(** [warn scope m]: [console.warn("<scope>: " ^ m)]. *)

val error : scope -> string -> unit
(** [error scope m]: [console.error("<scope>: " ^ m)]. *)
