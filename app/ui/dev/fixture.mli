(** Values shared by the dev pages. *)

val state : unit -> State.t
(** A fresh {!State.t}: no filter, online with nothing to upload, signed out,
    originals kept in the app. *)
