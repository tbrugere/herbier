(** Navigation. The route is the URL fragment ({!Route}), so the Android back
    button and a reload land where expected; a route change builds the new
    screen and releases the old one (primer §6: navigation is the one dynamic
    part of the graph). Tabs are shown in a shell whose tab bar survives tab
    switches; modals and dev pages are shown alone.

    Dev pages ([#dev/<name>]) are routes too; the router holds none and resolves
    them through [dev]. *)

val start :
  root:Brr.El.t ->
  tab:(Widgets.Tab_bar.tab -> Screen.t) ->
  modal:(Route.modal -> Screen.t) ->
  dev:(string -> (unit -> Screen.t) option) ->
  unit
(** Shows the route of the current fragment in [root] and follows [hashchange]
    from then on. A [Dev] route that [dev] does not know shows Collection, and
    the URL is rewritten in place to the fragment of what is shown
    ([#collection] for [""] and unknown fragments). [tab] and [modal] build a
    screen each time it is entered; staying on the same route builds nothing. A
    screen that raises is shown as an error message, logged to the console.

    A tab press replaces the current history entry, so Android back leaves the
    app from any tab instead of walking the tabs visited. [start] registers the
    [backButton] listener that does so: back goes back in the WebView history
    when it can and exits the app otherwise. Leaving a dev page reloads the page
    on the new fragment, since dev pages do not hand their bindings to the
    router.

    A route change runs through {!Transition.run} with
    [Herbier_ui_model.Motion.kind ~from ~to_ direction]: [from] is the place of
    the route last asked for (the one shown, or the one a transition still about
    to show), [to_] that of the new one ([Tab Collection] → [Collection], any
    other tab → [Tab], [Modal (Plant id)] → [Fiche id], any other modal →
    [Modal], [Dev _] → [Dev]), and [direction] compares the Navigation API's
    history index at the previous change (at [start] for the first) with the
    current one. A transition's update shows the route last asked for when it
    runs, so a late one cannot bring back an older route. A change to the route
    last asked for runs nothing; the first screen is shown without a transition.
    The new screen is built, mounted and the old one released by the
    transition's commit (inside the View Transition's update when one runs),
    outside any update step. *)
