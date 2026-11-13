open Brr
module K = Herbier_sync.Keepalive
module Report = Herbier_sync_core.Keepalive.Report
module Wire = Herbier_sync_core.Keepalive.Wire
module Gotrue = Herbier_sync_core.Auth.Gotrue

let lines_of el lines =
  El.set_children el (List.map (fun l -> El.div [El.txt' l]) lines)

(* The other errors already name their event. *)
let error_line label = function
  | K.No_runner as e -> label ^ ": " ^ K.error_to_string e
  | (Rejected _ | Timed_out _ | Bad_answer _) as e -> K.error_to_string e

let iso t = Ptime.to_rfc3339 ~tz_offset_s:0 t

let report_lines (r : Report.t) =
  List.concat
    [
      [
        (match r.session_expires_at with
        | None -> "session: none"
        | Some at -> "session: expires " ^ iso at);
        Printf.sprintf "queued: %d" r.queued;
        Printf.sprintf "runs: %d" (List.length r.runs);
      ];
      List.map Report.run_to_string r.runs;
    ]

let page app =
  let keepalive = App.keepalive app in
  let config =
    El.div
      [
        El.txt'
          (Printf.sprintf "label %s, every %d min" Wire.label
             Wire.interval_minutes);
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
  let set = Kit.button "Session du job"
  and drop = Kit.button "Oublier la session"
  and hand_off = Kit.button "Confier la file"
  and reclaim = Kit.button "Reprendre la file"
  and run = Kit.button "Lancer maintenant"
  and update = Kit.button "Actualiser" in
  let done_ label fut =
    Fut.await fut (function
      | Ok () ->
          Kit.append log (label ^ ": ok");
          refresh ()
      | Error e -> Kit.append log (error_line label e))
  in
  Kit.on_click set (fun () ->
      let text = Jstr.to_string (El.prop El.Prop.value session) in
      El.set_prop El.Prop.value Jstr.empty session;
      match
        Gotrue.decode_session ~now:(Ptime_clock.now ()) ~status:200 text
      with
      | Error e -> Kit.append log ("session: " ^ Gotrue.error_to_string e)
      | Ok s -> done_ "session" (K.set_session keepalive s));
  Kit.on_click drop (fun () -> done_ "forget" (K.drop_session keepalive));
  Kit.on_click hand_off (fun () ->
      Fut.await (K.hand_off keepalive) (fun () ->
          Kit.append log "hand off: done";
          refresh ()));
  Kit.on_click reclaim (fun () -> done_ "reclaim" (K.reclaim keepalive));
  Kit.on_click run (fun () ->
      Kit.append log "run: started";
      Fut.await (K.run_now keepalive) (fun r ->
          (match r with
          | Ok _ -> Kit.append log "run: ok"
          | Error e -> Kit.append log (error_line "run" e));
          show r));
  Kit.on_click update refresh;
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
  Fut.await (render ()) (fun () -> Kit.append log "done");
  el

let el = function
  | Error e -> El.p [El.txt' ("no app: " ^ e)]
  | Ok app -> page app
