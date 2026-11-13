(** A screen's content built from store reads. *)

val v :
  ?reload:unit React.event ->
  ?failed:(unit -> Brr.El.t * Rb.binding list) ->
  what:string ->
  Brr.El.t ->
  (unit -> ('a, Herbier_store_io.Db.error) result Fut.t) ->
  ('a -> Brr.El.t * Rb.binding list) ->
  Rb.binding list
(** [render] of what [load] returns becomes the container's only child, again on
    each [reload] occurrence, and the previous rendering's bindings are
    released. Errors go to the console under [what]; a first load that fails
    shows [failed] (nothing when absent), a later one keeps what is shown. *)

val live :
  reload:unit React.event ->
  what:string ->
  gone:(unit -> Brr.El.t * Rb.binding list) ->
  failed:(unit -> Brr.El.t * Rb.binding list) ->
  Brr.El.t ->
  (unit -> ('a option, Herbier_store_io.Db.error) result Fut.t) ->
  ('a React.signal -> Brr.El.t * Rb.binding list) ->
  Rb.binding list
(** Like {!v} with [reload], but [render] is called once and given a signal: a
    reload sets it, so what the rendering holds open (a dialog, an editor, an
    input) stays open across one. [None] shows [gone] (a reload that finds it
    again renders anew); a first load that fails shows [failed]. *)

val notice : ?back:string -> string -> Brr.El.t * Rb.binding list
(** A screen's text under a header holding a text button [back] (default «
    Retour ») that goes back: what is shown for a record no longer in the
    herbier, or one that could not be read. *)
