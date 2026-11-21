(** The long-press delete of 4a's cards and 4c's rows: reads what the record
    takes with it now, asks with a {!Widgets.Dialog} (title and text of
    {!Herbier_ui_model.Delete_plan}, « Supprimer » Danger / « Annuler »
    Secondary), and on « Supprimer » reads it again and saves
    {!Herbier_ui_model.Delete_plan}'s edits through {!App.save}: the same edits
    as 5a and 4h. The list reloads on {!App.saved}, as for any save. *)

type t = {
  el : Brr.El.t;  (** the dialog's host: put it once in the screen *)
  plant : from:Brr.El.t -> Herbier_domain.Ids.Plant_id.t -> unit;
  observation : from:Brr.El.t -> Herbier_domain.Ids.Observation_id.t -> unit;
  bindings : Rb.binding list;
}

val v : App.t -> scope:string -> t
(** [scope] names the screen in console lines ([Log.db ~scope]).

    [plant ~from id] / [observation ~from id], called from a long-press on
    [from] (outside update steps):
    - is ignored while a read, a shown dialog or a save of this [t] is under way
      (one question at a time);
    - reads the target: a plant, its observations, their photos and its tags; an
      observation and its photos. A read error is logged and toasted
      ([plant_failure] / [observation_failure]); the record gone (no live row)
      is one console line, nothing shown;
    - shows the dialog (focus on its first button), registering an {!Overlay}
      ([Light]) whose [close] is « Annuler »; Escape on the dialog is « Annuler
      » too;
    - « Annuler » hides it, removes the overlay, writes nothing and gives the
      focus back to [from];
    - « Supprimer » hides it, removes the overlay, reads the target again (a
      pull may have changed its dependents; gone, nothing is saved, one console
      line) and saves the edits of that read at [Ptime_clock.now ()]; a failed
      read or save is logged and toasted, a success shows nothing more (the
      route does not change).

    Releasing [bindings] (the screen leaves) drops a shown dialog and its
    overlay; a read answering later shows nothing, a save still commits and its
    failure is still toasted. Never raises. *)
