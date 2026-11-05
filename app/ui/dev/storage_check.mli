(** Dev-only page: runs each binding against the real plugins and lists one line
    per check, "ok" or the {!Herbier_bindings.Cap_error.to_string} of the
    failure. Reached with the URL fragment [#dev/storage]. *)

val el : unit -> Brr.El.t
(** A fresh element that starts the checks when created and appends a line as
    each one settles. Checks run sequentially; a failure is reported and the
    next group still runs. Writes only under [dev/] in [Directory.Data], the
    [herbier.dev.*] preference keys and the [herbier_dev] database. A group
    removes the files, key and table it creates only when every check in it
    passes (a failure stops the group); the [dev/] directory and the
    [herbier_dev] database file always remain. *)
