(** 4m « Toute la France » texts and the mobile-data warning rule. Sizes through
    {!Fr_text.size}, counts through {!Fr_text.plural}. Pure. *)

val button : string
(** ["Toute la France"] *)

val loading : string
(** ["Chargement…"] *)

val retry : string
(** ["Réessayer"] *)

val no_departements : string
(** ["Aucun département reçu de l’IGN."]: a list with no département. *)

val scope : total:int -> string
(** ["Métropole, Corse et outre-mer (Guadeloupe, Martinique, Guyane, La Réunion,
     Mayotte) : 101 départements."] for [total = 101]. *)

val estimate : total:int -> todo:int -> bytes:int -> string
(** [todo = 0] → ["Tous les départements sont déjà téléchargés."];
    [todo = total] → ["101 départements · environ 52,9 Mo"]; else
    ["96 à télécharger sur 101 · environ 50,4 Mo"]. *)

val keep_open : string
(** ["Gardez Herbier ouvert pendant le téléchargement ; vous pourrez
     l’interrompre et le reprendre."] *)

val large_bytes : int
(** [10_000_000] *)

val warn_mobile : cellular:bool -> bytes:int -> bool
(** [cellular && bytes >= large_bytes]. *)

val mobile_warning : bytes:int -> string
(** ["Connexion par données mobiles : environ 65,7 Mo seront téléchargés."];
    [bytes]: what the WFS sends (gzip), not the stored size. *)

val start : string
(** ["Télécharger"] *)

val dismiss : string
(** ["Annuler"] *)

val interrupt : string
(** ["Interrompre"] *)

val progress :
  position:int ->
  total:int ->
  bytes:int ->
  estimate:int ->
  current:string option ->
  string
(** ["37 / 101 · 12,4 Mo sur environ 52,9 Mo · Haut-Rhin"]; [current = None]
    drops [" · <current>"]. [bytes]: this run's; [estimate]: the plan's. *)

(** Why a retry waits, in a few words. *)
type retry_reason =
  | Connection_lost  (** ["connexion perdue"] *)
  | Timed_out  (** ["délai dépassé"] *)
  | Unavailable  (** ["service indisponible"] *)
  | Bad_answer  (** ["réponse invalide"] *)

val retrying :
  current:string ->
  reason:retry_reason ->
  attempt:int ->
  attempts:int ->
  wait_ms:int ->
  string
(** ["Haut-Rhin : service indisponible, nouvel essai dans 20 s (2/3)."]; seconds
    = [(wait_ms + 999) / 1000]. *)

val cancelling : string
(** ["Interruption après le département en cours…"] *)

val complete : downloaded:int -> bytes:int -> failed:string list -> string
(** [failed = []] → ["Terminé : 96 départements · 50,4 Mo."]; else
    ["Terminé : 94 départements · 49,5 Mo. Non téléchargés : 2A · Corse-du-Sud,
     973 · Guyane. Relancez « Toute la France » pour réessayer."] ([failed]
    joined by [", "], given as {!Pack_text.title}s). [downloaded = 0] →
    ["Terminé : 0 département · 0 o."] (the plural rule as is). *)

val cancelled : position:int -> total:int -> string
(** ["Interrompu à 37 / 101. Relancez « Toute la France » pour reprendre."] *)

val stopped : position:int -> total:int -> reason:string -> string
(** ["Arrêté à 37 / 101 : <reason> Relancez « Toute la France » pour
     reprendre."]; [reason] ends with a full stop ([App.pack_error_to_string]).
*)

val summary : count:int -> bytes:int -> string
(** ["12 départements · 4,1 Mo"]: above the pack rows when [count > 0]. *)

val delete_all : string
(** ["Supprimer tout"] *)

val delete_all_question : count:int -> bytes:int -> string
(** ["Supprimer les 12 départements (4,1 Mo) ?"]; [count = 1] →
    ["Supprimer le département (89 ko) ?"]. *)

val delete_all_note : string
(** ["Les noms déjà donnés aux observations restent."] *)
