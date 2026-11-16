(** 4m's « Données hors-ligne » row, in the « Sur le téléphone » card: the sizes
    of the previews and of the reference photos ({!App.offline_usage}, read at
    mount and after « Libérer »; a failed read is « Taille inconnue » and a
    console line), and « Libérer », active when
    {!Herbier_ui_model.Offline_data.can_free} and no « Libérer » runs. A tap
    asks in a dialog; « Libérer » there (still active when chosen) runs
    {!App.free_reference_photos}, then measures again, the sizes « … » and the
    button off meanwhile. A status line under the card says what was freed or
    why nothing was; the next tap clears it. *)

type t = {
  row : Brr.El.t;  (** for the card *)
  after : Brr.El.t list;
      (** the status line (hidden while empty) and the dialog
          ([position: fixed]), for right after the card *)
  bindings : Rb.binding list;
}

val v : App.t -> t
