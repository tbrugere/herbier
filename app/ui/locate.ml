module Map_sheet = Herbier_ui_model.Map_sheet
module Cap_geolocation = Herbier_bindings.Cap_geolocation
module Cap_error = Herbier_bindings.Cap_error

let world : State.camera = {center = {lat = 0.; lon = 0.}; zoom = 1.}

let notice = function
  | Cap_error.Rejected {code; message = _} -> Map_sheet.position_failure code
  | Unavailable _ | Unexpected _ | Invalid_path _ ->
      Map_sheet.Position_unavailable

let current ~what =
  Fut.map
    (function
      | Ok {Cap_geolocation.latitude; longitude; _} ->
          Ok {Herbier_domain.Places.lat = latitude; lon = longitude}
      | Error e ->
          Brr.Console.(warn [str what; str (Cap_error.to_string e)]);
          Error (notice e))
    (Cap_geolocation.current_position ~high_accuracy:true ~timeout_ms:10_000
       ~maximum_age_ms:30_000)
