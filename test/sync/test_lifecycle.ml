(* Native checks of app/sync_core/auth/lifecycle.ml: each transition's next
   state and its actions, in the order Auth runs them. *)

module Lifecycle = Herbier_sync_core.Auth.Lifecycle
module Session = Herbier_sync_core.Auth.Session
module Gotrue = Herbier_sync_core.Auth.Gotrue

let time s =
  match Ptime.of_float_s s with Some t -> t | None -> failwith "time"

(* 2027-01-15T08:00:00Z *)
let now = time 1_800_000_000.

let session ?(email = Some "person@example.com") ?(token = "1") ~expires () =
  {
    Session.access_token = "AT-" ^ token;
    refresh_token = "RT-" ^ token;
    expires_at = time expires;
    user_id = "user-1";
    email;
  }

(* Due in an hour; due already. *)
let fresh = session ~expires:1_800_003_600. ()
let due = session ~token:"2" ~expires:1_800_000_060. ()

let action_to_string : Lifecycle.action -> string = function
  | Notify Unconfigured -> "Notify Unconfigured"
  | Notify Restoring -> "Notify Restoring"
  | Notify Signed_out -> "Notify Signed_out"
  | Notify (Signed_in {email}) ->
      "Notify Signed_in " ^ Option.value email ~default:"-"
  | Reschedule -> "Reschedule"
  | Retry_in span -> Printf.sprintf "Retry_in %.0f" (Ptime.Span.to_float_s span)
  | Stop_timer -> "Stop_timer"
  | Start_refresh -> "Start_refresh"
  | Log m -> "Log " ^ m
  | Warn m -> "Warn " ^ m
  | Console_error m -> "Console_error " ^ m
  | Logout_server s -> "Logout_server " ^ s.access_token
  | Job_dropped -> "Job_dropped"
  | Forget_stored {generation} -> Printf.sprintf "Forget_stored %d" generation

let action =
  Alcotest.testable
    (fun ppf a -> Format.pp_print_string ppf (action_to_string a))
    Lifecycle.equal_action

let status =
  Alcotest.testable
    (fun ppf s ->
      Format.pp_print_string ppf
        (match (s : Lifecycle.status) with
        | Unconfigured -> "Unconfigured"
        | Restoring -> "Restoring"
        | Signed_out -> "Signed_out"
        | Signed_in {email} -> "Signed_in " ^ Option.value email ~default:"-"))
    Lifecycle.equal_status

let actions name expected (_, got) =
  Alcotest.(check (list action)) name expected got

let expires_fresh = "expires 2027-01-15T09:00:00Z"
let started = Lifecycle.create ~configured:true

let signed_in s =
  fst
    (Lifecycle.restored started ~generation:0 (Ok (Some (Session.to_string s))))

let signed_out = fst (Lifecycle.restored started ~generation:0 (Ok None))

let revoking =
  Gotrue.Rejected
    {status = 400; code = Some "refresh_token_not_found"; message = "gone"}

