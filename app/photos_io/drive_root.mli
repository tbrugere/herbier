(** The Drive root folder kept in [settings]: its id (key [Drive_root_folder])
    and its name (key [Drive_root_folder_name], « Herbier » when unset), read
    before a Drive program that needs the root and updated from what the program
    learnt ({!Herbier_photos.Drive.rooted}); and the Drive account they belong
    to (key [Drive_account]), written with the id. Device-local, not synced.
    Console lines never carry an id, a name or an email. *)

module Db := Herbier_store_io.Db

val stored : Db.t -> (string option, Db.error) result Fut.t
(** [Settings.get Drive_root_folder]. A blank value ([Decode] with
    [Row `WrongType]) is [Ok None] plus one console error « drive: root folder
    unreadable: … » (the next upload finds or creates the root by name and
    {!apply} overwrites it). Any other error (a failed plugin call) is returned:
    reading it as unset could create a second root folder after a move. *)

val name : Db.t -> (string option, Db.error) result Fut.t
(** [Settings.get Drive_root_folder_name]. A blank value ([Row `WrongType]) is
    [Ok None] plus one console error « drive: folder name unreadable: … »; any
    other error is returned. *)

val root : Db.t -> (Herbier_photos.Drive.root, Db.error) result Fut.t
(** {!stored} and {!name}: [{id; name}], [name] being
    [Herbier_photos.Drive.folder_name] of the stored name, else
    [Herbier_photos.Drive.default_folder_name]. Either read's error → [Error].
*)

val forget : Db.t -> (int, Db.error) result Fut.t
(** [Settings.unset Drive_root_folder]. *)

val apply :
  Db.t ->
  stored_name:string option ->
  'a Herbier_photos.Drive.rooted ->
  unit Fut.t
(** Writes, in one transaction, the root change ([Keep] → nothing; [Store id] →
    [Settings.set Drive_root_folder id]; [Forget] → {!forget}) and, when the run
    learnt a name to store ({!Herbier_photos.Drive.name_to_store}
    [~stored_name rooted.name] = [Some n]),
    [Settings.set Drive_root_folder_name n]: a root re-created after a loss and
    its name never diverge. Nothing to write → no transaction. Console lines «
    drive: root folder stored » / « drive: root folder forgotten », « drive:
    folder name stored ». A write error is a console error « drive: root folder
    not written: … » only (the next run checks the root again). Never raises;
    always resolves. *)

val run :
  Db.t ->
  (root:Herbier_photos.Drive.root -> 'a Herbier_photos.Drive.rooted Fut.t) ->
  ('a Herbier_photos.Drive.rooted, Db.error) result Fut.t
(** {!root}, then the program with it, then {!apply} of what it learnt (with the
    name read), written before the caller acts on the result (a root created by
    a run that then failed is not created again by the next one). A {!root}
    error → [Error], no program run. *)

val account : Db.t -> (string option, Db.error) result Fut.t
(** [Settings.get Drive_account]: the Drive account chosen in 4m. A blank value
    ([Row `WrongType]) is [Ok None] plus one console error « drive: account
    unreadable: … »; any other error is returned. *)

val store_account :
  Db.t ->
  account:string ->
  storage:Herbier_domain.Photo.Original_target.t option ->
  (unit, Db.error) result Fut.t
(** The sheet's « Utiliser un autre compte », or the 4m Drive radio: reads
    {!account}, then writes in one transaction
    {!Herbier_store.Settings.drive_choice} with
    [~account:(Herbier_photos.Drive.account_to_store ~stored ~account)] and
    [~storage]: another account → [Drive_account], [Drive_account_changed_at]
    and [Drive_root_folder] unset (the old Drive's id; the name is kept); with
    [storage = Some s], [Storage_target = s] in the same transaction, so an
    error leaves the storage unchanged too. Nothing to write → [Ok ()], no
    transaction. Console lines « drive: account changed, root folder forgotten
    », « drive: storage set with the account »; an error (the read, or the
    transaction, rolled back) is returned and logged « drive: account not
    written: … ». Run it inside [Upload_queue.exclusive]. *)

val seed :
  Db.t -> session_email:string option -> (string option, Db.error) result Fut.t
(** Keeps an older install's root folder: reads {!stored} and {!account}, and
    when {!Herbier_photos.Drive.seed_account} gives [Some email], writes
    [Drive_account] = [email] alone (the id stays) and returns it, with the
    console line « drive: root folder kept for the signed-in account »; else
    writes nothing, [Ok None]. Run it inside [Upload_queue.exclusive]. *)

val forget_account : Db.t -> (unit, Db.error) result Fut.t
(** Unsets [Drive_account] and [Drive_root_folder] in one transaction
    (#dev/drive « Oublier le compte »): the folder belongs to the account; the
    name is kept. Console line « drive: root folder forgotten with the account
    »; an error is returned and logged « drive: root folder not written: … ».
    Run it inside [Upload_queue.exclusive]. *)
