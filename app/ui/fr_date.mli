(** Dates and times as the French handoff writes them. Pure: the caller gives
    the time zone offset ({!Herbier_bindings.Js_date}). *)

val local_date : tz_offset_s:int -> Ptime.t -> Ptime.date
(** The wall-clock date of the instant in that zone. *)

val day_header : this_year:int -> Ptime.date -> string
(** The Journal's day header: ["Ven. 12 juin"], ["Lun. 1 mars"] (weekday
    abbreviated with a capital and a dot, day without leading zero, month in
    full, lower case), then the year when it is not [this_year]:
    ["Mer. 3 décembre 2025"]. No weekday for a date that does not exist. *)

val long_day : Ptime.date -> string
(** {!day_header} always with the year: ["Ven. 12 juin 2026"] (4h, 4k). *)

val day_time : tz_offset_s:int -> Ptime.t -> string
(** {!long_day} of the instant's date in that zone, then its {!time}:
    ["Ven. 12 juin 2026 · 14:32"] (4h, 4k). *)

val time : tz_offset_s:int -> Ptime.t -> string
(** ["14:32"], ["09:05"]: hours and minutes, zero-padded. *)

val year : tz_offset_s:int -> Ptime.t -> int
(** The wall-clock year of the instant in that zone. *)

val month_name : int -> string
(** ["janvier"] … ["décembre"] for 1..12; [""] outside. *)

val day_month : Ptime.date -> string
(** ["12 juin"], ["1 mars"]: the 4f hero's date and « modifié le … ». *)

val full_date : Ptime.date -> string
(** ["12 juin 2026"]: the 4f observation rows. *)

val ago : now:Ptime.t -> Ptime.t -> string
(** Elapsed time as 4f's « mis à jour … » says it, from the whole days [d]
    between the instant and [now] (floor): [d < 1] (or the instant after [now])
    → ["aujourd'hui"]; [d < 14] → ["il y a <d> j"]; [d < 60] →
    ["il y a <d/7> sem."]; [d < 365] → ["il y a <d/30> mois"]; else
    ["il y a <d/365> an"] (["ans"] from 2). *)
