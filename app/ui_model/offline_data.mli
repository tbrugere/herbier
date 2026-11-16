(** 4m's « Données hors-ligne » row: the sizes kept on the phone and the texts
    of « Libérer », which frees the reference photos only (the previews are the
    only local copy of a photo; the reference texts are synced and are the
    offline fiche). Pure. *)

type usage = {previews : float; reference_photos : float} [@@deriving eq]
(** Bytes kept on the phone (floats: a sum passes 2{^ 31}, the width of [int]
    under js_of_ocaml). *)

type state = Measuring | Measured of usage | Unknown  (** a read failed *)
[@@deriving eq]

val detail : state -> string
(** The row's meta line. [Measuring] → « Aperçus photos … · Photos de référence
    … »; [Measured u] → « Aperçus photos <size previews> · Photos de référence
    <size reference_photos> » ({!Fr_text.size}); [Unknown] → « Taille inconnue
    ». *)

val can_free : state -> bool
(** [Measured u] with [u.reference_photos > 0.]. *)

val confirm_title : string
(** « Libérer les photos de référence ? » *)

val confirm_text : string
(** « Elles seront retéléchargées à l’ouverture de chaque fiche, avec le réseau.
    Vos photos et vos fiches restent. » *)

type free_failure =
  | Busy  (** a thumbnails download or another « Libérer » is running *)
  | Failed  (** clearing the rows or removing the files failed *)

val free_failure_text : free_failure -> string
(** [Busy] → « Des photos de référence se téléchargent : réessayez dans un
    instant. »; [Failed] → « La place n’a pas pu être libérée. ». *)

val freed_text : float -> string
(** The bytes freed: « <size n> libérés. » ({!Fr_text.size}). *)

val freed : before:float -> state -> string
(** After a « Libérer » that succeeded, [before] the reference photos' size
    measured before it and the state measured after: {!freed_text} of
    [before - reference_photos] (0 when the directory grew meanwhile) for
    [Measured]; of [before] for [Measuring] / [Unknown] (the directory was
    removed whole, so all of it went). *)
