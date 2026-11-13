module Geo = Herbier_bindings.Cap_geolocation

let start ~on_error () =
  let gps, set_gps = React.S.create Gps.Searching in
  Fut.await
    (Geo.current_position ~high_accuracy:true ~timeout_ms:20_000
       ~maximum_age_ms:30_000) (function
    | Ok p ->
        set_gps
          (Gps.Fix
             {
               lat = p.latitude;
               lon = p.longitude;
               accuracy_m = Some p.accuracy_m;
             })
    | Error e ->
        set_gps Gps.No_fix;
        on_error (Herbier_bindings.Cap_error.to_string e));
  gps
