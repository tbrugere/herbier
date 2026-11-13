open Brr
module Outbox = Herbier_store.Outbox
module Outcome = Herbier_sync.Cycle.Outcome

let cls c = At.class' (Jstr.v c)

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

let card (blocked, entries) =
  let blocked_row =
    match blocked with
    | Some stop ->
        [Row.v ~title:"Réception bloquée" ~detail:(Outcome.to_string stop) ()]
    | None -> []
  in
  match blocked_row @ parked_rows entries with
  | [] -> (El.div ~at:[cls "is-hidden"] [], [])
  | rows -> (El.div ~at:[cls "settings__card"] rows, [])

let pull_blocked engine =
  Option.bind (Herbier_sync.Engine.last engine) (fun report ->
      Option.bind (Herbier_sync.Cycle.Report.pull_stop report) (fun stop ->
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
          (Result.map (fun entries -> (pull_blocked (App.engine app), entries)))
          (Herbier_store.Db.all (App.db app) Outbox.parked))
      card
  in
  (el, bindings)
