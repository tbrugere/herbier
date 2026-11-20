(** The identification layer (6b, 6c, 6f, 6g) as a pure machine: the screen runs
    the {!command}s and feeds back the {!event}s. One request at a time; an
    answer to an older [seq] changes nothing. A request leaves only on {!open_}
    or on a tap event ([Set_organ], [Photo_added], [Set_flora], [Force],
    [Retry]): never on [Answered] or [Slow]. Never raises. *)

module Organ := Herbier_identify.Organ

type outcome =
  | Left
      (** ←, Android back, « Continuer sans attendre »: back to the caller with
          its photos; a request in flight is not aborted *)
  | Chosen of Herbier_identify.Plantnet.proposal  (** the card's button *)
  | None_matches  (** « Aucune ne correspond » *)

val equal_outcome : outcome -> outcome -> bool

(** What a caller that resolves a chosen proposal does once the layer closed
    (6i, 6k). *)
type after =
  | Stay  (** back to the caller, focus on its Identifier button *)
  | Resolve of Herbier_identify.Plantnet.proposal
      (** resolve the proposal through GBIF, then the caller's save or link *)

val equal_after : after -> after -> bool

val after_close : outcome -> after
(** [Chosen p] → [Resolve p]; [Left], [None_matches] → [Stay]. *)

type phase =
  | Sending of {slow : bool}
      (** 6b; [slow]: {!slow_ms} passed, the skeletons say « Pl@ntNet… » *)
  | Proposals of Herbier_identify.identified
      (** 6c, or 6f when [uncertain]; never with [proposals = []] *)
  | Failed of Failure.t  (** 6g *)
  | Closed of outcome

val equal_phase : phase -> phase -> bool

type request = {
  flora : string;  (** {!Identify_settings.flora_id} of [t.flora] *)
  no_reject : bool;
  organs : Organ.sent list;  (** one per photo, in order *)
}

val equal_request : request -> request -> bool

type t = {
  caller : Caller.t;
  organs : Organ.sent list;
      (** one per photo, in photo order; 1 to {!Organ.max_photos} (none only
          when {!open_} was given none) *)
  detected : Organ.t option list;
      (** Pl@ntNet's organ per photo from the last answer, same length as
          [organs] ([None] where unknown; all [None] before any answer and for
          an added photo) *)
  flora : Herbier_store.Settings.flora option;  (** [None] = « Automatique » *)
  no_reject : bool;  (** of the request last sent *)
  seq : int;  (** of the request last sent; 1 for the first, 0 for none *)
  taking : bool;
      (** a [Take_photo] is pending: set by [Add], cleared by [Photo_added] *)
  phase : phase;
}

val equal : t -> t -> bool

type command =
  | Send of {seq : int; request : request}
      (** identify the caller's photos zipped with [request.organs], then feed
          [Answered {seq; _}] *)
  | Wait_slow of {seq : int; ms : int}  (** a timer, then [Slow seq] *)
  | Take_photo of Organ.sent
      (** the caller adds a photo sent with that organ, then [Photo_added] *)
  | Save_flora of Herbier_store.Settings.flora option  (** the 4m setting *)
  | Close of outcome

val equal_command : command -> command -> bool

type event =
  | Slow of int
  | Answered of {
      seq : int;
      result : (Herbier_identify.identified, Failure.error) result;
    }
  | Back
  | Choose of int  (** 0-based index into the proposals *)
  | None_matches
  | Set_organ of {photo : int; organ : Organ.t}  (** 0-based photo *)
  | Add  (** the « + <organe> » / « + photo » tile *)
  | Photo_added of Organ.sent option  (** [None]: the caller cancelled *)
  | Set_flora of Herbier_store.Settings.flora option
  | Force  (** « Voir quand même les propositions peu probables » *)
  | Retry

val slow_ms : int
(** 600. *)

val request : t -> request

val open_ :
  caller:Caller.t ->
  flora:Herbier_store.Settings.flora option ->
  Organ.sent list ->
  t * command list
(** The first {!Organ.max_photos} organs are kept. [[]] → [phase = Closed Left],
    [seq = 0], [[Close Left]] (nothing to send). Else [seq = 1],
    [no_reject = false], [detected] all [None], [Sending {slow = false}],
    [[Send {seq = 1; request}; Wait_slow {seq = 1; ms = slow_ms}]]. *)

val step : t -> event -> t * command list
(** "Re-ask" below = [seq + 1], [Sending {slow = false}], commands
    [[Send {seq; request}; Wait_slow {seq; ms = slow_ms}]] (with [request] of
    the new state). First matching rule:
    - [Closed _]: any event → unchanged, [[]].
    - [Back] → [Closed Left], [[Close Left]] (any phase).
    - [Slow s]: [Sending _] and [s = seq] → [slow = true], [[]]; else unchanged.
    - [Answered {seq = s; _}] with [s <> seq] or the phase not [Sending _] →
      unchanged, [[]].
    - [Answered {result = Ok i}]: [i.answer.proposals = []] →
      [Failed (No_plant {can_force = not no_reject})]; else [Proposals i] and
      [detected] = [i.answer.detected] truncated / padded with [None] to the
      length of [organs]. [[]].
    - [Answered {result = Error e}] → [Failed (Failure.of_error ~no_reject e)];
      [detected] unchanged; [[]].
    - [Photo_added (Some o)]: {!accepts_photo} → [organs @ [o]],
      [detected @ [None]], [no_reject = false], [taking = false], re-ask. Else
      [taking = false], [[]].
    - [Photo_added None] → [taking = false], [[]].
    - [Add], [Set_organ _], [Set_flora _], [Force], [Retry] while [taking] →
      unchanged, [[]]: the photo being taken is not lost to a re-ask.
    - [Choose k]: [Proposals i], [0 <= k < length] → [Closed (Chosen p_k)],
      [[Close (Chosen p_k)]]; else unchanged.
    - [None_matches]: [Proposals _] → [Closed None_matches],
      [[Close None_matches]]; else unchanged.
    - [Set_organ {photo; organ}]: [Proposals _], [photo] in range, and
      [Organ.effective (organs.(photo)) ~detected:(detected.(photo)) <> Some
       organ] → [organs.(photo) := Given organ], [no_reject = false], re-ask.
      Else unchanged (same organ: no request).
    - [Add]: {!add_tile} is [Some s] → [taking = true],
      [[Take_photo (Organ.sent_of_suggestion s)]]; else unchanged, [[]].
    - [Set_flora f]: [Proposals _] and [f] differs from [flora]
      ([Option.equal Settings.equal_flora]) → [flora = f], [no_reject = false],
      commands [Save_flora f :: re-ask's]. Else unchanged.
    - [Force]: [Failed (No_plant {can_force = true})] → [no_reject = true],
      re-ask. Else unchanged.
    - [Retry]: [Failed f] with [Failure.retry f] → re-ask with [no_reject]
      unchanged. Else unchanged. *)

val accepts_photo : t -> bool
(** Whether a photo added now is kept and re-asked: [Proposals _], or [Failed f]
    with [Failure.reask f], and fewer than {!Organ.max_photos} photos. *)

val add_tile : t -> Organ.suggestion option
(** The tile shown: [Proposals _] → {!Organ.suggest} of the effective organs
    ([None] at five photos); [Failed f] with [Failure.reask f] and fewer than
    five photos → [Some Add_photo]; else [None]. *)

val effective_organs : t -> Organ.t option list
(** [Organ.effective] of each photo with its [detected]. *)
