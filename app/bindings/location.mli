(** [window.location]'s parts Brr does not bind. *)

val replace : Brr.Uri.t -> unit
(** [replace uri] navigates to [uri] in place of the current entry. When only
    the fragment differs, the page stays and [hashchange] fires asynchronously,
    as for any fragment navigation. *)

val origin : unit -> string
(** [window.location.origin] (["https://localhost"] in the app). *)
