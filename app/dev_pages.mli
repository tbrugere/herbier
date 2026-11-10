(** The dev pages this build can show, by route name ([#dev/<name>]). Copied by
    [app/dune] from [dev_pages.dev.ml] in every profile but [release], and from
    [dev_pages.release.ml] (no page) in the release profile, so a release build
    links none of [Herbier_ui.Dev]. *)

val find :
  (Herbier_store.Db.t, string) result ->
  string ->
  (unit -> Herbier_ui.Screen.t) option
(** [find db name]: the pages that read or write [herbier] work over [db], the
    app's own handle (one open [Db.t] per database), or show its error. *)
