open Brr
module Db = Herbier_store.Db
module Settings = Herbier_store.Settings
module Place_name = Herbier_geo.Place_name

type choice = Open_settings | Understood

let log_error what e =
  Console.(error [str ("notice: " ^ what); str (Db.error_to_string e)])

let body () =
  let p text = El.p ~at:[At.class' (Jstr.v "t-body")] [El.txt' text] in
  [
    p "Vous pouvez activer, dans Réglages › Noms de lieux :";
    El.ul
      ~at:[At.class' (Jstr.v "confirm__list"); At.class' (Jstr.v "t-body")]
      (List.map
         (fun src ->
           El.li
             [El.txt' (Place_name.label src ^ " : " ^ Place_name.detail src)])
         Place_name.order);
    p
      "Par défaut, toutes sont désactivées : un lieu sans nom s’affiche « Lieu \
       inconnu ». La carte télécharge son fond depuis OpenFreeMap pour la zone \
       affichée.";
  ]

let show app =
  let dialog =
    Widgets.Dialog.v ~title:"Vos positions restent sur le téléphone"
      ~text:
        "Herbier nomme vos observations avec vos propres lieux (ceux que vous \
         avez renommés), sans réseau."
      ~body:(body ())
      [
        (Widgets.Button.Primary, "Choisir dans Réglages", Open_settings);
        (Widgets.Button.Secondary, "Compris", Understood);
      ]
  in
  (* style: the bindings the choice releases, set once just below; the
     dialog lives outside every screen, so nothing else would release them. *)
  let held = ref [] in
  let close choice =
    El.remove dialog.el;
    Rb.release !held;
    Fut.await
      (Db.write (App.db app) (Settings.set Settings.Location_notice_seen true))
      (function Ok (_ : int) -> () | Error e -> log_error "write" e);
    match choice with
    | Open_settings -> Route.go (Route.Tab Widgets.Tab_bar.Settings)
    | Understood -> ()
  in
  held := Rb.act dialog.choice close :: dialog.bindings;
  Rb.hold dialog.el !held;
  El.append_children (Document.body G.document) [dialog.el];
  dialog.show ()

let show_once app =
  Fut.await
    (Db.find (App.db app) (Settings.get Settings.Location_notice_seen))
    (function
      | Ok (Some true) -> ()
      | Ok (None | Some false) | Error (Db.Decode _) -> show app
      | Error
          (( Db.Plugin _ | Db.Schema _ | Db.Migration _ | Db.Not_migrated _
           | Db.Unexpected_rows _ | Db.Raised _ ) as e) ->
          log_error "read" e)
