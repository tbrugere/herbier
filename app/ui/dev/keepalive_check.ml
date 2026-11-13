open Brr
module K = Herbier_sync.Keepalive

let append log text = El.append_children log [El.div [El.txt' text]]
let button label = El.button ~at:[At.type' (Jstr.v "button")] [El.txt' label]

let on_click el f =
  ignore (Ev.listen Ev.click (fun _ -> f ()) (El.as_target el) : Ev.listener)

let lines_of el lines =
  El.set_children el (List.map (fun l -> El.div [El.txt' l]) lines)

(* The other errors already name their event. *)
let error_line label = function
  | K.No_runner as e -> label ^ ": " ^ K.error_to_string e
  | (Rejected _ | Timed_out _ | Bad_answer _) as e -> K.error_to_string e

let iso t = Ptime.to_rfc3339 ~tz_offset_s:0 t

let report_lines (r : K.Report.t) =
  List.concat
    [
      [
        (match r.session_expires_at with
        | None -> "session: none"
        | Some at -> "session: expires " ^ iso at);
        Printf.sprintf "queued: %d" r.queued;
        Printf.sprintf "runs: %d" (List.length r.runs);
      ];
      List.map K.Report.run_to_string r.runs;
    ]

let page app =
  let keepalive = App.keepalive app in
  let config =
    El.div
      [
        El.txt'
          (Printf.sprintf "label %s, every %d min" K.Wire.label
             K.Wire.interval_minutes);
      ]
  in
  let report = El.div [] in
  let log = El.div ~at:[At.v (Jstr.v "role") (Jstr.v "log")] [] in
  let show = function
    | Ok r -> lines_of report (report_lines r)
    | Error e -> lines_of report [K.error_to_string e]
  in
  let render () = Fut.map show (K.report keepalive) in
  let refresh () = Fut.await (render ()) Fun.id in
  let session =
    El.input
      ~at:
        [
          At.type' (Jstr.v "password");
          At.v (Jstr.v "placeholder") (Jstr.v "session JSON");
          At.v (Jstr.v "aria-label") (Jstr.v "Session du job (JSON)");
        ]
      ()
  in
  let set = button "Session du job"
  and drop = button "Oublier la session"
  and hand_off = button "Confier la file"
  and reclaim = button "Reprendre la file"
  and run = button "Lancer maintenant"
  and update = button "Actualiser" in
  let done_ label fut =
    Fut.await fut (function
      | Ok () ->
          append log (label ^ ": ok");
          refresh ()
      | Error e -> append log (error_line label e))
  in
  on_click set (fun () ->
      let text = Jstr.to_string (El.prop El.Prop.value session) in
      El.set_prop El.Prop.value Jstr.empty session;
      match
        Herbier_sync.Auth.Gotrue.decode_session ~now:(Ptime_clock.now ())
          ~status:200 text
      with
      | Error e ->
          append log ("session: " ^ Herbier_sync.Auth.Gotrue.error_to_string e)
      | Ok s -> done_ "session" (K.set_session keepalive s));
  on_click drop (fun () -> done_ "forget" (K.drop_session keepalive));
  on_click hand_off (fun () ->
      Fut.await (K.hand_off keepalive) (fun () ->
          append log "hand off: done";
          refresh ()));
  on_click reclaim (fun () -> done_ "reclaim" (K.reclaim keepalive));
  on_click run (fun () ->
      append log "run: started";
      Fut.await (K.run_now keepalive) (fun r ->
          (match r with
          | Ok _ -> append log "run: ok"
          | Error e -> append log (error_line "run" e));
          show r));
  on_click update refresh;
  let el =
    El.div
      [
        El.h1 [El.txt' "Keep-alive check"];
        config;
        El.div [session; set];
        report;
        El.div [drop; hand_off; reclaim; run; update];
        log;
      ]
  in
  Fut.await (render ()) (fun () -> append log "done");
  el

let el = function
  | Error e -> El.p [El.txt' ("no app: " ^ e)]
  | Ok app -> page app
