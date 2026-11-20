module Pack_text = Herbier_ui_model.Pack_text
module Drive_text = Herbier_ui_model.Drive_text
open Brr
module Db = Herbier_store_io.Db
module Settings = Herbier_store.Settings
module Original_target = Herbier_domain.Photo.Original_target
module Place_name = Herbier_geo.Place_name
module W = Widgets

let cls = Html.cls
let log_error = Log.db ~scope:"réglages"

let section title children =
  El.section
    ~at:[cls "settings__section"]
    (El.h2 ~at:[cls "t-section-label"] [El.txt' title] :: children)

module Auth = Herbier_sync.Auth

(* The line under the account card after a failed sign-in; a dismissed
   chooser is not a failure, nor a tap replaced by a later one. *)
let sign_in_error : Auth.error -> string option = function
  | Cancelled | Replaced -> None
  | Not_allowed -> Some "Ce compte Google n'a pas accès à Herbier."
  | Network _ -> Some "Pas de connexion au serveur."
  | Google _ -> Some "La connexion Google a échoué."
  | Server _ -> Some "Le serveur a refusé la connexion."
  | Storage _ -> Some "Connexion non enregistrée sur le téléphone."
  | Not_configured | Crypto _ | No_session -> Some "La connexion a échoué."

(* The address's first character, whole even when it is not ASCII;
   upper-cased only when it is. *)
let initial = function
  | "" -> None
  | e ->
      let d = String.get_utf_8_uchar e 0 in
      let b = Buffer.create 4 in
      Buffer.add_utf_8_uchar b (Uchar.utf_decode_uchar d);
      Some (String.uppercase_ascii (Buffer.contents b))

type card = {
  avatar : string;
  title : string;
  meta : string;
  action : string option;
}
[@@deriving eq]

(* « Changer » signs in again (the account chooser); the current session
   stays until the new one is made. *)
let card ~running : Auth.status -> card = function
  | Unconfigured ->
      {
        avatar = "G";
        title = "Compte Google non connecté";
        meta = "Connexion indisponible dans cette version.";
        action = None;
      }
  | Restoring ->
      {avatar = "G"; title = "Compte Google"; meta = "…"; action = None}
  | Signed_out ->
      {
        avatar = "G";
        title = "Compte Google non connecté";
        meta = "Connectez-vous pour sauvegarder la collection.";
        action =
          Some
            (match running with
            | true -> "Connexion…"
            | false -> "Se connecter");
      }
  | Signed_in {email} ->
      {
        avatar = Option.value (Option.bind email initial) ~default:"G";
        title = "Compte Google connecté";
        meta = Drive_text.account_meta ~email;
        action =
          Some (match running with true -> "Connexion…" | false -> "Changer");
      }

let account_card app =
  let auth = App.auth app and state = App.state app in
  let running, set_running = React.S.create ~eq:Bool.equal false in
  let error, set_error = React.S.create ~eq:(Option.equal String.equal) None in
  let card =
    React.S.l2 ~eq:equal_card
      (fun (a : State.account) running -> card ~running a.auth)
      (State.account state) running
  in
  let avatar = El.span ~at:[cls "settings__avatar"] [] in
  let title = El.span ~at:[cls "settings__title"] [] in
  let meta = El.span ~at:[cls "t-meta"; cls "settings__email"] [] in
  let button = W.Button.text "" in
  (* role=alert: read out when it appears, since nothing else changes where
     the user is looking when a sign-in fails. *)
  let error_el =
    El.p
      ~at:
        [
          cls "t-meta";
          cls "settings__error";
          At.v (Jstr.v "role") (Jstr.v "alert");
        ]
      []
  in
  let sign_in () =
    match React.S.value running with
    | true -> ()
    | false ->
        let step = React.Step.create () in
        set_running ~step true;
        set_error ~step None;
        React.Step.execute step;
        Fut.await (Auth.sign_in auth) (fun result ->
            let message =
              match result with
              | Ok () -> None
              | Error e ->
                  let message = sign_in_error e in
                  Option.iter
                    (fun (_ : string) ->
                      Log.error ~scope:"réglages" "sign-in"
                        (Auth.error_to_string e))
                    message;
                  message
            in
            let step = React.Step.create () in
            set_running ~step false;
            set_error ~step message;
            React.Step.execute step)
  in
  let el =
    El.div
      [
        W.Card.panel
          [
            El.div
              ~at:[cls "settings__account"]
              [
                avatar;
                El.span ~at:[cls "settings__text"] [title; meta];
                button.el;
              ];
          ];
        error_el;
      ]
  in
  ( el,
    Rb.text avatar (React.S.map (fun c -> c.avatar) card)
    :: Rb.text title (React.S.map (fun c -> c.title) card)
    :: Rb.text meta (React.S.map (fun c -> c.meta) card)
    :: Rb.text button.el
         (React.S.map (fun c -> Option.value c.action ~default:"") card)
    :: Rb.class_ button.el "is-hidden"
         (React.S.map (fun c -> Option.is_none c.action) card)
    :: Rb.disabled button.el running
    :: Rb.text error_el (React.S.map (Option.value ~default:"") error)
    :: Rb.class_ error_el "is-hidden" (React.S.map Option.is_none error)
    :: Rb.act button.click sign_in
    :: button.bindings )

(* « IGN hors-ligne »: the downloaded packs and the département picker. *)

type picker =
  | Closed
  | Loading
  | List_failed of string
  | Choosing of Herbier_geo.Communes.departement list

let pack_row app ~locked ~deleting ~set_deleting ~set_message (p : App.pack) =
  let remove = W.Button.text ~tone:`Danger "Supprimer" in
  let code = p.code in
  let busy =
    React.S.l2 ~eq:Bool.equal
      (fun deleting locked ->
        locked || List.exists (Herbier_geo.Communes.Code.equal code) deleting)
      deleting locked
  in
  let el =
    El.div
      ~at:[cls "settings__row"; cls "pack-row"]
      [
        El.span
          ~at:[cls "settings__text"]
          [
            El.span
              ~at:[cls "settings__title"]
              [
                El.txt'
                  (Pack_text.title ~code:p.row.departement ~name:p.row.name);
              ];
            El.span
              ~at:[cls "t-meta"]
              [
                El.txt'
                  (match p.usable with
                  | true ->
                      Pack_text.detail ~size_bytes:p.row.size_bytes
                        ~communes:p.row.communes
                  | false -> Pack_text.unreadable);
              ];
          ];
        remove.el;
      ]
  in
  let act () =
    match React.S.value busy with
    | true -> ()
    | false ->
        set_deleting (code :: React.S.value deleting);
        set_message None;
        Fut.await (App.delete_pack app code) (fun r ->
            set_deleting
              (List.filter
                 (fun c -> not (Herbier_geo.Communes.Code.equal c code))
                 (React.S.value deleting));
            match r with
            | Ok () -> ()
            | Error e -> set_message (Some (App.pack_error_to_string e)))
  in
  (el, Rb.disabled remove.el busy :: Rb.act remove.click act :: remove.bindings)

let picker_list_id = "pack-picker-list"

let ign_offline_block app =
  let state = App.state app in
  let on =
    React.S.map ~eq:Bool.equal
      (fun (s : Place_name.sources) -> s.ign_offline)
      (State.place_sources state)
  in
  let deleting, set_deleting =
    React.S.create ~eq:(List.equal Herbier_geo.Communes.Code.equal) []
  in
  let set_deleting l = set_deleting l in
  let message, set_message =
    React.S.create ~eq:(Option.equal String.equal) None
  in
  let set_message m = set_message m in
  let picker, set_picker = React.S.create ~eq:( == ) Closed in
  let set_picker p = set_picker p in
  (* style: the list fetched once per screen, kept for a reopened picker. *)
  let fetched = ref None in
  let packs_el = El.div ~at:[cls "packs"] [] in
  let france = France_block.v app ~set_message in
  let render (packs, on) =
    let rows =
      List.map
        (pack_row app ~locked:france.locked ~deleting ~set_deleting ~set_message)
        packs
    in
    let none =
      match (packs, on) with
      | [], true ->
          [
            El.p
              ~at:[cls "t-meta"; cls "settings__intro"]
              [El.txt' Pack_text.no_pack];
          ]
      | [], false | _ :: _, _ -> []
    in
    ( El.div ~at:[cls "packs__list"] (List.map fst rows @ none),
      List.concat_map snd rows )
  in
  let add = W.Button.text "Ajouter un département" in
  (* App-wide, so a screen opened again during a download or a « Toute la
     France » run still says so. *)
  let downloading = france.busy in
  let field =
    W.Text_field.v ~icon:W.Icon.Search ~placeholder:"Département" ()
  in
  let choosing departements =
    set_picker (Choosing departements);
    El.set_has_focus true field.input
  in
  let open_picker () =
    match (React.S.value downloading, React.S.value picker) with
    | true, _ -> ()
    | false, (Loading | Choosing _ | List_failed _) -> set_picker Closed
    | false, Closed -> (
        set_message None;
        match !fetched with
        | Some departements -> choosing departements
        | None ->
            set_picker Loading;
            Fut.await (App.departements app) (function
              | Ok departements ->
                  fetched := Some departements;
                  choosing departements
              | Error e -> set_picker (List_failed (App.pack_error_to_string e)))
        )
  in
  (* The error goes to [message_el], outside the scrolled list: at the end of
     about a hundred rows it would be out of sight. *)
  let choose (d : Herbier_geo.Communes.departement) =
    set_message None;
    Fut.await (App.download_pack app d) (function
      | Ok () ->
          field.set "";
          set_picker Closed
      | Error e -> set_message (Some (App.pack_error_to_string e)))
  in
  let list_el =
    El.div ~at:[cls "pack-picker__list"; At.id (Jstr.v picker_list_id)] []
  in
  let render_picker (picker, query, packs, downloading) =
    let downloaded = List.map (fun (p : App.pack) -> p.code) packs in
    let line text =
      El.p ~at:[cls "t-meta"; cls "settings__intro"] [El.txt' text]
    in
    match (picker, downloading) with
    | _, true | Closed, false -> (El.div [], [])
    | Loading, false -> (El.div [line "Chargement…"], [])
    | List_failed text, false ->
        let retry = W.Button.text "Réessayer" in
        ( El.div [line text; El.div ~at:[cls "settings__row"] [retry.el]],
          Rb.act retry.click (fun () ->
              set_picker Closed;
              open_picker ())
          :: retry.bindings )
    | Choosing departements, false ->
        let shown =
          Herbier_geo.Communes.available ~downloaded departements
          |> List.filter (fun (d : Herbier_geo.Communes.departement) ->
              match String.trim query with
              | "" -> true
              | _ ->
                  Herbier_domain.Fold.matches ~query
                    (Herbier_geo.Communes.Code.to_string d.code ^ " " ^ d.name))
        in
        let rows =
          List.map
            (fun (d : Herbier_geo.Communes.departement) ->
              let row =
                W.List_row.v
                  ~title:
                    (Pack_text.title
                       ~code:(Herbier_geo.Communes.Code.to_string d.code)
                       ~name:d.name)
                  ~meta:"Télécharger ses communes" ()
              in
              (row.el, Rb.act row.click (fun () -> choose d) :: row.bindings))
            shown
        in
        (El.div (List.map fst rows), List.concat_map snd rows)
  in
  let field_shown =
    React.S.l2 ~eq:Bool.equal
      (fun picker downloading ->
        match (picker, downloading) with
        | Choosing _, false -> true
        | (Closed | Loading | List_failed _), _ | Choosing _, true -> false)
      picker downloading
  in
  let status_line () =
    El.p
      ~at:
        [
          cls "t-meta";
          cls "settings__intro";
          At.v (Jstr.v "role") (Jstr.v "status");
        ]
      []
  in
  let progress_el = status_line () in
  let message_el = status_line () in
  let shown_text el text =
    [
      Rb.text el (React.S.map (Option.value ~default:"") text);
      Rb.attr el "hidden"
        (React.S.map
           (function None -> Some "" | Some (_ : string) -> None)
           text);
    ]
  in
  (* During a run, its own progress line says it. *)
  let progress =
    React.S.l2
      ~eq:(Option.equal String.equal)
      (fun d running ->
        match running with
        | true -> None
        | false ->
            Option.map
              (fun (d : Herbier_geo.Communes.departement) ->
                Printf.sprintf "Téléchargement de %s…" d.name)
              d)
      (App.downloading app) france.running
  in
  let els =
    List.concat
      [
        france.summary;
        [
          packs_el;
          El.div
            ~at:[cls "settings__row"; cls "packs__actions"]
            [add.el; france.button];
          field.el;
          list_el;
        ];
        france.after;
        [
          progress_el;
          message_el;
          El.p
            ~at:[cls "t-meta"; cls "settings__intro"]
            [El.txt' Pack_text.attribution];
        ];
      ]
  in
  El.set_at (Jstr.v "aria-controls") (Some (Jstr.v picker_list_id)) add.el;
  let bindings =
    [
      Rb.view packs_el render
        (React.S.l2
           ~eq:(fun (a, b) (c, d) ->
             List.equal App.equal_pack a c && Bool.equal b d)
           (fun p o -> (p, o))
           (App.packs app) on);
      Rb.view list_el render_picker
        (React.S.l4 ~eq:( == )
           (fun p q packs d -> (p, q, packs, d))
           picker field.value (App.packs app) downloading);
      Rb.disabled add.el downloading;
      Rb.attr add.el "aria-expanded"
        (React.S.map
           (function
             | Closed -> Some "false"
             | Loading | Choosing _ | List_failed _ -> Some "true")
           picker);
      Rb.act add.click open_picker;
      Rb.attr field.el "hidden"
        (React.S.map (function true -> None | false -> Some "") field_shown);
    ]
    @ shown_text progress_el progress
    @ shown_text message_el message
    @ add.bindings
    @ field.bindings
    @ france.bindings
  in
  (els, bindings)

type stop_choice = Send_anyway | Dont_send | Keep_drive

(* 4m « File d'envoi »: the queue's title, why it waits, the last upload, and
   « Envoyer maintenant ». *)
let queue_block app =
  let state = App.state app in
  let queue = App.upload_queue app in
  let send = W.Button.text "Envoyer maintenant" in
  let title = El.span ~at:[cls "settings__title"] [] in
  let status =
    El.span
      ~at:
        [
          cls "t-meta";
          cls "settings__status";
          At.v (Jstr.v "role") (Jstr.v "status");
        ]
      []
  in
  let last = El.span ~at:[cls "t-meta"] [] in
  let status_text =
    React.S.l4
      ~eq:(Option.equal String.equal)
      (fun access (n : State.network) (a : State.account) q ->
        Drive_text.queue_status access ~online:n.online ~wifi_only:a.wifi_only q)
      (App.drive_access app) (State.network state) (State.account state) queue
  in
  (* [now] is read when the queue changes, in a DOM-side callback: a signal
     function must stay pure. *)
  let show_last (q : Drive_text.queue) =
    let now = Ptime_clock.now () in
    El.set_children last
      [
        El.txt'
          (Drive_text.last_sent ~now ~tz_offset_s:(Zone.offset_s now)
             q.last_upload);
      ]
  in
  show_last (React.S.value queue);
  let enabled = React.S.map ~eq:Bool.equal Drive_text.send_enabled queue in
  let el =
    El.div
      ~at:[cls "settings__row"]
      [El.span ~at:[cls "settings__text"] [title; status; last]; send.el]
  in
  ( el,
    [
      Rb.text title (React.S.map Drive_text.queue_title queue);
      Rb.text status (React.S.map (Option.value ~default:"") status_text);
      Rb.class_ status "is-hidden" (React.S.map Option.is_none status_text);
      Rb.act (React.S.changes queue) show_last;
      Rb.attr send.el "aria-disabled"
        (React.S.map (function true -> None | false -> Some "true") enabled);
      Rb.act send.click (fun () ->
          match React.S.value enabled with
          | true -> App.send_now app
          | false -> ());
    ]
    @ send.bindings )

(* The dialog when « Dans Herbier seulement » is chosen while originals wait
   on this phone, built at the tap for the count then: an upload that ends
   while it is open neither replaces nor closes it. [send_anyway] and
   [dont_send] run the choice. *)
let stop_dialog ~send_anyway ~dont_send =
  let host = El.div [] in
  (* style: the open dialog's bindings, replaced at each tap and released with
     the screen: a DOM-side cache. *)
  let current = ref [] in
  let open_ n =
    Rb.release !current;
    let {Drive_text.title; text} = Drive_text.stop_dialog n in
    let d =
      W.Dialog.v ~title ~text
        [
          (W.Button.Primary, "Les envoyer quand même", Send_anyway);
          (W.Button.Danger, "Ne pas les envoyer", Dont_send);
          (W.Button.Secondary, "Annuler", Keep_drive);
        ]
    in
    El.set_children host [d.el];
    current :=
      Rb.act d.choice (function
        | Send_anyway -> send_anyway ()
        | Dont_send -> dont_send ()
        | Keep_drive -> ())
      :: d.bindings;
    d.show ()
  in
  (host, open_, Rb.on_release (fun () -> Rb.release !current))

let storage_not_saved = Herbier_ui_model.Settings_text.not_saved

let stop_failed =
  "Les photos en attente n’ont pas pu être retirées : rien n’a changé."

let v app =
  let state = App.state app in
  (* « · Drive » and « Autoriser » say what Play Services says now, without
     waiting for an upload; the answer comes in a future's callback. *)
  App.check_drive_access app;
  let parked, parked_b = Pending.v app in
  let storage =
    React.S.map ~eq:( = )
      (fun (a : State.account) -> a.storage)
      (State.account state)
  in
  let wifi =
    React.S.map ~eq:Bool.equal
      (fun (a : State.account) -> a.wifi_only)
      (State.account state)
  in
  let set_account f =
    State.set_account state (f (React.S.value (State.account state)))
  in
  let db = App.db app in
  (* Shown before the write, so a second tap while it runs flips it back. *)
  let toggle_wifi () =
    let next = not (React.S.value wifi) in
    set_account (fun a -> {a with wifi_only = next});
    Fut.await
      (Db.write db (Settings.set Settings.Wifi_only next))
      (function
        | Ok _ -> ()
        | Error e ->
            log_error "wifi" e;
            set_account (fun a -> {a with wifi_only = not next}))
  in
  let account, account_b = account_card app in
  let identification = Identification.v app in
  let folder =
    Folder_button.v app
      ~visible:
        (React.S.l2 ~eq:Bool.equal
           (fun (target : Original_target.t) q ->
             match target with
             | Drive -> true
             | App_only -> Drive_text.pending_count q > 0)
           storage (App.upload_queue app))
  in
  let local =
    Radio_row.v
      ~title:(React.S.const "Dans Herbier seulement")
      ~detail:
        (React.S.const "Compressées à 1600 px, sur le téléphone seulement.")
      (React.S.map
         (function Original_target.App_only -> true | Drive -> false)
         storage)
  in
  let compressed =
    W.Switch.v ~disabled:true ~label:"Copie compressée hors-ligne"
      ~detail:"Toujours gardée : c'est elle que l'app affiche."
      (React.S.const true) ()
  in
  let wifi_switch = W.Switch.v ~label:"Envoyer seulement en Wi-Fi" wifi () in
  let source_switches =
    List.map
      (fun src ->
        let on =
          React.S.map ~eq:Bool.equal
            (fun s -> Place_name.enabled s src)
            (State.place_sources state)
        in
        let switch =
          W.Switch.v ~label:(Place_name.label src)
            ~detail:(Place_name.detail src) on ()
        in
        ( src,
          switch,
          Rb.act switch.toggle (fun () ->
              App.set_place_source app src (not (React.S.value on))) ))
      Place_name.order
  in
  let offline_els, offline_bindings = ign_offline_block app in
  let source_error =
    El.p
      ~at:
        [
          cls "t-meta";
          cls "settings__intro";
          At.v (Jstr.v "role") (Jstr.v "status");
        ]
      []
  in
  let offline = Offline_row.v app in
  let queue_el, queue_b = queue_block app in
  let storage_error, set_storage_error =
    React.S.create ~eq:(Option.equal String.equal) None
  in
  let drive = Drive_radio.v app ~storage ~set_error:set_storage_error in
  (* The only storage this screen writes alone: Drive comes with a pick. *)
  let set_app_only () =
    Fut.await (App.set_storage app Original_target.App_only) (function
      | Ok () -> set_storage_error None
      | Error (_ : Db.error) -> set_storage_error (Some storage_not_saved))
  in
  (* The waiting photos first: when that fails nothing has changed, and when
     the setting then fails the radio still says Drive, which is true for the
     photos to come. *)
  let dont_send () =
    Fut.await (App.stop_drive_uploads app) (function
      | Ok () -> set_app_only ()
      | Error (_ : Db.error) -> set_storage_error (Some stop_failed))
  in
  let stop_el, open_stop, stop_b =
    stop_dialog ~send_anyway:set_app_only ~dont_send
  in
  let choose_app_only () =
    match Drive_text.pending_count (React.S.value (App.upload_queue app)) with
    | 0 -> set_app_only ()
    | n -> open_stop n
  in
  let storage_error_el =
    El.p
      ~at:
        [
          cls "t-meta";
          cls "settings__error";
          At.v (Jstr.v "role") (Jstr.v "alert");
        ]
      []
  in
  let el =
    El.div
      ~at:[cls "screen"; cls "settings"]
      [
        El.h1 ~at:[cls "t-screen-title"] [El.txt' "Réglages"];
        account;
        section Herbier_ui_model.Identify_settings.section_title
          identification.els;
        section "Où vont mes photos"
          [
            El.div
              ~at:
                [
                  cls "settings__card";
                  At.v (Jstr.v "role") (Jstr.v "radiogroup");
                ]
              [drive.radio; local.el];
            drive.status;
            storage_error_el;
            folder.el;
          ];
        section "Sur le téléphone"
          (El.div
             ~at:[cls "settings__card"]
             [compressed.el; wifi_switch.el; offline.row]
          :: offline.after);
        section "Noms de lieux"
          [
            El.div
              ~at:[cls "settings__card"]
              (El.p
                 ~at:[cls "t-meta"; cls "settings__intro"]
                 [
                   El.txt'
                     "Vos lieux renommés nomment d’abord les observations à \
                      moins de 500 m, sans réseau ; sinon les sources activées \
                      ci-dessous ; sinon « Lieu inconnu ».";
                 ]
               :: List.concat_map
                    (fun (src, (s : W.Switch.t), _) ->
                      match src with
                      | Place_name.Ign_offline -> s.el :: offline_els
                      | Place_name.(Ign_online | Photon_online) -> [s.el])
                    source_switches
              @ [source_error]);
          ];
        section "File d'envoi"
          [El.div ~at:[cls "settings__card"] [queue_el]; parked];
        stop_el;
      ]
  in
  {
    Screen.el;
    ready = Screen.now;
    bindings =
      List.concat
        [
          account_b;
          identification.bindings;
          parked_b;
          queue_b;
          [stop_b];
          drive.bindings;
          folder.bindings;
          local.bindings;
          [
            Rb.text storage_error_el
              (React.S.map (Option.value ~default:"") storage_error);
            Rb.class_ storage_error_el "is-hidden"
              (React.S.map Option.is_none storage_error);
            Rb.act local.click (fun () ->
                match React.S.value storage with
                | Original_target.App_only -> ()
                | Drive -> choose_app_only ());
            Rb.act wifi_switch.toggle toggle_wifi;
            Rb.text source_error
              (React.S.map (Option.value ~default:"") (App.place_error app));
            Rb.attr source_error "hidden"
              (React.S.map
                 (function None -> Some "" | Some (_ : string) -> None)
                 (App.place_error app));
          ];
          compressed.bindings;
          wifi_switch.bindings;
          List.concat_map
            (fun (_, (s : W.Switch.t), act) -> act :: s.bindings)
            source_switches;
          offline_bindings;
          offline.bindings;
        ];
  }

let drive_sheet = Drive_sheet.v
