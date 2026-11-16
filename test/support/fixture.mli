(** The recorded payloads of test/fixtures/, read from a suite's build directory
    (test/<suite>/, through the [(deps (glob_files ...))] of its dune file). *)

val read : string -> string
(** [read name] is the raw text of test/fixtures/[name]. Raises [Sys_error] when
    the file is missing (a broken test setup). *)

val exists : string -> bool
(** [exists name] is true when test/fixtures/[name] is there. *)

val names : prefix:string -> string list
(** [names ~prefix] is the file names of test/fixtures/ that start with
    [prefix], sorted; [[]] when none match. It lists the build directory, which
    holds what any suite's [(deps)] copied: filter on a prefix the suite's own
    [(deps)] glob covers. Raises [Sys_error] when the directory is missing (a
    broken test setup). *)
