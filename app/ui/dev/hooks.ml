(* style: module-level, as Geocoder's queue: the requests started since
   [install], newest first. *)
let started : Herbier_geo.Geocode.request list ref = ref []
let geocode_requests () = List.rev !started

let install () =
  Herbier_bindings.Dev_hook.export_int "live" Rb.live;
  Herbier_geo.Geocoder.observe (fun r -> started := r :: !started);
  Herbier_bindings.Dev_hook.export_strings "geocodeRequests" (fun () ->
      List.map Herbier_geo.Geocode.request_to_string (geocode_requests ()))
