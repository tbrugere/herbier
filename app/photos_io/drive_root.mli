(** The Drive root folder's id kept in [settings] (key [Drive_root_folder]):
    read before a Drive program that needs the root, updated from its
    {!Herbier_photos.Drive.root_change}; and the folder the user picked in 4m
    (key [Drive_root_folder_picked]), which is the root while the two ids match,
    with the root it replaced (key [Drive_root_folder_default]); and the Drive
    account they belong to (key [Drive_account]), written with them.
    Device-local, not synced. Console lines never carry an id, a name or an
    email. *)

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

val account : Db.t -> (string option, Db.error) result Fut.t
(** [Settings.get Drive_account]: the Drive account chosen in 4m. A blank value
    ([Row `WrongType]) is [Ok None] plus one console error « drive: account
    unreadable: … »; any other error is returned. *)

val choose :
  Db.t ->
  account:string ->
  storage:Herbier_domain.Photo.Original_target.t option ->
  Herbier_store.Settings.drive_folder ->
  (unit, Db.error) result Fut.t
(** 4m « Dossier Drive » sheet or Drive radio, a folder picked for [account]:
    reads the three keys and {!account}, then writes
    {!Herbier_photos.Drive.choose_for_account} of them in one transaction:
    [Drive_account] when the account changed, then [Drive_root_folder] = the
    folder's id, [Drive_root_folder_picked] = the folder,
    [Drive_root_folder_default] = for the same account the root in force before
    the first pick (kept across later picks), for another account unset (the old
    account's folders are forgotten). Console line « drive: root folder picked
    », plus « drive: account changed, root folder forgotten » when the account
    changed; an error (a read, or the transaction, rolled back: nothing changed)
    is returned and logged « drive: root folder not written: … ». With
    [storage = Some s] (the 4m Drive radio), [Storage_target] = [s] is written
    in the same transaction, so an error leaves the storage unchanged too;
    console line « drive: storage set with the pick ». Run it inside
    [Upload_queue.exclusive]. *)

val reset : Db.t -> account:string -> (unit, Db.error) result Fut.t
(** The sheet's « Par défaut » for [account]: as {!choose}, with no folder. The
    same account: the root goes back to the saved default (the app's « Herbier
    », wherever it was moved), or is unset when none was saved; another account:
    the account is stored and all three keys unset (the next upload finds or
    creates « Herbier » at that Drive's root). The picked folder and the default
    are unset. Console line « drive: root folder reset ». *)

val seed :
  Db.t -> session_email:string option -> (string option, Db.error) result Fut.t
(** Keeps an older install's folders: reads the three keys and {!account}, and
    when {!Herbier_photos.Drive.seed_account} gives [Some email], writes
    [Drive_account] = [email] alone (the ids stay) and returns it, with the
    console line « drive: root folder kept for the signed-in account »; else
    writes nothing, [Ok None]. Run it inside [Upload_queue.exclusive]. *)

val forget_account : Db.t -> (unit, Db.error) result Fut.t
(** Unsets [Drive_account] and the three root keys in one transaction
    (#dev/drive « Oublier le compte »): the folders belong to the account.
    Console line « drive: root folder forgotten with the account »; an error is
    returned and logged as {!choose}'s. Run it inside [Upload_queue.exclusive].
*)
