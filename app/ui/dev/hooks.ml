(* style: module-level, as Geocoder's queue: the requests started since
   [install], newest first. *)
let started : Herbier_geo.Geocode.request list ref = ref []
let geocode_requests () = List.rev !started

(* style: module-level, as [started]: the transitions run since [install],
   newest first. *)
let transitions : Transition.record list ref = ref []

(* style: module-level, as [transitions]: the system-bar value last applied,
   [None] before the first. *)
let system_bars : Herbier_ui_model.System_bars.t option ref = ref None

let surface_name = function
  | Herbier_ui_model.System_bars.Light -> "light"
  | Dark -> "dark"

let install () =
  Herbier_bindings.Dev_hook.export_int "live" Rb.live;
  Herbier_geo_io.Geocoder.observe (fun r -> started := r :: !started);
  Herbier_bindings.Dev_hook.export_strings "geocodeRequests" (fun () ->
      List.map Herbier_geo.Geocode.request_to_string (geocode_requests ()));
  Transition.observe (fun r -> transitions := r :: !transitions);
  Herbier_bindings.Dev_hook.export_strings "transitions" (fun () ->
      List.rev_map Transition.record_to_string !transitions);
  System_bars.observe (fun t -> system_bars := Some t);
  Herbier_bindings.Dev_hook.export_strings "systemBars" (fun () ->
      match !system_bars with
      | None -> []
      | Some {status; navigation} ->
          [
            "status:" ^ surface_name status;
            "navigation:" ^ surface_name navigation;
          ])

module France_packs = Herbier_geo.France_packs
module Code = Herbier_geo.Communes.Code

let france_log line = Brr.Console.(log [str ("france: " ^ line)])

(* [codes]: comma-separated, spaces ignored; [""] is the whole list. *)
let only_of_string codes =
  match String.trim codes with
  | "" -> None
  | codes ->
      Some
        (List.filter_map
           (fun c ->
             match String.trim c with
             | "" -> None
             | c -> (
                 match Code.of_string c with
                 | Some code -> Some code
                 | None ->
                     Brr.Console.(error [str ("downloadFrance: bad code " ^ c)]);
                     None))
           (String.split_on_char ',' codes))

let progress_string (p : App.pack_error France_packs.progress) =
  Printf.sprintf "%d/%d" (France_packs.position p) p.plan.total

let france_state : App.france -> string = function
  | France_idle -> "idle"
  | France_deleting -> "deleting"
  | France_starting -> "starting"
  | France_running {step = Downloading (p, d); cancelling} ->
      Printf.sprintf "running %s %d %s%s" (progress_string p) p.bytes d.name
        (match cancelling with true -> " cancelling" | false -> "")
  | France_running {step = Retrying {attempt; attempts; wait_ms; _}; cancelling}
    ->
      Printf.sprintf "retrying %d/%d %d%s" attempt attempts wait_ms
        (match cancelling with true -> " cancelling" | false -> "")
  | France_finished (Complete p) ->
      Printf.sprintf "complete %d %d failed=%s" p.downloaded p.bytes
        (String.concat ","
           (List.map
              (fun ((d : Herbier_geo.Communes.departement), (_ : App.pack_error))
                 -> Code.to_string d.code)
              p.failed))
  | France_finished (Cancelled p) -> "cancelled " ^ progress_string p
  | France_finished (Stopped (p, e)) ->
      Printf.sprintf "stopped %s %s" (progress_string p)
        (App.pack_error_to_string e)

let install_france app =
  Herbier_bindings.Dev_hook.export_action "downloadFrance" (fun codes ->
      let open Fut.Result_syntax in
      Fut.await
        (let* plan = App.france_plan ?only:(only_of_string codes) app in
         App.download_france app plan)
        (function
          | Ok o -> france_log (france_state (France_finished o))
          | Error e -> france_log ("error " ^ App.pack_error_to_string e)));
  Herbier_bindings.Dev_hook.export_action "cancelFrance" (fun (_ : string) ->
      App.cancel_france app);
  Herbier_bindings.Dev_hook.export_strings "franceState" (fun () ->
      [france_state (React.S.value (App.france app))]);
  Herbier_bindings.Dev_hook.export_strings "packSizes" (fun () ->
      List.map
        (fun (p : App.pack) ->
          Printf.sprintf "%s %d" (Code.to_string p.code) p.row.size_bytes)
        (React.S.value (App.packs app)))

let install_app app =
  install_france app;
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
