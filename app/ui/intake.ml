module Intercept = Herbier_ui_model.Intercept
module Cap_app = Herbier_bindings.Cap_app
module Cap_share_target = Herbier_bindings.Cap_share_target

(* style: module-level because the listeners live as long as the app, and
   [#dev/link] reads what they last received; written by them only. *)
let received = ref None
let last () = !received

(* style: module-level: the 4i query that stands where the last outside 4j
   was, written by that 4j, read when the next link arrives. *)
let fallback = ref None
let fell_back q = fallback := Some q

let is_fallback q =
  match !fallback with Some f -> String.equal f q | None -> false

let open_sheet = function
  | None -> Brr.Console.(warn [str "intake: empty share or link"])
  | Some text -> (
      received := Some text;
      let route = Route.Modal (Route.Intercepted {text; outside = true}) in
      let replaces =
        match Route.current () with
        | Route.Modal (Route.Intercepted _) -> true
        | Route.Modal (Route.Search q) -> is_fallback q
        | Route.Tab _ | Route.Dev _
        | Route.Modal
            ( Route.Tags | Route.Manage_tags | Route.Plant _
            | Route.Edit_plant _ | Route.New_plant | Route.Observation _
            | Route.Change_species _ | Route.Identify _ | Route.Record
            | Route.Saved _ | Route.Viewer _ | Route.Link_species _
            | Route.Move_point _ ) ->
            false
      in
      fallback := None;
      match replaces with
      | true -> Route.replace route
      | false -> Route.go route)

let log = Log.cap ~scope:"intake"

let start (_ : App.t) =
  Fut.await
    (Cap_app.on_url_open (fun url -> open_sheet (Intercept.of_url url)))
    (function Ok _ -> () | Error e -> log "appUrlOpen" e);
  Fut.await
    (Cap_share_target.on_share_received (fun {title; texts} ->
         open_sheet (Intercept.of_share ~title ~texts)))
    (function Ok _ -> () | Error e -> log "shareReceived" e)
