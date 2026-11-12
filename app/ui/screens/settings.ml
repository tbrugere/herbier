open Brr
module Db = Herbier_store.Db
module Settings = Herbier_store.Settings
module Original_target = Herbier_domain.Photo.Original_target
module Place_name = Herbier_geo.Place_name
module W = Widgets

let cls c = At.class' (Jstr.v c)

let log_error what e =
  Console.(error [str ("réglages: " ^ what); str (Db.error_to_string e)])

let section title children =
  El.section
    ~at:[cls "settings__section"]
    (El.h2 ~at:[cls "t-section-label"] [El.txt' title] :: children)

let radio ~title ~detail selected =
  let el =
    El.button
      ~at:
        [
          At.type' (Jstr.v "button");
          cls "radio-row";
          At.v (Jstr.v "role") (Jstr.v "radio");
        ]
      [
        El.span ~at:[cls "radio-row__dot"] [];
        El.span
          ~at:[cls "radio-row__text"]
          [
            El.span ~at:[cls "radio-row__title"] [El.txt' title];
            El.span ~at:[cls "t-meta"] [El.txt' detail];
          ];
      ]
  in
  let click, b = Rb.click el in
  ( el,
    click,
    [
      b;
      Rb.class_ el "radio-row--on" selected;
      Rb.attr el "aria-checked"
        (React.S.map (fun v -> Some (string_of_bool v)) selected);
    ] )

let v app =
  let db = App.db app and state = App.state app in
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
  let set_storage target =
    Fut.await
      (Db.write db (Settings.set Settings.Storage_target target))
      (function
        | Error e -> log_error "storage" e
        | Ok _ -> set_account (fun a -> {a with storage = target}))
  in
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
  let account =
    W.Card.panel
      [
        El.div
          ~at:[cls "settings__account"]
          [
            El.span ~at:[cls "settings__avatar"] [El.txt' "G"];
            El.span
              ~at:[cls "settings__text"]
              [
                El.span
                  ~at:[cls "settings__title"]
                  [El.txt' "Compte Google non connecté"];
                El.span
                  ~at:[cls "t-meta"]
                  [
                    El.txt'
                      "La connexion se fait à la première photo envoyée vers \
                       Drive.";
                  ];
              ];
          ];
      ]
  in
  let drive_el, drive_click, drive_b =
    radio ~title:"Google Drive · dossier “Herbier”"
      ~detail:"Un sous-dossier par espèce. Aperçus gardés sur le téléphone."
      (React.S.map
         (function Original_target.Drive -> true | App_only -> false)
         storage)
  in
  let local_el, local_click, local_b =
    radio ~title:"Dans Herbier seulement"
      ~detail:"Compressées à 1600 px, sur le téléphone seulement."
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
        ( switch,
          Rb.act switch.toggle (fun () ->
              App.set_place_source app src (not (React.S.value on))) ))
      Place_name.order
  in
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
  let free = W.Button.text "Libérer" in
  let send = W.Button.text "Envoyer maintenant" in
  El.set_at (Jstr.v "aria-disabled") (Some (Jstr.v "true")) free.el;
  El.set_at (Jstr.v "aria-disabled") (Some (Jstr.v "true")) send.el;
  let pending = El.span ~at:[cls "settings__title"] [] in
  let row children = El.div ~at:[cls "settings__row"] children in
  let el =
    El.div
      ~at:[cls "screen"; cls "settings"]
      [
        El.h1 ~at:[cls "t-screen-title"] [El.txt' "Réglages"];
        account;
        section "Où vont mes photos"
          [
            El.div
              ~at:
                [
                  cls "settings__card";
                  At.v (Jstr.v "role") (Jstr.v "radiogroup");
                ]
              [drive_el; local_el];
          ];
        section "Sur le téléphone"
          [
            El.div
              ~at:[cls "settings__card"]
              [
                compressed.el;
                wifi_switch.el;
                row
                  [
                    El.span
                      ~at:[cls "settings__text"]
                      [
                        El.span
                          ~at:[cls "settings__title"]
                          [El.txt' "Données hors-ligne"];
                        El.span
                          ~at:[cls "t-meta"]
                          [El.txt' "Aperçus photos · Fiches de référence"];
                      ];
                    free.el;
                  ];
              ];
          ];
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
               :: List.map (fun ((s : W.Switch.t), _) -> s.el) source_switches
              @ [source_error]);
          ];
        section "File d'envoi"
          [
            El.div
              ~at:[cls "settings__card"]
              [
                row
                  [
                    El.span
                      ~at:[cls "settings__text"]
                      [
                        pending;
                        El.span
                          ~at:[cls "t-meta"]
                          [El.txt' "Aucun envoi pour l'instant."];
                      ];
                    send.el;
                  ];
              ];
          ];
      ]
  in
  {
    Screen.el;
    bindings =
      List.concat
        [
          drive_b;
          local_b;
          [
            Rb.act drive_click (fun () -> set_storage Original_target.Drive);
            Rb.act local_click (fun () -> set_storage Original_target.App_only);
            Rb.act wifi_switch.toggle toggle_wifi;
            Rb.text source_error
              (React.S.map (Option.value ~default:"") (App.place_error app));
            Rb.attr source_error "hidden"
              (React.S.map
                 (function None -> Some "" | Some (_ : string) -> None)
                 (App.place_error app));
            Rb.text pending
              (React.S.map
                 (fun (n : State.network) ->
                   match n.pending_uploads with
                   | 0 -> "Aucune photo en attente"
                   | 1 -> "1 photo en attente"
                   | n -> Printf.sprintf "%d photos en attente" n)
                 (State.network state));
          ];
          compressed.bindings;
          wifi_switch.bindings;
          List.concat_map
            (fun ((s : W.Switch.t), act) -> act :: s.bindings)
            source_switches;
          free.bindings;
          send.bindings;
        ];
  }
