open Brr
module Picker = Herbier_bindings.Google_picker
module Backend = Herbier_sync.Backend
module Auth = Herbier_sync.Auth

let dummy_app_id = "123456789012"
let dummy_token = "ya29.invalid"

let input ~type' ~label ~value =
  El.input
    ~at:
      [
        At.type' (Jstr.v type');
        At.value (Jstr.v value);
        At.v (Jstr.v "aria-label") (Jstr.v label);
        At.v (Jstr.v "autocomplete") (Jstr.v "off");
      ]
    ()

let value_of el = String.trim (Jstr.to_string (El.prop El.Prop.value el))

let outcome_detail = function
  | Picker.Picked {id = (_ : string); name; mime_type} ->
      Printf.sprintf "picked %s %d chars" mime_type (String.length name)
  | Picker.Cancelled -> "cancelled"

(* The Picker's iframe src carries the token in its query: only hosts. *)
let iframe_hosts () =
  El.find_by_tag_name (Jstr.v "iframe")
  |> List.map (fun el ->
      let src = El.prop (El.Prop.jstr (Jstr.v "src")) el in
      match Uri.of_jstr src with
      | Ok uri -> Jstr.to_string (Uri.host uri)
      | Error (_ : Jv.Error.t) ->
          Printf.sprintf "(not a URL: %d chars)" (Jstr.length src))

let page auth =
  let log = El.div ~at:[At.v (Jstr.v "role") (Jstr.v "log")] [] in
  let number = Backend.google_cloud_project_number in
  let app_id =
    input ~type':"text" ~label:"App id (essai)"
      ~value:(match number with "" -> dummy_app_id | n -> n)
  and key = input ~type':"password" ~label:"Clé API (essai)" ~value:"" in
  let config ~with_key =
    {
      Picker.app_id = value_of app_id;
      developer_key =
        (match with_key with
        | false -> None
        | true -> ( match value_of key with "" -> None | k -> Some k));
      origin = Herbier_bindings.Location.origin ();
    }
  in
  let open_picker label ~with_key token_fut =
    let open Fut.Syntax in
    Kit.append log
      (Printf.sprintf "%s: key %s" label
         (match (config ~with_key).developer_key with
         | None -> "none"
         | Some (_ : string) -> "set"));
    let (_ : G.timer_id) =
      G.set_timeout ~ms:3000 (fun () ->
          Kit.append log
            (label ^ ": iframes: " ^ String.concat ", " (iframe_hosts ())))
    in
    let ticket = Picker.ticket () in
    let picked =
      let* token = token_fut in
      match token with
      | Error m -> Fut.return (Error m)
      | Ok token ->
          Fut.map
            (Result.map_error Picker.error_to_string)
            (Picker.pick_folder
               ~on_action:(fun a -> Kit.append log (label ^ ": action " ^ a))
               ticket (config ~with_key) ~token)
    in
    Fut.await
      (Kit.step log label
         ~detail:(fun o -> Some (outcome_detail o))
         ~error:Fun.id picked)
      ignore
  in
  let dummy () = Fut.return (Ok dummy_token) in
  let drive () =
    match auth with
    | None -> Fut.return (Error "no app")
    | Some auth ->
        Fut.map
          (Result.map_error Auth.drive_error_to_string)
          (Auth.drive_token auth ~interactive:true)
  in
  let opener label source ~with_key =
    Kit.action label (fun () -> open_picker label ~with_key (source ()))
  in
  let load =
    Kit.action "Charger api.js" (fun () ->
        Fut.await
          (Kit.step log "load"
             ~detail:(fun () -> None)
             ~error:Picker.error_to_string (Picker.load ()))
          ignore)
  and close = Kit.action "Fermer" Picker.dismiss in
  let drive_buttons =
    match auth with
    | None -> []
    | Some (_ : Auth.t) ->
        [
          opener "Ouvrir (jeton Drive, sans clé)" drive ~with_key:false;
          opener "Ouvrir (jeton Drive, avec clé)" drive ~with_key:true;
        ]
  in
  El.div
    [
      El.h1 [El.txt' "Picker check"];
      El.p
        [
          El.txt'
            ("project number: "
            ^ match number with "" -> "non défini" | n -> n);
        ];
      El.div [app_id; key];
      El.div [load; close];
      El.div drive_buttons;
      El.div
        [
          opener "Ouvrir (jeton factice, sans clé)" dummy ~with_key:false;
          opener "Ouvrir (jeton factice, avec clé)" dummy ~with_key:true;
        ];
      log;
    ]

let el = function
  | Ok app -> page (Some (App.auth app))
  | Error e -> El.div [El.p [El.txt' ("no app: " ^ e)]; page None]
