let plugin = "geolocation"

type position = {
  latitude : float;
  longitude : float;
  accuracy_m : float;
  timestamp_ms : float;
}

let position r =
  let open Result.Syntax in
  let* latitude = Cap_call.float_field r "coords.latitude" in
  let* longitude = Cap_call.float_field r "coords.longitude" in
  let* accuracy_m = Cap_call.float_field r "coords.accuracy" in
  let+ timestamp_ms = Cap_call.float_field r "timestamp" in
  {latitude; longitude; accuracy_m; timestamp_ms}

let current_position ~high_accuracy ~timeout_ms ~maximum_age_ms =
  Cap_call.call plugin "getCurrentPosition"
    [|
      Jv.obj
        [|
          ("enableHighAccuracy", Jv.of_bool high_accuracy);
          ("timeout", Jv.of_int timeout_ms);
          ("maximumAge", Jv.of_int maximum_age_ms);
        |];
    |]
    ~ok:position
