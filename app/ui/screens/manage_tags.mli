(** 5d Gérer les tags (modal): check tags to delete or merge them (the most used
    one wins and keeps its name), rename one in place with ✎. Changes are staged
    ({!Tag_edits}) and saved in one transaction on « Terminé »; « Annuler »
    discards them. After saving, {!State.filters} forgets deleted tags and
    follows merged ones to the tag that kept them. *)

val v : App.t -> Screen.t
