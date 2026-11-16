(** The Drive root folder's id kept in [settings] (key [Drive_root_folder]):
    read before a Drive program that needs the root, updated from its
    {!Herbier_photos.Drive.root_change}. Device-local, not synced. Console lines
    never carry the id. *)

module Db := Herbier_store_io.Db

val stored : Db.t -> (string option, Db.error) result Fut.t
(** [Settings.get Drive_root_folder]. A blank value ([Decode] with
    [Row `WrongType]) is [Ok None] plus one console error « drive: root folder
    unreadable: … » (the next upload finds or creates the root by name and
    {!apply} overwrites it). Any other error (a failed plugin call) is returned:
    reading it as unset could create a second root folder after a move. *)

val forget : Db.t -> (int, Db.error) result Fut.t
(** [Settings.unset Drive_root_folder]. *)

val apply : Db.t -> Herbier_photos.Drive.root_change -> unit Fut.t
(** [Keep] → nothing (no write); [Store id] →
    [Settings.set Drive_root_folder id], console line « drive: root folder
    stored »; [Forget] → {!forget}, « drive: root folder forgotten ». A write
    error is a console error « drive: root folder not written: … » only (the
    next run checks the root again). Never raises; always resolves. *)

val run :
  Db.t ->
  (root:string option -> 'a Herbier_photos.Drive.rooted Fut.t) ->
  ('a Herbier_photos.Drive.rooted, Db.error) result Fut.t
(** {!stored}, then the program with it, then {!apply} of its root change,
    written before the caller acts on the result (a root created by a run that
    then failed is not created again by the next one). A {!stored} error →
    [Error], no program run. *)
