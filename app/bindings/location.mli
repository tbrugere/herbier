(** [window.location.replace], which Brr does not bind: a navigation that
    replaces the current history entry instead of adding one. *)

val replace : Brr.Uri.t -> unit
(** [replace uri] navigates to [uri] in place of the current entry. When only
    the fragment differs, the page stays and [hashchange] fires asynchronously,
    as for any fragment navigation. *)
