(** Binding to [@capacitor/preferences] ([globalThis.herbier.preferences]):
    string key/value pairs in the default group (SharedPreferences on Android,
    localStorage on the web). *)

val get : key:string -> (string option, Cap_error.t) result Fut.t
(** [None] when the key is absent ([value: null]); [Error (Unexpected "value")]
    when the result has no [value] or it is neither null nor a string. *)

val set : key:string -> value:string -> (unit, Cap_error.t) result Fut.t

val remove : key:string -> (unit, Cap_error.t) result Fut.t
(** Removing an absent key succeeds. *)
