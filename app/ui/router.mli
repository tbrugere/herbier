(** Navigation. The route is the URL fragment, so the Android back button and a
    reload land where expected; a route change builds the new screen and
    releases the old one (primer §6: navigation is the one dynamic part of the
    graph). The tab bar belongs to the shell and survives tab switches.

    Dev pages ([#dev/<name>]) are routes too; the router holds none and resolves
    them through [dev]. *)

type route = Tab of Widgets.Tab_bar.tab | Dev of string

val of_fragment : string -> route
(** [""], ["collection"] → [Tab Collection]; ["carte"], ["journal"],
    ["reglages"]; ["dev/<name>"] → [Dev name]. Anything else is
    [Tab Collection]. *)

val to_fragment : route -> string
(** Inverse of {!of_fragment} on its canonical forms ([Tab Collection] is
    ["collection"]). *)

val start :
  root:Brr.El.t ->
  tab:(Widgets.Tab_bar.tab -> Screen.t) ->
  dev:(string -> (unit -> Screen.t) option) ->
  unit
(** Shows the route of the current fragment in [root] and follows [hashchange]
    from then on. A [Dev] route that [dev] does not know shows Collection, and
    the URL is rewritten in place to the fragment of what is shown
    ([#collection] for [""] and unknown fragments). [tab] builds a tab's screen
    each time the tab is entered; staying on the same route builds nothing. A
    screen that raises is shown as an error message, logged to the console.

    A tab press replaces the current history entry, so Android back leaves the
    app from any tab instead of walking the tabs visited. [start] registers the
    [backButton] listener that does so: back goes back in the WebView history
    when it can and exits the app otherwise. Leaving a dev page reloads the page
    on the new fragment, since dev pages do not hand their bindings to the
    router. *)
