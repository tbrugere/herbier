(** Binding to [@capacitor/background-runner]
    ([globalThis.herbier.backgroundRunner]): events sent to the runner script
    configured in capacitor.config.ts. Every event carries JSON text both ways,
    as the string field [json] of its details and of its result. *)

val dispatch_event :
  label:string ->
  event:string ->
  json:string option ->
  (string option, Cap_error.t) result Fut.t
(** [BackgroundRunner.dispatchEvent({label, event, details})], [details] being
    [{json}] ([{}] for [None]): runs the script's [event] handler in a fresh
    runner context. Resolves to the string field [json] of the value the handler
    passed to [resolve], [None] when it passed nothing or an object without it
    ([json] of another type → [Error (Unexpected "json")]). A handler that calls
    [reject], a runner not started (Android shuts it down when the activity
    stops, i.e. when the app goes to the background), a missing plugin
    ([Unavailable "backgroundRunner"], also in a browser, where vendor.js leaves
    it out) or a throw → [Error] as [Cap_call.call]. Never raises. *)
