(** Alcotest testables the suites share. *)

val yojson : Yojson.Safe.t Alcotest.testable
(** Compared with [Yojson.Safe.equal], printed pretty. *)
