(** 4m « Noms de lieux », « IGN hors-ligne »: « Toute la France » and «
    Supprimer tout », around the pack rows and the département picker.

    - [summary]: when packs exist, a line
      ({!Herbier_ui_model.France_text.summary}) and « Supprimer tout ». The line
      is a [<button>] with a chevron and [aria-expanded] that shows or hides the
      pack rows ([expanded]; the caller gives the list the id [packs], its
      [aria-controls]). « Supprimer tout » asks inline
      ({!Herbier_ui_model.France_text.delete_all_question} and its note) before
      {!App.delete_all_packs}; an error goes to [set_message].
    - [button]: « Toute la France ». A tap shows « Chargement… »
      ({!App.france_plan} and {!App.connection}; another tap meanwhile does
      nothing), then an inline panel: the scope (overseas included), the
      estimate, the background note, the mobile-data warning when
      {!Herbier_ui_model.France_text.warn_mobile} says so for the plan's
      transfer size (never a block), « Télécharger » (absent when nothing is
      left) and « Annuler ». A failed plan, or a list with no département, shows
      its error and « Réessayer ».
    - [after]: that panel, then, during a run, a [<progress>] bar, a status line
      (progress, retry and its reason, interruption; always in the page, empty
      when there is nothing to say) and « Interrompre » ({!App.cancel_france});
      after a run, its outcome line (until the next tap of « Toute la France »
      or « Supprimer tout »).

    [busy] is true while a département downloads, a run is going or « Supprimer
    tout » deletes (from {!App.downloading} and {!App.france}): the caller
    disables « Ajouter un département » with it. [locked] is the last two only
    ({!App.is_busy}): the caller disables each pack's « Supprimer » with it.
    [running] ({!App.is_running}) hides the caller's « Téléchargement de … »
    line during a run. *)

type t = {
  summary : Brr.El.t list;  (** above the pack rows *)
  expanded : bool React.signal;
      (** the pack rows are shown: toggled by the summary line, false at first
      *)
  button : Brr.El.t;  (** next to « Ajouter un département » *)
  after : Brr.El.t list;  (** under the picker *)
  running : bool React.signal;
  busy : bool React.signal;
  locked : bool React.signal;
  bindings : Rb.binding list;
}

val packs_id : string
(** The id the caller gives the pack rows' holder. *)

val v : App.t -> set_message:(string option -> unit) -> t
