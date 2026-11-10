(** The WebView's time zone, through JavaScript's [Date]. *)

val offset_at_s : float -> int
(** [offset_at_s t] for [t] in seconds since the epoch: seconds east of UTC of
    the device's zone at that instant
    ([-60 * new Date(t * 1000).getTimezoneOffset()]), so it follows daylight
    saving time for that date, not today's. *)

val local_offset_s :
  year:int ->
  month:int ->
  day:int ->
  hour:int ->
  minute:int ->
  second:int ->
  int
(** Seconds east of UTC of the device's time zone at that local wall-clock time
    ([month] 1–12):
    [-60 * new Date(year, month - 1, day, hour, minute,
     second).getTimezoneOffset()]. So it follows daylight saving time for the
    date given, not today's. A local time skipped by a DST change gets the
    offset JavaScript resolves it to. JavaScript reads a [year] in 0–99 as 1900
    \+ [year], so such a year gets the offset of that 20th-century date. *)
