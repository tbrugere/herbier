(** Errors of the Capacitor plugin bindings. Binding-level only: no domain
    meaning; callers map them to their own error type. *)

type t =
  | Unavailable of string
      (** [globalThis.herbier.<name>] is missing (vendor.js not loaded or the
          key not exported); carries [<name>], e.g. ["sqlite"]. *)
  | Rejected of {code : string option; message : string}
      (** The plugin call threw or its promise rejected. [code] is the error's
          string [code] property when it has one (Capacitor's ["UNIMPLEMENTED"]
          / ["UNAVAILABLE"], filesystem's ["OS-PLUG-FILE-XXXX"]); [message] is
          its [message] property, or the rejection itself when the plugin
          rejected with a bare string (the sqlite wrapper does:
          ["Connection herbier does not exist"]), or [String(value)] for
          anything else. Never interpreted. *)
  | Unexpected of string
      (** The promise resolved to a value without a field the plugin documents,
          or with it at the wrong type or out of range; carries the field path,
          e.g. ["changes.changes"], ["values"], ["uri"], ["data"]. *)
  | Invalid_path of string
      (** A {!Cap_filesystem} path that could leave [Directory.Data]; carries
          the path. The plugin is not called. *)

val to_string : t -> string
(** One line for logs and the dev page; includes [code] when present. *)
