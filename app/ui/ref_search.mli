(** 4i's reference search, without timers or network: the screen runs the
    effects ({!effect_}: [effect] is a keyword since OCaml 5.3) and feeds back
    their outcome. Stale timers and answers (an older [seq]) change nothing.
    Pure; never raises. *)

type status =
  | Blank  (** The trimmed query is empty: the section shows nothing. *)
  | Pending  (** Debounce running or request in flight: « Recherche… ». *)
  | Found of Herbier_refs.Resolve.Candidate.t list
      (** [[]] → « Aucune espèce trouvée dans GBIF. » *)
  | Offline  (** « Recherche indisponible hors-ligne. » *)
  | Failed of string
      (** « La recherche n'a pas abouti. » + « Réessayer »; the message is for
          the console. *)

val equal_status : status -> status -> bool

type t

val query : t -> string
(** Trimmed. *)

val status : t -> status
val seq : t -> int

type effect_ =
  | No_effect
  | Wait of {seq : int; ms : int}  (** Start a timer, then {!elapsed} [~seq]. *)
  | Fetch of {seq : int; q : string}
      (** [Resolver.search ~q], then {!answered} [~seq]. *)

val debounce_ms : int
(** 300 *)

val init : online:bool -> string -> t * effect_
(** The prefilled query: trimmed blank → [Blank], [No_effect]; offline →
    [Offline], [No_effect]; online → [Pending], [Fetch] at once (nothing was
    typed, no debounce). [seq] starts at 0 and the first effect carries it. *)

val typed : online:bool -> string -> t -> t * effect_
(** Trimmed text equal to {!query} → unchanged, [No_effect]. Otherwise [seq + 1]
    and: blank → [Blank], [No_effect]; offline → [Offline], [No_effect]; online
    → [Pending], [Wait {seq; ms = debounce_ms}]. *)

val elapsed : online:bool -> seq:int -> t -> t * effect_
(** A stale [seq] → unchanged, [No_effect]. The current one: offline →
    [Offline], [No_effect]; online → status unchanged, [Fetch {seq; q = query}].
*)

val answered :
  seq:int ->
  ( Herbier_refs.Resolve.Candidate.t list,
    Herbier_refs.Resolve.unresolved )
  result ->
  t ->
  t
(** Stale → unchanged. [Ok l] → [Found l]; [Error (Unavailable m)] → [Failed m];
    [Error No_species | Error Observation_link] → [Found []]. *)

val network : online:bool -> t -> t * effect_
(** Going offline with status [Pending] or [Failed _] → [seq + 1] (drops the
    request in flight), [Offline], [No_effect]. Coming online with status
    [Offline] or [Failed _] and a non-blank query → [seq + 1], [Pending],
    [Fetch] at once. Anything else unchanged, [No_effect] ([Found] stays shown
    offline). *)

val retry : online:bool -> t -> t * effect_
(** « Réessayer »: non-blank query and online → [seq + 1], [Pending], [Fetch];
    offline → [Offline], [No_effect]; blank → unchanged. *)
