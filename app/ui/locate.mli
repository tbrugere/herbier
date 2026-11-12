(** The device fix of the two map screens (4b « Ma position », 5b « Ma position
    » and its entry fix), with their shared camera fallback. *)

val world : State.camera
(** Centre [0, 0] at zoom 1: the camera when nothing better is known. *)

val current :
  what:string -> (Herbier_domain.Places.point, Map_sheet.notice) result Fut.t
(** One high-accuracy fix (10 s timeout, fixes up to 30 s old accepted). A
    failure is logged with [Console.warn] under [what] and given as the notice
    the screen shows: {!Map_sheet.position_failure} of a rejected call's code,
    else [Position_unavailable]. Never raises. *)
