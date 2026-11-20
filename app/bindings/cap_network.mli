(** Binding to [@capacitor/network] ([globalThis.herbier.network]): the current
    connection (Android's ConnectivityManager; the web implementation reads
    [navigator]). *)

(** [connectionType]: ["wifi"], ["cellular"], ["none"], ["unknown"]; any other
    string → [Unknown]. *)
type connection = Wifi | Cellular | No_connection | Unknown

type status = {connected : bool; connection : connection}

val status : unit -> (status, Cap_error.t) result Fut.t
(** [Network.getStatus()]. Plugin missing → [Error (Unavailable "network")]; a
    result without a boolean [connected] → [Error (Unexpected "connected")]; a
    missing or non-string [connectionType] → [connection = Unknown]. Never
    raises. *)
