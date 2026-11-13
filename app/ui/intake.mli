(** Links and shares from other apps (architecture §7): [appUrlOpen] (the
    manifest's VIEW filters) and [shareReceived] (its SEND text/plain) both open
    4j ({!Route.Intercepted} with [outside = true]). *)

val start : App.t -> unit
(** Registers both listeners once, for the app's lifetime; call it after
    {!Router.start}. Each event's text ({!Intercept.of_url},
    {!Intercept.of_share}) becomes the current route
    [Modal (Intercepted {text; outside = true})]: {!Route.replace} when the
    current route is the previous link's sheet, an [Intercepted] one or the 4i
    that took its place ({!fell_back}), so a second link replaces the first
    sheet; {!Route.go} otherwise. A [None] text (an empty share) is logged as
    [intake: empty share or link] and opens nothing. A listener that cannot be
    registered is logged ([intake: <listener> <Cap_error>]) and the other still
    works. The received text is never written to the console. Never raises.
    [App.t] is taken so that intake only runs in an app that started. *)

val fell_back : string -> unit
(** [fell_back q]: an outside 4j was replaced by 4i prefilled with [q]
    ({!Route.Search} [q]); the next link replaces that 4i rather than stacking
    above it. Forgotten when the next link arrives. *)

val last : unit -> string option
(** The last text received since start, for [#dev/link]. *)
