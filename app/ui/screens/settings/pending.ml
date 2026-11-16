module Parked_entry = Herbier_ui_model.Parked_entry
open Brr
module Outbox = Herbier_store.Outbox
module Outcome = Herbier_sync_core.Cycle.Outcome
module Server_text = Herbier_ui_model.Server_text

let cls = Html.cls

let parked_rows = function
  | [] -> []
  | entries ->
      let entry (e : Outbox.entry) =
        let {Parked_entry.title; detail} =
          Parked_entry.describe ~table_name:e.table_name ~payload:e.payload
            ~last_error:(Option.value e.last_error ~default:"")
        in
        Row.v ~title ~detail ()
      in
      El.div
        ~at:[cls "settings__row"]
        [
          El.span
            ~at:[cls "settings__title"]
            [
              El.txt'
                (Printf.sprintf "Non synchronisé · %d" (List.length entries));
            ];
        ]
      :: List.map entry entries

(* Architecture §4: a 540 shows here, with the hosted project's dashboard
   (where it is restored); the local stack has none. *)
let paused_rows = function
  | false -> []
  | true ->
      let link =
        Option.map
          (fun url ->
            El.a
              ~at:
                [
                  cls "settings__link";
                  At.href (Jstr.v url);
                  At.v (Jstr.v "target") (Jstr.v "_blank");
                  At.v (Jstr.v "rel") (Jstr.v "noopener noreferrer");
                ]
              [El.txt' Server_text.dashboard_label])
          (Server_text.dashboard_url
             ~supabase_url:Herbier_sync.Backend.supabase_url)
      in
      [
        Row.v ?below:link ~title:Server_text.paused_title
          ~detail:Server_text.paused_detail ();
      ]

let card (paused, blocked, entries) =
  let blocked_row =
    match blocked with
    | Some stop ->
        [Row.v ~title:"Réception bloquée" ~detail:(Outcome.to_string stop) ()]
    | None -> []
  in
  match paused_rows paused @ blocked_row @ parked_rows entries with
  | [] -> (El.div ~at:[cls "is-hidden"] [], [])
  | rows -> (El.div ~at:[cls "settings__card"] rows, [])

let pull_blocked engine =
  Option.bind (Herbier_sync.Engine.last engine) (fun report ->
      Option.bind (Herbier_sync_core.Cycle.Report.pull_stop report) (fun stop ->
          match Outcome.persistent stop with true -> Some stop | false -> None))

let unreadable () =
  ( El.div
      ~at:[cls "settings__card"]
      [
        Row.v ~title:"File d'envoi illisible"
          ~detail:"Les envois en attente n'ont pas pu être lus." ();
      ],
    [] )

let v app =
  let el = El.div ~at:[cls "settings__parked"] [] in
  let bindings =
    Loaded.v ~reload:(App.synced app) ~failed:unreadable
      ~what:"réglages: file d'envoi" el
      (fun () ->
        Fut.map
          (Result.map (fun entries ->
               let engine = App.engine app in
               ( Server_text.paused (Herbier_sync.Engine.last engine),
                 pull_blocked engine,
                 entries )))
          (Herbier_store_io.Db.all (App.db app) Outbox.parked))
      card
  in
  (el, bindings)
