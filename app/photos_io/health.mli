(** The weekly check of the originals in Drive on the device (architecture §5):
    reads the photos whose original is in Drive, asks Drive about each
    ({!Herbier_photos.Health.program} over {!Drive.health}), commits the state
    changes, and records the date in [settings]. The token comes from the caller
    (silent: a background check never shows the consent). *)

module Db := Herbier_store_io.Db

type t

val create :
  db:Db.t ->
  commit:(Herbier_store.Outbox.edit list -> (int, Db.error) result Fut.t) ->
  token:(unit -> (string, string) result Fut.t) ->
  drop_token:(string -> unit Fut.t) ->
  t
(** No IO. [commit] is the app's (outbox, [saved], engine). *)

type outcome =
  | Not_due  (** checked less than {!Herbier_photos.Health.interval} ago *)
  | Busy  (** a check is running: nothing started *)
  | Checked of Herbier_photos.Health.report
      (** the round reached its last photo ([stopped = None]); date recorded,
          cursor cleared. The report covers this run's part of the round. *)
  | Stopped of string Drive.error
      (** [Token e]: no token, or a renewal that failed midway; nothing
          committed, cursor unchanged. [Drive e]: the report's [Account] error;
          the changes found before it committed and the cursor set to the last
          photo reached. Date not recorded either way. *)
  | Raised of string  (** an exception raised while the check started *)
  | Store of Db.error  (** a read or the commit failed; date not recorded *)

val outcome_to_string : outcome -> string
(** One line: ["not due"], ["busy"], ["checked …"]
    ({!Herbier_photos.Health.summary}), ["stopped: token: …"] /
    ["stopped: drive: …"] ({!Drive.error_to_string}), ["raised: …"],
    ["store: …"]; never a token or a file id. *)

val run : t -> force:bool -> outcome Fut.t
(** Single-flight: a call while a check runs → [Busy] at once. Otherwise:
    + unless [force]: [Settings.get Drive_health_checked_at] (a read or decode
      error counts as never checked, logged); not {!Herbier_photos.Health.due}
      [~now] → [Not_due] (no other read, no token);
    + [Photos.in_drive] → {!Herbier_photos.Health.items} (read error → [Store])
      with [~account_changed_at] from [Settings.get Drive_account_changed_at]
      (unreadable → [None], logged), then {!Herbier_photos.Health.resume} after
      [Settings.get Drive_health_cursor] (unreadable → from the first, logged):
      a round that stopped goes on where it stopped;
    + {!Drive.health} with [token] / [drop_token] ([Error e] → [Stopped e],
      nothing written);
    + the report's [changes], when any, in one [commit] of
      [Photos.set_upload id ~state ~drive_file_id:(Some item.file_id) ~at:now]
      each ([Error e] → [Store e], nothing else written);
    + [stopped = Some e] → [Settings.set Drive_health_cursor] to the report's
      [reached] (kept when [None]) → [Stopped (Drive e)]; else
      [Settings.set Drive_health_checked_at now] then
      [Settings.unset Drive_health_cursor] (their errors are console lines only)
      → [Checked report].

    An empty list (or a cursor past the last photo) ends the round without
    asking a token. Each outcome but [Not_due] is one console line « health:
    <outcome_to_string> ». Never raises; always resolves. *)
