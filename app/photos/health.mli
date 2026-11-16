(** The weekly check that the originals in Drive are still there (architecture
    §5): which photos to ask about, what Drive's answer means for each, and the
    whole check as one {!Drive.t} program. Without IO; run by
    [Herbier_photos_io.Health]. Nothing here raises. *)

module Photo := Herbier_domain.Photo
module Photo_id := Herbier_domain.Ids.Photo_id

val interval : Ptime.Span.t
(** 7 days. *)

val due : now:Ptime.t -> last:Ptime.t option -> bool
(** [last = None] → [true]; [last] after [now] (the clock went back) → [true];
    else [now - last >= interval]. *)

type item = {
  photo_id : Photo_id.t;
  file_id : string;  (** the photo's [drive_file_id], trimmed *)
  state : Photo.Upload_state.t;  (** [Uploaded] or [Original_missing] *)
}

val equal_item : item -> item -> bool

val items : Photo.t list -> item list
(** The photos to ask about, in the list's order: live ([deleted_at = None]),
    [original_target = Drive], [drive_file_id = Some id] with [id] non-blank
    ({!Herbier_domain.Text.non_blank}; the trimmed value is kept), and
    [upload_state] [Uploaded] or [Original_missing]. Every other photo is left
    out ([Pending]/[Failed] are the queue's, [App_only] has no original). This
    is the rule; [Photos.in_drive] only prefilters the rows read. *)

val resume : after:Photo_id.t option -> item list -> item list
(** The items whose photo id sorts after [after] (ids compared as their text,
    the order of [Photos.in_drive]), in the list's order; [None] → all. A round
    that stopped resumes there, so a long list is covered over several runs; a
    cursor whose photo is gone still resumes at the next id. *)

val verdict :
  Photo.Upload_state.t -> Drive.presence -> Photo.Upload_state.t option
(** The new state when it changes: [Uploaded] + [Trashed | Missing] →
    [Some Original_missing]; [Original_missing] + [Present] → [Some Uploaded]
    (restored from the bin); anything else → [None] (same state, or a state the
    check does not own: [Pending]/[Failed] → [None] whatever the presence). *)

type change = {item : item; state : Photo.Upload_state.t  (** the new one *)}

val equal_change : change -> change -> bool

type report = {
  checked : int;  (** items Drive answered for ([Ok] presence) *)
  changes : change list;  (** in item order *)
  skipped : (item * Drive.error) list;
      (** {!Drive.error_scope} [This_file] errors, in order *)
  stopped : Drive.error option;  (** the [Account] error that ended it *)
  reached : Photo_id.t option;
      (** the last item answered or skipped (where a stopped round resumes);
          [None] before the first *)
}

val equal_report : report -> report -> bool

val empty_report : report
(** [0], [[]], [[]], [None], [None]. *)

val program : item list -> report Drive.t
(** For each item in order, {!Drive.presence} [~file_id]: [Ok p] →
    [checked + 1], and a {!change} when {!verdict} gives [Some s]; [Error e]
    with {!Drive.error_scope} [This_file] → into [skipped], next item; either
    way [reached] is that item. [Account] → [stopped = Some e] and the program
    ends (no request for the items after it, [reached] left at the item before).
    [[]] → [Done empty_report], no request. Exactly these requests
    ({!Drive.get_trashed} [~file_id] each), in this order, nothing else. *)

val summary : report -> string
(** One console line, never a file id: ["checked 12, changed 1, skipped 0"],
    then [", stopped: <Drive.error_to_string e>"] when stopped. *)
