(** 6d Comparer (architecture §12): a full-screen dark layer over 6c, opened
    only from a species tile or « +N » of 6c. Top: ✕ and « Proposition i / n ».
    My photo (its organ pill) above the species' images, a horizontal
    [scroll-snap] track of the current proposal's images in
    {!Herbier_ui_model.Identify.Compare.images}' order, each with « Pl@ntNet ·
    <organe> », « k / m » and its credit band
    ({!Herbier_identify.Proposal.credit}), [url.m] loaded only for the shown
    image and its neighbours ({!Herbier_ui_model.Identify.Compare.to_load})
    behind the striped loading state with « Pl@ntNet… » after 600 ms. Bottom:
    Latin name and author, {!Herbier_ui_model.Identify.Text.compare_names}, «
    Dans ma collection · <nom> » when [owned] gives one, the percent, and ‹ /
    the caller's action / ›. Sends no request to Pl@ntNet's API, writes nothing,
    downloads nothing (plain [<img>]); a failed image keeps the stripes and its
    credit, without « Pl@ntNet… » nor any error text, and is logged to the
    console with its URL. Registered with {!Overlay}: Android back closes it (6c
    stays). *)

type t

val open_ :
  host:Brr.El.t ->
  caller:Herbier_ui_model.Identify.Caller.t ->
  owned:
    (Herbier_identify.Plantnet.proposal ->
    Herbier_ui_model.Identify.Owned.t option)
    React.signal ->
  choose:(int -> unit) ->
  on_close:(unit -> unit) ->
  photos:(cls:string -> Brr.El.t option) list ->
  Herbier_ui_model.Identify.Compare.t ->
  t
(** Appends the layer to [host] (6c's root), focuses ✕, pushes it on {!Overlay},
    and, once laid out, scrolls the track to
    {!Herbier_ui_model.Identify.Compare.image_index} without animation.
    [photos]: my photos in photo order, each building its image with the given
    class once, at open ([None]: a striped frame), as many as the [mine] the
    value was opened with; the top photo is [photos] at
    {!Herbier_ui_model.Identify.Compare.mine_index} (the first when out of
    range), under « Ma photo · <organe> » of
    {!Herbier_ui_model.Identify.Compare.mine_organ}. Events: the track's
    [scroll] → [Shown (round (scrollLeft / width))] when the position changed; ‹
    › → [Previous] / [Next] (each [aria-disabled], keeping the focus, when
    [can_previous] / [can_next] is false, and then doing nothing), which
    re-render the track at position 0 and the bottom block. The action's label
    is {!Herbier_ui_model.Identify.Text.compare_action}
    [(Caller.action caller ~owned:(React.S.value owned p <> None))]; a tap calls
    [choose (Compare.index c)] then {!close} (6c's [choose] runs its own
    [Choose k]: the outcome is the caller's). ✕ and back → {!close}. [owned] is
    read per shown proposal, and again for the shown one when it changes (6c's
    collection read arriving while 6d is open). *)

val close : t -> unit
(** Idempotent: releases the bindings, removes the element, removes it from
    {!Overlay}, calls [on_close] once (where 6c gives the focus back to the tile
    that opened it). Sets no signal itself, so it may run inside 6c's release.
*)
