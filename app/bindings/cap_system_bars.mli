(** Binding to Capacitor's core SystemBars plugin
    ([globalThis.herbier.systemBars], exported by web/js/vendor.js from
    [@capacitor/core] on Android only). Android:
    [WindowInsetsControllerCompat]'s light status and navigation bar appearance.
    A browser has no system bars: vendor.js exports nothing there (the plugin's
    web implementation would reject every call). *)

(** Capacitor's [SystemBarsStyle] minus ["DEFAULT"] (which follows the phone's
    night mode: Herbier never asks for it). *)
type style =
  | Light  (** ["LIGHT"]: dark icons, for a light background *)
  | Dark  (** ["DARK"]: light icons, for a dark background *)

(** Capacitor's [SystemBarType]. *)
type bar =
  | Status_bar  (** ["StatusBar"] *)
  | Navigation_bar  (** ["NavigationBar"] *)

val set_style : bar:bar -> style:style -> (unit, Cap_error.t) result Fut.t
(** [setStyle({style; bar})] with exactly those two string fields.
    [Error (Unavailable "systemBars")] when the plugin is not exported (a
    browser); [Error (Rejected _)] when the call throws or rejects. Never
    raises. *)
