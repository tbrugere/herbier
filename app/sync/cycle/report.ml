type cycle =
  | Push_stopped of Push.report * Outcome.stop
  | Pushed of Push.report * Pull.t

type t = {trigger : Schedule.trigger; started : Ptime.t; cycle : cycle}

let stop r =
  match r.cycle with
  | Push_stopped (_, s) | Pushed (_, Stopped s) -> Some s
  | Pushed (_, Done _) -> None

let pull_stop r =
  match r.cycle with
  | Pushed (_, Stopped s) -> Some s
  | Pushed (_, Done _) | Push_stopped _ -> None

let pulled_writes r =
  match r.cycle with
  | Pushed (_, Done tables) -> Pull.writes tables > 0
  | Pushed (_, Stopped _) | Push_stopped _ -> false

let push_line ({pushed; parked} : Push.report) =
  Printf.sprintf "pushed %d, parked %d" pushed parked

let table_line (r : Pull.table_report) =
  Printf.sprintf "%s %d (+%d ~%d =%d kept %d%s)" r.table r.fetched r.inserted
    r.replaced r.unchanged r.kept_local
    (match r.repeated with true -> ", repeated" | false -> "")

let lines r =
  let push = match r.cycle with Push_stopped (p, _) | Pushed (p, _) -> p in
  List.concat
    [
      [Schedule.trigger_to_string r.trigger; push_line push];
      (match r.cycle with
      | Pushed (_, Done tables) ->
          ["pulled " ^ String.concat ", " (List.map table_line tables)]
      | Pushed (_, Stopped _) | Push_stopped _ -> []);
      (match stop r with
      | Some s -> ["stopped: " ^ Outcome.to_string s]
      | None -> []);
    ]

let to_string r = String.concat "; " (lines r)