let case name f = Alcotest.test_case name `Quick f

let create_tests =
  [
    case "configured: Restoring, in the foreground, no session" (fun () ->
        Alcotest.check status "status" Restoring (Lifecycle.status started);
        Alcotest.(check bool) "configured" true (Lifecycle.configured started);
        Alcotest.(check bool) "foreground" true (Lifecycle.foreground started);
        Alcotest.(check bool) "armed" false (Lifecycle.armed started));
    case "not configured: Unconfigured" (fun () ->
        let t = Lifecycle.create ~configured:false in
        Alcotest.check status "status" Unconfigured (Lifecycle.status t);
        Alcotest.(check bool) "configured" false (Lifecycle.configured t));
  ]

let restore_tests =
  [
    case "a stored session: Signed_in, then the log line" (fun () ->
        let r =
          Lifecycle.restored started ~generation:0
            (Ok (Some (Session.to_string fresh)))
        in
        actions "actions"
          [
            Notify (Signed_in {email = Some "person@example.com"});
            Log ("session restored, " ^ expires_fresh);
          ]
          r;
        Alcotest.(check bool) "armed" true (Lifecycle.armed (fst r)));
    case "nothing stored: Signed_out" (fun () ->
        actions "actions" [Notify Signed_out]
          (Lifecycle.restored started ~generation:0 (Ok None)));
    case "the read failed: the error line, then Signed_out" (fun () ->
        actions "actions"
          [Console_error "session not read: boom"; Notify Signed_out]
          (Lifecycle.restored started ~generation:0 (Error "boom")));
    case "unparseable: the warning, Signed_out, then the key forgotten"
      (fun () ->
        actions "actions"
          [
            Warn "stored session dropped: not JSON";
            Notify Signed_out;
            Forget_stored {generation = 0};
          ]
          (Lifecycle.restored started ~generation:0 (Ok (Some "{"))));
    case "stale read failure or unparseable value: nothing, nothing forgotten"
      (fun () ->
        let t, _ = Lifecycle.kept started fresh in
        actions "read failed" []
          (Lifecycle.restored t ~generation:0 (Error "boom"));
        actions "unparseable" []
          (Lifecycle.restored t ~generation:0 (Ok (Some "{"))));
    case "stale (a sign-in landed first): nothing changes" (fun () ->
        let t, _ = Lifecycle.kept started fresh in
        let r = Lifecycle.restored t ~generation:0 (Ok None) in
        actions "actions" [] r;
        Alcotest.check status "status"
          (Signed_in {email = Some "person@example.com"})
          (Lifecycle.status (fst r)));
  ]

let foreground_tests =
  [
    case "resume, not due: rescheduled" (fun () ->
        let t, _ = Lifecycle.paused (signed_in fresh) in
        let r = Lifecycle.resumed ~now t in
        actions "actions" [Reschedule] r;
        Alcotest.(check bool) "foreground" true (Lifecycle.foreground (fst r)));
    case "resume, due: refreshed" (fun () ->
        actions "actions" [Start_refresh]
          (Lifecycle.resumed ~now (signed_in due)));
    case "resume, signed out: nothing, but in the foreground" (fun () ->
        let t, _ = Lifecycle.paused signed_out in
        let r = Lifecycle.resumed ~now t in
        actions "actions" [] r;
        Alcotest.(check bool) "foreground" true (Lifecycle.foreground (fst r)));
    case "pause: timer stopped, then logged; not armed" (fun () ->
        let r = Lifecycle.paused (signed_in fresh) in
        actions "actions" [Stop_timer; Log "background, timer stopped"] r;
        Alcotest.(check bool) "armed" false (Lifecycle.armed (fst r)));
  ]

let refresh_tests =
  [
    case "refreshed: kept, logged, rescheduled; same status, no Notify"
      (fun () ->
        actions "actions"
          [Log ("refreshed, " ^ expires_fresh); Reschedule]
          (Lifecycle.refreshed (signed_in due) fresh ~not_stored:None));
    case "refreshed, not stored: the error line first" (fun () ->
        actions "actions"
          [
            Console_error "refreshed session not stored: full";
            Log ("refreshed, " ^ expires_fresh);
            Reschedule;
          ]
          (Lifecycle.refreshed (signed_in due) fresh ~not_stored:(Some "full")));
    case "refreshed with another email: Notify before the log line" (fun () ->
        let other = {fresh with email = None} in
        actions "actions"
          [
            Notify (Signed_in {email = None});
            Log ("refreshed, " ^ expires_fresh);
            Reschedule;
          ]
          (Lifecycle.refreshed (signed_in due) other ~not_stored:None));
    case "failed refreshes back off: 10 s, 20 s, then reset by a success"
      (fun () ->
        let t = signed_in due in
        let t, first = Lifecycle.refresh_failed t ~why:"network: down" in
        Alcotest.(check (list action))
          "first"
          [
            Warn "refresh failed (network: down), retry in 10 s";
            Retry_in (Ptime.Span.of_int_s 10);
          ]
          first;
        let t, second = Lifecycle.refresh_failed t ~why:"network: down" in
        Alcotest.(check (list action))
          "second"
          [
            Warn "refresh failed (network: down), retry in 20 s";
            Retry_in (Ptime.Span.of_int_s 20);
          ]
          second;
        let t, _ = Lifecycle.refreshed t fresh ~not_stored:None in
        actions "after a success"
          [
            Warn "refresh failed (network: down), retry in 10 s";
            Retry_in (Ptime.Span.of_int_s 10);
          ]
          (Lifecycle.refresh_failed t ~why:"network: down"));
    case "revoked: warned, Signed_out, rescheduled, job dropped; new generation"
      (fun () ->
        let t = signed_in due in
        let r = Lifecycle.revoked t revoking in
        actions "actions"
          [
            Warn ("session revoked: " ^ Gotrue.error_to_string revoking);
            Notify Signed_out;
            Reschedule;
            Job_dropped;
          ]
          r;
        Alcotest.(check bool)
          "older flights stale" true
          (Lifecycle.stale (fst r) ~generation:(Lifecycle.generation t)));
    case "revoked resets the failures" (fun () ->
        let t, _ = Lifecycle.refresh_failed (signed_in due) ~why:"x" in
        let t, _ = Lifecycle.revoked t revoking in
        let t, _ = Lifecycle.kept t fresh in
        actions "first failure again"
          [
            Warn "refresh failed (x), retry in 10 s";
            Retry_in (Ptime.Span.of_int_s 10);
          ]
          (Lifecycle.refresh_failed t ~why:"x"));
  ]

let sign_in_tests =
  [
    case "attempts: each start is the latest, an older one is not current"
      (fun () ->
        let t, first = Lifecycle.sign_in_started signed_out in
        let t, second = Lifecycle.sign_in_started t in
        Alcotest.(check bool) "first" false (Lifecycle.current t ~attempt:first);
        Alcotest.(check bool)
          "second" true
          (Lifecycle.current t ~attempt:second));
    case "kept, signed out before: Signed_in, rescheduled, logged" (fun () ->
        actions "actions"
          [
            Notify (Signed_in {email = Some "person@example.com"});
            Reschedule;
            Log ("signed in, " ^ expires_fresh);
          ]
          (Lifecycle.kept signed_out fresh));
    case "kept over a session: the previous one logged out last" (fun () ->
        let r = Lifecycle.kept (signed_in due) fresh in
        actions "actions"
          [Reschedule; Log ("signed in, " ^ expires_fresh); Logout_server due]
          r;
        Alcotest.(check bool)
          "a new generation" true
          (Lifecycle.stale (fst r) ~generation:0));
    case "kept while Restoring: Signed_in, rescheduled, logged" (fun () ->
        actions "actions"
          [
            Notify (Signed_in {email = Some "person@example.com"});
            Reschedule;
            Log ("signed in, " ^ expires_fresh);
          ]
          (Lifecycle.kept started fresh));
    case "kept does not move the attempt" (fun () ->
        let t, attempt = Lifecycle.sign_in_started signed_out in
        let t, _ = Lifecycle.kept t fresh in
        Alcotest.(check bool) "current" true (Lifecycle.current t ~attempt));
    case "signed out: Signed_out, rescheduled, logged, job dropped" (fun () ->
        let r = Lifecycle.signed_out (signed_in fresh) in
        actions "actions"
          [Notify Signed_out; Reschedule; Log "signed out"; Job_dropped]
          r;
        Alcotest.(check bool)
          "a new generation" true
          (Lifecycle.stale (fst r) ~generation:0));
  ]

let expire_tests =
  [
    case "expiry moved to now + 90 s + 30 s, logged, rescheduled" (fun () ->
        let r = Lifecycle.expiry_moved ~now (signed_in fresh) in
        actions "actions"
          [Log "expiry moved, expires 2027-01-15T08:02:00Z"; Reschedule]
          r;
        Alcotest.(check bool)
          "due in 30 s" true
          (Option.equal Ptime.equal
             (Option.map
                (fun (s : Session.t) -> s.expires_at)
                (Lifecycle.session (fst r)))
             (Some (time 1_800_000_120.))));
    case "signed out: nothing" (fun () ->
        actions "actions" [] (Lifecycle.expiry_moved ~now signed_out));
  ]

let moves_generation name (t, transition) expected =
  let next, _ = transition t in
  Alcotest.(check bool)
    name expected
    (Lifecycle.stale next ~generation:(Lifecycle.generation t))

let generation_tests =
  [
    case "only revoked, kept and signed_out replace the session" (fun () ->
        let t = signed_in due in
        List.iter
          (fun (name, transition) -> moves_generation name (t, transition) true)
          [
            ("revoked", fun t -> Lifecycle.revoked t revoking);
            ("kept", fun t -> Lifecycle.kept t fresh);
            ("signed_out", Lifecycle.signed_out);
          ];
        List.iter
          (fun (name, transition) ->
            moves_generation name (t, transition) false)
          [
            ("refreshed", fun t -> Lifecycle.refreshed t fresh ~not_stored:None);
            ( "refreshed, not stored",
              fun t -> Lifecycle.refreshed t fresh ~not_stored:(Some "full") );
            ("refresh_failed", fun t -> Lifecycle.refresh_failed t ~why:"x");
            ("expiry_moved", Lifecycle.expiry_moved ~now);
            ("resumed", Lifecycle.resumed ~now);
            ("paused", Lifecycle.paused);
            ("sign_in_started", fun t -> (fst (Lifecycle.sign_in_started t), []));
          ];
        List.iter
          (fun (name, stored) ->
            moves_generation name
              (started, fun t -> Lifecycle.restored t ~generation:0 stored)
              false)
          [
            ("restored", Ok (Some (Session.to_string fresh)));
            ("restored, nothing", Ok None);
            ("restored, unparseable", Ok (Some "{"));
            ("restored, read failed", Error "boom");
          ]);
  ]

(* The interleavings Auth relies on, as the machine sees them: a flight reads
   the generation (or the attempt) when it starts and checks it when it
   lands. *)
let race_tests =
  [
    case "sign-in during a refresh: the refresh lands stale" (fun () ->
        let t = signed_in due in
        let refresh_started = Lifecycle.generation t in
        let t, _ = Lifecycle.sign_in_started t in
        let t, _ = Lifecycle.kept t fresh in
        Alcotest.(check bool)
          "refresh stale" true
          (Lifecycle.stale t ~generation:refresh_started);
        Alcotest.check status "the sign-in's session stands"
          (Signed_in {email = Some "person@example.com"})
          (Lifecycle.status t));
    case "sign-out during a sign-in: the sign-in, still current, lands after"
      (fun () ->
        let t, attempt = Lifecycle.sign_in_started (signed_in due) in
        let t, _ = Lifecycle.signed_out t in
        Alcotest.(check bool)
          "attempt current" true
          (Lifecycle.current t ~attempt);
        let t, acts = Lifecycle.kept t fresh in
        Alcotest.(check (list action))
          "kept from Signed_out"
          [
            Notify (Signed_in {email = Some "person@example.com"});
            Reschedule;
            Log ("signed in, " ^ expires_fresh);
          ]
          acts;
        Alcotest.check status "signed in"
          (Signed_in {email = Some "person@example.com"})
          (Lifecycle.status t));
    case "sign-in during a sign-out: the sign-out lands stale" (fun () ->
        let t = signed_in due in
        let sign_out_started = Lifecycle.generation t in
        let t, _ = Lifecycle.sign_in_started t in
        let t, _ = Lifecycle.kept t fresh in
        Alcotest.(check bool)
          "sign-out stale" true
          (Lifecycle.stale t ~generation:sign_out_started));
    case "a newer sign-in: the older attempt is no longer current" (fun () ->
        let t, older = Lifecycle.sign_in_started signed_out in
        let t, newer = Lifecycle.sign_in_started t in
        let t, _ = Lifecycle.kept t fresh in
        Alcotest.(check bool) "older" false (Lifecycle.current t ~attempt:older);
        Alcotest.(check bool) "newer" true (Lifecycle.current t ~attempt:newer));
  ]

let () =
  Alcotest.run "lifecycle"
    [
      ("create", create_tests);
      ("restored", restore_tests);
      ("resumed and paused", foreground_tests);
      ("refresh", refresh_tests);
      ("sign-in and sign-out", sign_in_tests);
      ("expiry_moved", expire_tests);
      ("generation", generation_tests);
      ("races", race_tests);
    ]
