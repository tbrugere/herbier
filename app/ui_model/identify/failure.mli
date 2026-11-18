(** 6g's variants. The user sees seven of them; the console line (Make's, logged
    by App.identify) is what tells the causes of [Not_answered] apart. Pure. *)

type error =
  | Not_sent_offline  (** App's [Identify_offline]: nothing sent *)
  | Preview_unreadable  (** App's [Preview_unreadable _]: nothing sent *)
  | Plantnet of Herbier_identify.Plantnet.error

val equal_error : error -> error -> bool

type t =
  | No_plant of {can_force : bool}
      (** « Aucune plante reconnue »; [can_force]: « Voir quand même » shown *)
  | Not_answered  (** « Pl@ntNet n'a pas répondu », « Réessayer » *)
  | Offline  (** « Réessayer » *)
  | Used_up  (** 429 *)
  | Key_refused  (** 401 *)
  | No_key
  | Unreadable

val equal : t -> t -> bool
val pp : Format.formatter -> t -> unit
val show : t -> string

val of_error : no_reject:bool -> error -> t
(** [no_reject]: the request that failed was sent with [no-reject=true].
    - [Plantnet No_plant] → [No_plant {can_force = not no_reject}];
    - [Plantnet (Unreachable _ | Key_not_exposed | Refused_request _ | Malformed
       _ | No_photo)] → [Not_answered];
    - [Plantnet Quota_used_up] → [Used_up]; [Plantnet Key_refused] →
      [Key_refused]; [Plantnet No_key] → [No_key];
    - [Not_sent_offline] → [Offline]; [Preview_unreadable] → [Unreadable]. *)

val retry : t -> bool
(** « Réessayer »: [Not_answered], [Offline] → [true]; else [false]. *)

val reask : t -> bool
(** Whether 6g keeps the « + photo » tile (a re-ask with one more photo):
    [No_plant _], [Not_answered], [Offline] → [true]; else [false]. *)

val of_gate : Identify_settings.gate -> (Identify_settings.Key.t, error) result
(** The key a request is sent with, or the error it gets without being sent:
    [Ready k] → [Ok k]; [Offline], [Waiting] → [Error Not_sent_offline];
    [No_key] → [Error (Plantnet No_key)]. *)
