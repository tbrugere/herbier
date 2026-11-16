(** The Drive root folder's id kept in [settings] (key [Drive_root_folder]):
    read before a Drive program that needs the root, updated from its
    {!Herbier_photos.Drive.root_change}; and the folder the user picked in 4m
    (key [Drive_root_folder_picked]), which is the root while the two ids match,
    with the root it replaced (key [Drive_root_folder_default]). Device-local,
    not synced. Console lines never carry an id or a name. *)

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

val read_choice :
  Db.t ->
  (string option * Herbier_store.Settings.drive_folder option, Db.error) result
  Fut.t
(** {!stored}, and the picked folder: a [Row `WrongType] → [None] plus one
    console error « drive: picked folder unreadable: … »; any other error of
    either read is returned. *)

val choose :
  Db.t -> Herbier_store.Settings.drive_folder -> (unit, Db.error) result Fut.t
(** Reads the three keys, then writes {!Herbier_photos.Drive.pick_root} of them
    in one transaction: [Drive_root_folder] = the folder's id,
    [Drive_root_folder_picked] = the folder, [Drive_root_folder_default] = the
    root in force before the first pick (kept across later picks). Console line
    « drive: root folder picked »; an error (a read, or the transaction, rolled
    back: nothing changed) is returned and logged « drive: root folder not
    written: … ». Run it inside [Upload_queue.exclusive]. *)

val reset : Db.t -> (unit, Db.error) result Fut.t
(** 4m « Par défaut »: as {!choose}, with {!Herbier_photos.Drive.default_root}:
    the root goes back to the saved default (the app's « Herbier », wherever it
    was moved), or is unset when none was saved (the next upload finds or
    creates « Herbier » at My Drive's root); the picked folder and the default
    are unset. Console line « drive: root folder reset ». *)
