(** The dev pages this build can show, by route name ([#dev/<name>]). Copied by
    [app/dune] from [dev_pages.dev.ml] in every profile but [release], and from
    [dev_pages.release.ml] (no page) in the release profile, so a release build
    links none of [Herbier_ui.Dev]. *)

val find : string -> (unit -> Herbier_ui.Screen.t) option
