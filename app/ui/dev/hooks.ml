(* style: module-level, as Geocoder's queue: the requests started since
   [install], newest first. *)
let started : Herbier_geo.Geocode.request list ref = ref []
let geocode_requests () = List.rev !started

(* style: module-level, as [started]: the transitions run since [install],
   newest first. *)
let transitions : Transition.record list ref = ref []

let install () =
  Herbier_bindings.Dev_hook.export_int "live" Rb.live;
  Herbier_geo_io.Geocoder.observe (fun r -> started := r :: !started);
  Herbier_bindings.Dev_hook.export_strings "geocodeRequests" (fun () ->
      List.map Herbier_geo.Geocode.request_to_string (geocode_requests ()));
  Transition.observe (fun r -> transitions := r :: !transitions);
  Herbier_bindings.Dev_hook.export_strings "transitions" (fun () ->
      List.rev_map Transition.record_to_string !transitions)

let install_app app =
  Herbier_bindings.Dev_hook.export_action "markOriginal" (fun arg ->
      let mark =
        match arg with
        | "uploaded" -> Some Drive_check.Uploaded
        | "original_missing" -> Some Drive_check.Missing
        | _ -> None
      in
      match mark with
      | None -> Brr.Console.(error [str ("markOriginal: unknown state " ^ arg)])
      | Some m ->
          Fut.await (Drive_check.mark_original app m) (function
            | Ok line -> Brr.Console.(log [str ("markOriginal: " ^ line)])
            | Error e -> Brr.Console.(error [str ("markOriginal: " ^ e)])))
