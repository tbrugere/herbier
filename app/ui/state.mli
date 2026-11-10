(** Global UI state shared by several screens (handoff « État », Global):
    filters common to Collection, Carte and Journal, network status, account.
    Per-screen state lives in each screen.

    One value of {!t} is created at startup and passed to the screens. Setters
    are called from outside an update step (a DOM callback, a resolved future),
    never from a binding. *)

module Tag_id := Herbier_domain.Ids.Tag_id

type filters = {
  tags : Tag_id.t list;  (** a plant must have all of them; [[]] = « Toutes » *)
  year : int option;  (** Journal's year chip; [None] = every year *)
  to_identify_only : bool;  (** Journal's « À identifier · n » chip *)
}

val no_filters : filters
val equal_filters : filters -> filters -> bool

type network = {online : bool; pending_uploads : int}

type account = {
  google_signed_in : bool;
  storage : Herbier_domain.Photo.Original_target.t;
      (** the Settings choice, kept while signed out: Drive asks for the sign-in
          at the first photo to upload *)
}

type t

val create : network:network -> account:account -> t
(** Filters start empty; [network] and [account] are what the platform and the
    settings say at startup. *)

val filters : t -> filters React.signal
val network : t -> network React.signal
val account : t -> account React.signal

val set_filters : t -> ?step:React.step -> filters -> unit
(** [step] groups this change with other setters in one update step (style guide
    9.3); without it the setter runs its own step. *)

val set_network : t -> ?step:React.step -> network -> unit
val set_account : t -> ?step:React.step -> account -> unit
