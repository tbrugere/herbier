(** Keeps Android's system-bar icons readable: dark on paper, light on 4d, 5e,
    6d and under the offline strip. The window starts LIGHT
    (capacitor.config.ts' [SystemBars.style], the app theme's
    [windowLightStatusBar]); this follows the app from there. *)

val surface_of_route : Route.t -> Herbier_ui_model.System_bars.surface
(** [Modal Record] (4d) and [Modal (Viewer _)] (5e) are [Dark]; every other
    route (tabs, other modals, [Dev _]) is [Light]. *)

val start :
  route:Route.t React.signal -> offline_banner:bool React.signal -> unit
(** Once, in main.ml after {!Router.start} (and after {!Offline_banner.mount}
    when the app started). Applies
    [System_bars.resolve ~route:(surface_of_route r) ~overlays ~offline_banner]
    ([overlays] from {!Overlay.surfaces}) now, at each change of [route] or
    [offline_banner] and at each {!Overlay.on_change}, sending only
    [System_bars.changes] through {!Herbier_bindings.Cap_system_bars.set_style}
    ([Light] → [Light], [Dark] → [Dark]). Each apply recomputes from the current
    values, so the last one wins whatever order a route change and an overlay's
    removal arrive in. A failed call is logged with {!Log.error}
    [~scope:"system bars"], but for [Unavailable] (a browser, which has no
    system bars), and not retried; the applied value is still recorded (no
    loop). Holds its bindings for the app's lifetime. Never raises. *)

val observe : (Herbier_ui_model.System_bars.t -> unit) -> unit
(** Dev builds: [f] is called with each value applied (dev hook
    [herbierDev.systemBars()]). One observer; a second call replaces it. As
    {!Transition.observe}. *)
