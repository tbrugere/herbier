(* Server_text: 4m's "Serveur en pause" row, derived from the engine's last
   cycle report, and the Supabase dashboard link. Report values built
   literally, as test/sync/test_cycle.ml's report_tests does. *)

module Server_text = Herbier_ui_model.Server_text
module Report = Herbier_sync_core.Cycle.Report
module Outcome = Herbier_sync_core.Cycle.Outcome
module Pull = Herbier_sync_core.Cycle.Pull
module Schedule = Herbier_sync_core.Cycle.Schedule

let started = Herbier_test_support.Value.time "2026-11-12T09:00:00Z"
let report cycle : Report.t = {trigger = Schedule.Resume; started; cycle}
let push_stopped stop = Report.Push_stopped ({pushed = 0; parked = 0}, stop)
let pushed outcome = Report.Pushed ({pushed = 0; parked = 0}, outcome)

(* ---------- paused ---------- *)

let paused_none () =
  Alcotest.(check bool) "no cycle yet" false (Server_text.paused None)

let paused_push_stopped () =
  Alcotest.(check bool)
    "push stopped on Paused" true
    (Server_text.paused (Some (report (push_stopped Outcome.Paused))));
  Alcotest.(check bool)
    "push stopped on another reason" false
    (Server_text.paused (Some (report (push_stopped (Outcome.Offline "x")))))

let paused_pull_stopped () =
  Alcotest.(check bool)
    "pull stopped on Paused" true
    (Server_text.paused (Some (report (pushed (Pull.Stopped Outcome.Paused)))));
  Alcotest.(check bool)
    "pull completed" false
    (Server_text.paused (Some (report (pushed (Pull.Done [])))))

let paused_held () =
  Alcotest.(check bool)
    "held, pull stopped on Paused" true
    (Server_text.paused
       (Some
          (report (Report.Held ("keep-alive: x", Pull.Stopped Outcome.Paused)))));
  Alcotest.(check bool)
    "held, pull completed" false
    (Server_text.paused
       (Some (report (Report.Held ("keep-alive: x", Pull.Done [])))))

let paused =
  [
    Alcotest.test_case "no cycle yet: false" `Quick paused_none;
    Alcotest.test_case
      "a push stopped on Paused is true, on anything else false" `Quick
      paused_push_stopped;
    Alcotest.test_case
      "a pushed cycle whose pull stopped on Paused is true, a completed pull \
       is false"
      `Quick paused_pull_stopped;
    Alcotest.test_case
      "a held push whose pull stopped on Paused is true, a completed pull is \
       false"
      `Quick paused_held;
  ]

(* ---------- fixed texts ---------- *)

let texts =
  [
    Alcotest.test_case "paused_title, paused_detail, dashboard_label" `Quick
      (fun () ->
        Alcotest.(check string)
          "title" "Serveur en pause" Server_text.paused_title;
        Alcotest.(check string)
          "detail"
          "Les modifications attendent sur le téléphone ; elles partiront \
           quand le serveur sera réactivé."
          Server_text.paused_detail;
        Alcotest.(check string)
          "dashboard label" "Ouvrir le tableau de bord ↗"
          Server_text.dashboard_label);
  ]

(* ---------- dashboard_url ---------- *)

let dashboard_url =
  let some = Alcotest.(option string) in
  [
    Alcotest.test_case "a hosted project's ref gives the dashboard url" `Quick
      (fun () ->
        Alcotest.check some "no trailing slash"
          (Some "https://supabase.com/dashboard/project/abcd1234")
          (Server_text.dashboard_url
             ~supabase_url:"https://abcd1234.supabase.co");
        Alcotest.check some "trailing slash"
          (Some "https://supabase.com/dashboard/project/abcd1234")
          (Server_text.dashboard_url
             ~supabase_url:"https://abcd1234.supabase.co/"));
    Alcotest.test_case
      "the local stack, blank, a path, another host, a malformed ref, \
       uppercase, a suffix past .supabase.co, two slashes: None"
      `Quick (fun () ->
        List.iter
          (fun url ->
            Alcotest.check some url None
              (Server_text.dashboard_url ~supabase_url:url))
          [
            "http://127.0.0.1:54321";
            "";
            "https://x.supabase.co/rest";
            "https://evil.com";
            "https://.supabase.co";
            "https://ab_cd.supabase.co";
            "http://abcd.supabase.co";
            "https://abcd.supabase.co.evil.com";
            "https://ABCD.supabase.co";
            "https://a.b.supabase.co";
            "https://abcd.supabase.co//";
          ]);
  ]

let server_text = paused @ texts @ dashboard_url
