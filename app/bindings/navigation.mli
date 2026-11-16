(** The Navigation API's current history entry (Chrome 102+), absent from Brr.
*)

val current_index : unit -> int option
(** [navigation.currentEntry.index]; [None] when [globalThis.navigation] or its
    [currentEntry] is missing, or the index is not a non-negative integer (-1
    for an entry outside the session history). Never raises. *)
