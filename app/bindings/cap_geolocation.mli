(** Binding to [@capacitor/geolocation] ([globalThis.herbier.geolocation]): the
    GPS fix of a new observation (handoff 4d). *)

type position = {
  latitude : float;  (** WGS84 degrees. *)
  longitude : float;  (** WGS84 degrees. *)
  accuracy_m : float;
      (** Accuracy radius in metres, as the plugin reports it (on Android the
          radius of 68 % confidence). *)
  timestamp_ms : float;  (** When the fix was taken, ms since the epoch. *)
}

val current_position :
  high_accuracy:bool ->
  timeout_ms:int ->
  maximum_age_ms:int ->
  (position, Cap_error.t) result Fut.t
(** [getCurrentPosition({enableHighAccuracy; timeout; maximumAge})]. No fix
    within [timeout_ms], location off or permission refused are
    [Error (Rejected _)] as the plugin reports them. A result without finite
    numeric [coords.latitude], [coords.longitude], [coords.accuracy] or
    [timestamp] is [Error (Unexpected <that path>)]. *)
