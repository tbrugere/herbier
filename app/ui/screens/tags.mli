(** 4l Tags (modal): the four most used tags as cards, the others as chips with
    their plant count. A tap filters the collection by that tag alone and
    returns to Collection ([history.back()], as 4l is opened from it); « Gérer »
    opens 5d. The subtitle says when there is no tag or the read failed. Covers
    are placeholders. *)

val v : App.t -> Screen.t
