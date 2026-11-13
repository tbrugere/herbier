type cycle =
  | Push_stopped of Push.report * Outcome.stop
  | Pushed of Push.report * Pull.t
  | Held of string * Pull.t

type t = {trigger : Schedule.trigger; started : Ptime.t; cycle : cycle}

let stop r =
  match r.cycle with
  | Push_stopped (_, s) | Pushed (_, Stopped s) | Held (_, Stopped s) -> Some s
  | Held (why, Done _) -> Some (Outcome.Held why)
  | Pushed (_, Done _) -> None

let pull_stop r =
  match r.cycle with
  | Pushed (_, Stopped s) | Held (_, Stopped s) -> Some s
  | Pushed (_, Done _) | Held (_, Done _) | Push_stopped _ -> None

let pulled_writes r =
  match r.cycle with
  | Pushed (_, Done tables) | Held (_, Done tables) -> Pull.writes tables > 0
  | Pushed (_, Stopped _) | Held (_, Stopped _) | Push_stopped _ -> false

let push_line ({pushed; parked} : Push.report) =
  Printf.sprintf "pushed %d, parked %d" pushed parked

let table_line (r : Pull.table_report) =
  Printf.sprintf "%s %d (+%d ~%d =%d kept %d%s)" r.table r.fetched r.inserted
    r.replaced r.unchanged r.kept_local
    (match r.repeated with true -> ", repeated" | false -> "")

let lines r =
  let push =
    match r.cycle with
    | Push_stopped (p, _) | Pushed (p, _) -> push_line p
    | Held (why, _) -> Outcome.to_string (Held why)
  in
  (* A held cycle's push line already names the hold. *)
  let shown_stop =
    match r.cycle with
    | Push_stopped (_, s) -> Some s
    | Pushed _ | Held _ -> pull_stop r
  in
  List.concat
    [
      [Schedule.trigger_to_string r.trigger; push];
      (match r.cycle with
      | Pushed (_, Done tables) | Held (_, Done tables) ->
          ["pulled " ^ String.concat ", " (List.map table_line tables)]
      | Pushed (_, Stopped _) | Held (_, Stopped _) | Push_stopped _ -> []);
      (match shown_stop with
      | Some s -> ["stopped: " ^ Outcome.to_string s]
      | None -> []);
    ]

let to_string r = String.concat "; " (lines r)
