(** Values shared by the dev pages. *)

val state : unit -> State.t
(** A fresh {!State.t}: no filter, online with nothing to upload, signed out,
    originals kept in the app, every place-name source off. *)

val auth : unit -> Herbier_sync.Auth.t
(** A fresh {!Herbier_sync.Auth.t}, never started: no IO, no listener, no timer.
*)
