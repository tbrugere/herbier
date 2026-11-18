(* Herbier_ui_model.Identify (app/ui_model/identify/): Caller, Owned, Failure,
   Layer (the pure machine) and Text, for the identification layer (6b, 6c,
   6f, 6g; architecture §12). No DOM, no network: Layer.step and Layer.open_
   are driven directly; "sent" answers are built from the recorded Pl@ntNet
   fixtures (certain/uncertain) or small synthetic Plantnet.answer values for
   the padding/truncation and multi-photo rules the fixtures do not shape. *)

module Identify = Herbier_ui_model.Identify
module Caller = Identify.Caller
module Owned = Identify.Owned
module Failure = Identify.Failure
module Layer = Identify.Layer
module Text = Identify.Text
module Organ = Herbier_identify.Organ
module Plantnet = Herbier_identify.Plantnet
module Proposal = Herbier_identify.Proposal
module Settings = Herbier_store.Settings
module Plant = Herbier_domain.Plant
module Plant_id = Herbier_domain.Ids.Plant_id
module Is = Herbier_ui_model.Identify_settings
module Fixture = Herbier_test_support.Fixture
module Support_text = Herbier_test_support.Text

(* ---------- testables ---------- *)

let plant_id_t =
  Alcotest.testable
    (fun fmt id -> Format.pp_print_string fmt (Plant_id.to_string id))
    Plant_id.equal

let pp_caller fmt = function
  | Caller.Noter -> Format.pp_print_string fmt "Noter"
  | Caller.Queue {index; total} ->
      Format.fprintf fmt "Queue {index = %d; total = %d}" index total
  | Caller.Free_name id ->
      Format.fprintf fmt "Free_name %s" (Plant_id.to_string id)

let caller_t = Alcotest.testable pp_caller Caller.equal
let action_t = Alcotest.testable Caller.pp_action Caller.equal_action

let pp_owned fmt (o : Owned.t) =
  Format.fprintf fmt "{plant = %a; observations = %d}" Plant.pp o.plant
    o.observations

let owned_t = Alcotest.testable pp_owned Owned.equal
let owned_opt_t = Alcotest.option owned_t
let failure_t = Alcotest.testable Failure.pp Failure.equal

let pp_organ_sent fmt (o : Organ.sent) =
  Format.pp_print_string fmt (Organ.sent_to_string o)

let organ_sent_t = Alcotest.testable pp_organ_sent Organ.equal_sent
let organ_sent_list_t = Alcotest.list organ_sent_t

let pp_organ_opt fmt = function
  | None -> Format.pp_print_string fmt "none"
  | Some o -> Format.pp_print_string fmt (Organ.to_string o)

let organ_opt_t = Alcotest.testable pp_organ_opt (Option.equal Organ.equal)
let organ_opt_list_t = Alcotest.list organ_opt_t
let pp_suggestion fmt s = Format.pp_print_string fmt (Organ.suggestion_label s)

let suggestion_opt_t =
  Alcotest.option (Alcotest.testable pp_suggestion Organ.equal_suggestion)

let pp_outcome fmt = function
  | Layer.Left -> Format.pp_print_string fmt "Left"
  | Layer.Chosen (p : Plantnet.proposal) ->
      Format.fprintf fmt "Chosen %s" p.name
  | Layer.None_matches -> Format.pp_print_string fmt "None_matches"
  | Layer.Retake -> Format.pp_print_string fmt "Retake"
  | Layer.Keep_unnamed -> Format.pp_print_string fmt "Keep_unnamed"

let outcome_t = Alcotest.testable pp_outcome Layer.equal_outcome

let pp_phase fmt = function
  | Layer.Sending {slow} -> Format.fprintf fmt "Sending {slow = %b}" slow
  | Layer.Proposals (i : Herbier_identify.identified) ->
      Format.fprintf fmt "Proposals {uncertain = %b; proposals = %d}"
        i.uncertain
        (List.length i.answer.proposals)
  | Layer.Failed f -> Format.fprintf fmt "Failed %a" Failure.pp f
  | Layer.Closed o -> Format.fprintf fmt "Closed %a" pp_outcome o

let phase_t = Alcotest.testable pp_phase Layer.equal_phase

let pp_request fmt (r : Layer.request) =
  Format.fprintf fmt "{flora = %S; no_reject = %b; organs = %a}" r.flora
    r.no_reject
    (Format.pp_print_list pp_organ_sent)
    r.organs

let request_t = Alcotest.testable pp_request Layer.equal_request

let pp_flora_opt fmt = function
  | None -> Format.pp_print_string fmt "None"
  | Some (f : Settings.flora) -> Format.fprintf fmt "Some {id = %S}" f.id

let flora_opt_t =
  Alcotest.testable pp_flora_opt (Option.equal Settings.equal_flora)

let pp_command fmt = function
  | Layer.Send {seq; request} ->
      Format.fprintf fmt "Send {seq = %d; request = %a}" seq pp_request request
  | Layer.Wait_slow {seq; ms} ->
      Format.fprintf fmt "Wait_slow {seq = %d; ms = %d}" seq ms
  | Layer.Take_photo o -> Format.fprintf fmt "Take_photo %a" pp_organ_sent o
  | Layer.Save_flora f -> Format.fprintf fmt "Save_flora %a" pp_flora_opt f
  | Layer.Close o -> Format.fprintf fmt "Close %a" pp_outcome o

let command_t = Alcotest.testable pp_command Layer.equal_command
let commands_t = Alcotest.list command_t

let pp_state fmt (t : Layer.t) =
  Format.fprintf fmt
    "{caller = %a; organs = %a; detected = %a; flora = %a; no_reject = %b; seq \
     = %d; taking = %b; phase = %a}"
    pp_caller t.caller
    (Format.pp_print_list pp_organ_sent)
    t.organs
    (Format.pp_print_list pp_organ_opt)
    t.detected pp_flora_opt t.flora t.no_reject t.seq t.taking pp_phase t.phase

let state_t = Alcotest.testable pp_state Layer.equal

(* ---------- shared values ---------- *)

let flora_so : Settings.flora =
  {id = "k-southwestern-europe"; title = "Europe du Sud-Ouest"}

let ready_key () =
  match Is.Key.of_input "abcdefgh" with
  | Some k -> k
  | None -> Alcotest.fail "Key.of_input \"abcdefgh\" should be a key"

let decode name =
  match Plantnet.decode_answer (Fixture.read name) with
  | Ok a -> a
  | Error e -> Alcotest.failf "decode %s: %s" name (Plantnet.error_to_string e)

let identified_of (answer : Plantnet.answer) : Herbier_identify.identified =
  {answer; uncertain = Proposal.uncertain answer.proposals}

let certain_answer = lazy (decode "plantnet_identify_two_flower_leaf_200.json")
let uncertain_answer = lazy (decode "plantnet_identify_one_auto_200.json")
let certain = lazy (identified_of (Lazy.force certain_answer))
let uncertain = lazy (identified_of (Lazy.force uncertain_answer))

let first_proposal (a : Plantnet.answer) =
  match a.proposals with
  | p :: _ -> p
  | [] -> Alcotest.fail "the certain fixture has no proposal"

let sample_proposal : Plantnet.proposal =
  {
    score = 0.9;
    name = "Sample";
    author = "";
    scientific_name = "Sample";
    family = None;
    common_names = [];
    gbif = None;
    images = [];
  }

let answer_of ~detected ?(proposals = [sample_proposal]) () : Plantnet.answer =
  {proposals; detected; flora = None; remaining = None}

let opened ?(caller = Caller.Noter) ?(flora = None) organs =
  Layer.open_ ~caller ~flora organs

let answered (t : Layer.t) result =
  Layer.step t (Layer.Answered {seq = t.seq; result})

(* ============================================================ *)
(* Caller *)
(* ============================================================ *)

let caller_action () =
  Alcotest.(check action_t)
    "Noter, owned" Caller.Choose
    (Caller.action Caller.Noter ~owned:true);
  Alcotest.(check action_t)
    "Noter, not owned" Caller.Choose
    (Caller.action Caller.Noter ~owned:false);
  let queue = Caller.Queue {index = 1; total = 3} in
  Alcotest.(check action_t)
    "Queue, owned" Caller.Link
    (Caller.action queue ~owned:true);
  Alcotest.(check action_t)
    "Queue, not owned" Caller.Create
    (Caller.action queue ~owned:false);
  let free = Caller.Free_name (Plant_id.fresh ()) in
  Alcotest.(check action_t)
    "Free_name, owned" Caller.Link
    (Caller.action free ~owned:true);
  Alcotest.(check action_t)
    "Free_name, not owned" Caller.Link
    (Caller.action free ~owned:false)

let caller_current_and_retake () =
  let id = Plant_id.fresh () in
  Alcotest.(check (option plant_id_t))
    "Free_name" (Some id)
    (Caller.current (Caller.Free_name id));
  Alcotest.(check (option plant_id_t))
    "Noter" None
    (Caller.current Caller.Noter);
  Alcotest.(check (option plant_id_t))
    "Queue" None
    (Caller.current (Caller.Queue {index = 1; total = 1}));
  Alcotest.(check bool) "retake Noter" true (Caller.retake Caller.Noter);
  Alcotest.(check bool)
    "retake Queue" false
    (Caller.retake (Caller.Queue {index = 1; total = 1}));
  Alcotest.(check bool)
    "retake Free_name" false
    (Caller.retake (Caller.Free_name id))

let caller_tests =
  [
    Alcotest.test_case
      "action: Noter -> Choose, Queue -> Link/Create by owned, Free_name -> \
       Link both"
      `Quick caller_action;
    Alcotest.test_case "current: Some id only for Free_name; retake: Noter only"
      `Quick caller_current_and_retake;
  ]

(* ============================================================ *)
(* Owned *)
(* ============================================================ *)

let owned_none_gbif_or_no_match () =
  let p = Fixtures.plant_with ~gbif_key:(Some 111) () in
  Alcotest.(check owned_opt_t)
    "gbif = None" None
    (Owned.find ~current:None ~plants:[p] ~observations:[] None);
  Alcotest.(check owned_opt_t)
    "no plant with that gbif_key" None
    (Owned.find ~current:None ~plants:[p] ~observations:[] (Some 222))

let owned_match_first_wins () =
  let a = Fixtures.plant_with ~gbif_key:(Some 100) ()
  and b = Fixtures.plant_with ~gbif_key:(Some 100) () in
  Alcotest.(check owned_opt_t)
    "the first in list order"
    (Some {Owned.plant = a; observations = 0})
    (Owned.find ~current:None ~plants:[a; b] ~observations:[] (Some 100))

let owned_skips_deleted_and_current () =
  let t = Fixtures.utc 2026 1 1 0 0 in
  let deleted =
    {(Fixtures.plant_with ~gbif_key:(Some 100) ()) with deleted_at = Some t}
  in
  let current_plant = Fixtures.plant_with ~gbif_key:(Some 100) () in
  let later = Fixtures.plant_with ~gbif_key:(Some 100) () in
  Alcotest.(check owned_opt_t)
    "deleted and current skipped, later found"
    (Some {Owned.plant = later; observations = 0})
    (Owned.find ~current:(Some current_plant.id)
       ~plants:[deleted; current_plant; later]
       ~observations:[] (Some 100))

let owned_observation_count () =
  let t = Fixtures.utc 2026 1 1 0 0 in
  let target = Fixtures.plant_with ~gbif_key:(Some 100) () in
  let other = Fixtures.plant_with ~gbif_key:(Some 200) () in
  let obs1 = Fixtures.plant_obs (Some target.id)
  and obs2 = Fixtures.plant_obs (Some target.id)
  and obs_deleted =
    {(Fixtures.plant_obs (Some target.id)) with deleted_at = Some t}
  and obs_other = Fixtures.plant_obs (Some other.id) in
  Alcotest.(check owned_opt_t)
    "0 observations possible"
    (Some {Owned.plant = target; observations = 0})
    (Owned.find ~current:None ~plants:[target] ~observations:[] (Some 100));
  Alcotest.(check owned_opt_t)
    "only live observations of that plant counted"
    (Some {Owned.plant = target; observations = 2})
    (Owned.find ~current:None ~plants:[target]
       ~observations:[obs1; obs2; obs_deleted; obs_other]
       (Some 100))

let owned_tests =
  [
    Alcotest.test_case "find: None gbif and no match both give None" `Quick
      owned_none_gbif_or_no_match;
    Alcotest.test_case "find: matches on gbif_key, the first in list order wins"
      `Quick owned_match_first_wins;
    Alcotest.test_case "find: a deleted plant and the current plant are skipped"
      `Quick owned_skips_deleted_and_current;
    Alcotest.test_case
      "find: observations counts only live observations of that plant, 0 \
       possible"
      `Quick owned_observation_count;
  ]

(* ============================================================ *)
(* Failure *)
(* ============================================================ *)

let of_error_table () =
  let check msg ~no_reject error expected =
    Alcotest.(check failure_t) msg expected (Failure.of_error ~no_reject error)
  in
  check "No_plant, not no_reject" ~no_reject:false
    (Failure.Plantnet Plantnet.No_plant)
    (Failure.No_plant {can_force = true});
  check "No_plant, no_reject" ~no_reject:true
    (Failure.Plantnet Plantnet.No_plant)
    (Failure.No_plant {can_force = false});
  List.iter
    (fun (e, label) ->
      check
        (Printf.sprintf "%s -> Not_answered" label)
        ~no_reject:false (Failure.Plantnet e) Failure.Not_answered)
    [
      (Plantnet.Unreachable Plantnet.Timeout, "Unreachable Timeout");
      (Plantnet.Unreachable Plantnet.Network, "Unreachable Network");
      (Plantnet.Unreachable (Plantnet.Server 503), "Unreachable (Server 503)");
      (Plantnet.Key_not_exposed, "Key_not_exposed");
      (Plantnet.Refused_request 413, "Refused_request 413");
      (Plantnet.Malformed "x", "Malformed");
      (Plantnet.No_photo, "No_photo (never reached)");
    ];
  check "Quota_used_up -> Used_up" ~no_reject:false
    (Failure.Plantnet Plantnet.Quota_used_up) Failure.Used_up;
  check "Key_refused -> Key_refused" ~no_reject:false
    (Failure.Plantnet Plantnet.Key_refused) Failure.Key_refused;
  check "No_key -> No_key" ~no_reject:false (Failure.Plantnet Plantnet.No_key)
    Failure.No_key;
  check "Not_sent_offline -> Offline" ~no_reject:false Failure.Not_sent_offline
    Failure.Offline;
  check "Preview_unreadable -> Unreadable" ~no_reject:false
    Failure.Preview_unreadable Failure.Unreadable

let key_not_exposed_is_not_answered () =
  let a =
    Failure.of_error ~no_reject:false
      (Failure.Plantnet Plantnet.Key_not_exposed)
  in
  let b =
    Failure.of_error ~no_reject:false
      (Failure.Plantnet (Plantnet.Unreachable Plantnet.Timeout))
  in
  Alcotest.(check failure_t)
    "Key_not_exposed equals Unreachable Timeout (= Not_answered)" b a;
  Alcotest.(check bool) "retry of it is true" true (Failure.retry a)

let no_plant_no_reject () =
  Alcotest.(check failure_t)
    "no_reject:true -> can_force = false"
    (Failure.No_plant {can_force = false})
    (Failure.of_error ~no_reject:true (Failure.Plantnet Plantnet.No_plant))

let retry_and_reask_tables () =
  let no_plant_true = Failure.No_plant {can_force = true}
  and no_plant_false = Failure.No_plant {can_force = false} in
  List.iter
    (fun (f, expected) ->
      Alcotest.(check bool)
        (Printf.sprintf "retry %s" (Failure.show f))
        expected (Failure.retry f))
    [
      (no_plant_true, false);
      (no_plant_false, false);
      (Failure.Not_answered, true);
      (Failure.Offline, true);
      (Failure.Used_up, false);
      (Failure.Key_refused, false);
      (Failure.No_key, false);
      (Failure.Unreadable, false);
    ];
  List.iter
    (fun (f, expected) ->
      Alcotest.(check bool)
        (Printf.sprintf "reask %s" (Failure.show f))
        expected (Failure.reask f))
    [
      (no_plant_true, true);
      (no_plant_false, true);
      (Failure.Not_answered, true);
      (Failure.Offline, true);
      (Failure.Used_up, false);
      (Failure.Key_refused, false);
      (Failure.No_key, false);
      (Failure.Unreadable, false);
    ]

let of_gate_tests () =
  let error_t =
    Alcotest.testable
      (fun fmt -> function
        | Failure.Not_sent_offline ->
            Format.pp_print_string fmt "Not_sent_offline"
        | Failure.Preview_unreadable ->
            Format.pp_print_string fmt "Preview_unreadable"
        | Failure.Plantnet e ->
            Format.fprintf fmt "Plantnet %a" Plantnet.pp_error e)
      Failure.equal_error
  in
  let check name expected gate =
    Alcotest.(check (result string error_t))
      name expected
      (Result.map Is.Key.to_string (Failure.of_gate gate))
  in
  let k = ready_key () in
  check "Ready k -> Ok k" (Ok (Is.Key.to_string k)) (Is.Ready k);
  check "Offline -> Not_sent_offline" (Error Failure.Not_sent_offline)
    Is.Offline;
  check "Waiting -> Not_sent_offline" (Error Failure.Not_sent_offline)
    Is.Waiting;
  check "No_key -> Plantnet No_key" (Error (Failure.Plantnet Plantnet.No_key))
    Is.No_key

let failure_tests =
  [
    Alcotest.test_case "of_gate: the key, or the error sent without a request"
      `Quick of_gate_tests;
    Alcotest.test_case
      "of_error: every Plantnet.error constructor and \
       Not_sent_offline/Preview_unreadable"
      `Quick of_error_table;
    Alcotest.test_case
      "of_error (Plantnet Key_not_exposed) equals of_error (Plantnet \
       (Unreachable Timeout)), and retry of it is true"
      `Quick key_not_exposed_is_not_answered;
    Alcotest.test_case "No_plant with ~no_reject:true has can_force = false"
      `Quick no_plant_no_reject;
    Alcotest.test_case "retry and reask truth tables" `Quick
      retry_and_reask_tables;
  ]

(* ============================================================ *)
(* Layer *)
(* ============================================================ *)

let open_tests () =
  let t1, cmds1 = opened [Organ.Auto] in
  Alcotest.(check phase_t)
    "Sending {slow = false}"
    (Layer.Sending {slow = false})
    t1.phase;
  Alcotest.(check int) "seq = 1" 1 t1.seq;
  Alcotest.(check commands_t)
    "Send + Wait_slow"
    [
      Layer.Send
        {
          seq = 1;
          request = {flora = "all"; no_reject = false; organs = [Organ.Auto]};
        };
      Layer.Wait_slow {seq = 1; ms = 600};
    ]
    cmds1;
  let t2, _ = opened ~flora:(Some flora_so) [Organ.Auto] in
  Alcotest.(check string)
    "request.flora is the chosen flora's id" flora_so.id
    (Layer.request t2).flora;
  let seven = List.init 7 (fun _ -> Organ.Auto) in
  let t3, _ = opened seven in
  Alcotest.(check int) "7 organs: only 5 kept" 5 (List.length t3.organs);
  let t4, cmds4 = opened [] in
  Alcotest.(check phase_t)
    "[] -> Closed Left" (Layer.Closed Layer.Left) t4.phase;
  Alcotest.(check commands_t)
    "[] -> [Close Left]" [Layer.Close Layer.Left] cmds4

let slow_tests () =
  let t, _ = opened [Organ.Auto] in
  let t', cmds = Layer.step t (Layer.Slow 1) in
  Alcotest.(check phase_t)
    "Slow 1 on seq 1 -> slow = true"
    (Layer.Sending {slow = true})
    t'.phase;
  Alcotest.(check commands_t) "no command" [] cmds;
  let t'', cmds2 = Layer.step t (Layer.Slow 0) in
  Alcotest.(check state_t) "stale Slow 0 unchanged" t t'';
  Alcotest.(check commands_t) "no command" [] cmds2;
  let tp, _ = answered t (Ok (Lazy.force uncertain)) in
  let tp', cmds3 = Layer.step tp (Layer.Slow 1) in
  Alcotest.(check state_t) "Slow while Proposals: unchanged" tp tp';
  Alcotest.(check commands_t) "no command" [] cmds3

let answered_ok_tests () =
  let t2, _ = opened [Organ.Auto; Organ.Auto] in
  let certain = Lazy.force certain in
  let t2', cmds = answered t2 (Ok certain) in
  Alcotest.(check phase_t)
    "certain fixture -> Proposals" (Layer.Proposals certain) t2'.phase;
  Alcotest.(check bool) "fixture is not uncertain" false certain.uncertain;
  Alcotest.(check organ_opt_list_t)
    "detected from predictedOrgans"
    [Some Organ.Flower; Some Organ.Leaf]
    t2'.detected;
  Alcotest.(check commands_t) "no command" [] cmds;
  let t3, _ = opened [Organ.Auto] in
  let unc = Lazy.force uncertain in
  let t3', _ = answered t3 (Ok unc) in
  (match t3'.phase with
  | Layer.Proposals i ->
      Alcotest.(check bool)
        "uncertain fixture -> uncertain = true" true i.uncertain
  | _ -> Alcotest.fail "expected Proposals");
  let tpad, _ = opened [Organ.Auto; Organ.Auto] in
  let tpad', _ =
    answered tpad
      (Ok (identified_of (answer_of ~detected:[Some Organ.Flower] ())))
  in
  Alcotest.(check organ_opt_list_t)
    "shorter detected padded with None" [Some Organ.Flower; None] tpad'.detected;
  let ttrunc, _ = opened [Organ.Auto; Organ.Auto] in
  let ttrunc', _ =
    answered ttrunc
      (Ok
         (identified_of
            (answer_of
               ~detected:[Some Organ.Flower; Some Organ.Leaf; Some Organ.Fruit]
               ())))
  in
  Alcotest.(check organ_opt_list_t)
    "longer detected truncated to organs length"
    [Some Organ.Flower; Some Organ.Leaf]
    ttrunc'.detected

let answered_stale_or_settled_tests () =
  let t, _ = opened [Organ.Auto] in
  let t', cmds =
    Layer.step t (Layer.Answered {seq = 2; result = Ok (Lazy.force uncertain)})
  in
  Alcotest.(check state_t) "stale seq (2 <> 1) unchanged" t t';
  Alcotest.(check commands_t) "no command" [] cmds;
  let tp, _ = answered t (Ok (Lazy.force uncertain)) in
  let tp2, cmds2 = answered tp (Ok (Lazy.force certain)) in
  Alcotest.(check state_t) "second answer while Proposals: unchanged" tp tp2;
  Alcotest.(check commands_t) "no command" [] cmds2;
  let tf, _ = answered t (Error (Failure.Plantnet Plantnet.Quota_used_up)) in
  let tf2, cmds3 = answered tf (Ok (Lazy.force certain)) in
  Alcotest.(check state_t) "Answered while Failed: unchanged" tf tf2;
  Alcotest.(check commands_t) "no command" [] cmds3

let answered_empty_proposals_tests () =
  let t, _ = opened [Organ.Auto] in
  let t', cmds =
    answered t
      (Ok (identified_of (answer_of ~proposals:[] ~detected:[None] ())))
  in
  Alcotest.(check phase_t)
    "empty proposals -> Failed (No_plant {can_force = true})"
    (Layer.Failed (Failure.No_plant {can_force = true}))
    t'.phase;
  Alcotest.(check commands_t) "no command" [] cmds

let answered_error_tests () =
  let errors =
    [
      Failure.Not_sent_offline;
      Failure.Preview_unreadable;
      Failure.Plantnet Plantnet.No_plant;
      Failure.Plantnet (Plantnet.Unreachable Plantnet.Timeout);
      Failure.Plantnet Plantnet.Key_not_exposed;
      Failure.Plantnet Plantnet.Quota_used_up;
      Failure.Plantnet Plantnet.Key_refused;
      Failure.Plantnet Plantnet.No_key;
    ]
  in
  List.iter
    (fun e ->
      let t, _ = opened [Organ.Auto] in
      let t', _ = answered t (Error e) in
      Alcotest.(check phase_t)
        (Printf.sprintf "%s -> Failed (Failure.of_error ...)"
           (Failure.show (Failure.of_error ~no_reject:false e)))
        (Layer.Failed (Failure.of_error ~no_reject:false e))
        t'.phase)
    errors;
  let t, _ = opened [Organ.Auto] in
  let t', _ = answered t (Error (Failure.Plantnet Plantnet.Key_not_exposed)) in
  Alcotest.(check phase_t)
    "Key_not_exposed -> Failed Not_answered" (Layer.Failed Failure.Not_answered)
    t'.phase;
  let tp, _ = answered t (Ok (Lazy.force uncertain)) in
  let tre, _ =
    Layer.step tp (Layer.Set_organ {photo = 0; organ = Organ.Leaf})
  in
  let terr, _ =
    answered tre (Error (Failure.Plantnet Plantnet.Quota_used_up))
  in
  Alcotest.(check organ_opt_list_t)
    "an error leaves detected as the last answer gave it" [Some Organ.Flower]
    terr.detected

let choose_tests () =
  let t, _ = opened [Organ.Auto; Organ.Auto] in
  let certain = Lazy.force certain in
  let tp, _ = answered t (Ok certain) in
  let p0 = first_proposal certain.answer in
  let tc, cmds = Layer.step tp (Layer.Choose 0) in
  Alcotest.(check phase_t)
    "Choose 0 -> Closed (Chosen p0)" (Layer.Closed (Layer.Chosen p0)) tc.phase;
  Alcotest.(check commands_t)
    "[Close (Chosen p0)]"
    [Layer.Close (Layer.Chosen p0)]
    cmds;
  let tc2, cmds2 = Layer.step tp (Layer.Choose 9) in
  Alcotest.(check state_t) "out of range unchanged" tp tc2;
  Alcotest.(check commands_t) "no command" [] cmds2;
  let ts, cmds3 = Layer.step t (Layer.Choose 0) in
  Alcotest.(check state_t) "Choose while Sending unchanged" t ts;
  Alcotest.(check commands_t) "no command" [] cmds3

let none_matches_tests () =
  let t, _ = opened [Organ.Auto] in
  let tp, _ = answered t (Ok (Lazy.force uncertain)) in
  let tn, cmds = Layer.step tp Layer.None_matches in
  Alcotest.(check phase_t)
    "None_matches in Proposals -> Closed None_matches"
    (Layer.Closed Layer.None_matches) tn.phase;
  Alcotest.(check commands_t)
    "[Close None_matches]"
    [Layer.Close Layer.None_matches]
    cmds;
  let ts, cmds2 = Layer.step t Layer.None_matches in
  Alcotest.(check state_t) "None_matches while Sending unchanged" t ts;
  Alcotest.(check commands_t) "no command" [] cmds2

let effective_organs_tests () =
  let t, _ = opened [Organ.Auto; Organ.Auto] in
  Alcotest.(check organ_opt_list_t)
    "before any answer: Auto with no detected organ is unknown" [None; None]
    (Layer.effective_organs t);
  let tp, _ = answered t (Ok (Lazy.force certain)) in
  Alcotest.(check organ_opt_list_t)
    "Auto photos take the detected organs"
    [Some Organ.Flower; Some Organ.Leaf]
    (Layer.effective_organs tp);
  let tg, _ =
    Layer.step tp (Layer.Set_organ {photo = 0; organ = Organ.Fruit})
  in
  Alcotest.(check organ_opt_list_t)
    "a given organ wins over the detected one"
    [Some Organ.Fruit; Some Organ.Leaf]
    (Layer.effective_organs tg)

let back_tests () =
  let t, _ = opened [Organ.Auto] in
  let tb, cmds = Layer.step t Layer.Back in
  Alcotest.(check phase_t)
    "Back from Sending -> Closed Left" (Layer.Closed Layer.Left) tb.phase;
  Alcotest.(check commands_t) "[Close Left]" [Layer.Close Layer.Left] cmds;
  let tp, _ = answered t (Ok (Lazy.force uncertain)) in
  let tpb, cmds2 = Layer.step tp Layer.Back in
  Alcotest.(check phase_t)
    "Back from Proposals -> Closed Left" (Layer.Closed Layer.Left) tpb.phase;
  Alcotest.(check commands_t) "[Close Left]" [Layer.Close Layer.Left] cmds2;
  let tf, _ = answered t (Error (Failure.Plantnet Plantnet.Quota_used_up)) in
  let tfb, cmds3 = Layer.step tf Layer.Back in
  Alcotest.(check phase_t)
    "Back from Failed -> Closed Left" (Layer.Closed Layer.Left) tfb.phase;
  Alcotest.(check commands_t) "[Close Left]" [Layer.Close Layer.Left] cmds3;
  let tafter, cmds4 = Layer.step tb Layer.Retry in
  Alcotest.(check state_t) "any event after Closed: unchanged" tb tafter;
  Alcotest.(check commands_t) "no command" [] cmds4

let set_organ_tests () =
  let t, _ = opened [Organ.Auto] in
  let tp, _ = answered t (Ok (Lazy.force uncertain)) in
  Alcotest.(check organ_opt_list_t)
    "detected Flower for the single photo" [Some Organ.Flower] tp.detected;
  let ts, cmds =
    Layer.step tp (Layer.Set_organ {photo = 0; organ = Organ.Leaf})
  in
  Alcotest.(check organ_sent_list_t)
    "organ corrected to Given Leaf" [Organ.Given Organ.Leaf] ts.organs;
  Alcotest.(check bool) "no_reject = false" false ts.no_reject;
  Alcotest.(check int) "seq + 1" (tp.seq + 1) ts.seq;
  Alcotest.(check commands_t)
    "re-ask"
    [
      Layer.Send {seq = ts.seq; request = Layer.request ts};
      Layer.Wait_slow {seq = ts.seq; ms = Layer.slow_ms};
    ]
    cmds;
  let tsame, cmds2 =
    Layer.step tp (Layer.Set_organ {photo = 0; organ = Organ.Flower})
  in
  Alcotest.(check state_t) "same as the detected organ: unchanged" tp tsame;
  Alcotest.(check commands_t) "no Send" [] cmds2;
  let tbad, cmds3 =
    Layer.step tp (Layer.Set_organ {photo = 5; organ = Organ.Leaf})
  in
  Alcotest.(check state_t) "out-of-range photo: unchanged" tp tbad;
  Alcotest.(check commands_t) "no command" [] cmds3;
  let tneg, cmds4 =
    Layer.step tp (Layer.Set_organ {photo = -1; organ = Organ.Leaf})
  in
  Alcotest.(check state_t) "negative photo: unchanged" tp tneg;
  Alcotest.(check commands_t) "negative photo: no command" [] cmds4

let add_tile_tests () =
  let t, _ = opened [Organ.Auto] in
  let tp, _ = answered t (Ok (Lazy.force uncertain)) in
  let _, cmds = Layer.step tp Layer.Add in
  Alcotest.(check commands_t)
    "detected Flower -> Take_photo (Given Leaf)"
    [Layer.Take_photo (Organ.Given Organ.Leaf)]
    cmds;
  let t2, _ = opened [Organ.Auto] in
  let tp2, _ =
    answered t2 (Ok (identified_of (answer_of ~detected:[None] ())))
  in
  let _, cmds2 = Layer.step tp2 Layer.Add in
  Alcotest.(check commands_t)
    "detected none -> Take_photo (Given Flower)"
    [Layer.Take_photo (Organ.Given Organ.Flower)]
    cmds2;
  let t3, _ = opened [Organ.Auto; Organ.Auto] in
  let tp3, _ = answered t3 (Ok (Lazy.force certain)) in
  let _, cmds3 = Layer.step tp3 Layer.Add in
  Alcotest.(check commands_t)
    "flower + leaf -> Take_photo Auto"
    [Layer.Take_photo Organ.Auto]
    cmds3;
  let five = List.init 5 (fun _ -> Organ.Auto) in
  let t4, _ = opened five in
  let tp4, _ =
    answered t4
      (Ok (identified_of (answer_of ~detected:(List.init 5 (fun _ -> None)) ())))
  in
  let _, cmds4 = Layer.step tp4 Layer.Add in
  Alcotest.(check commands_t) "5 photos -> no command" [] cmds4;
  let t5, _ = opened [Organ.Auto] in
  let tf5, _ =
    answered t5
      (Ok (identified_of (answer_of ~proposals:[] ~detected:[None] ())))
  in
  let _, cmds5 = Layer.step tf5 Layer.Add in
  Alcotest.(check commands_t)
    "Failed (No_plant _) -> Take_photo Auto"
    [Layer.Take_photo Organ.Auto]
    cmds5;
  let t6, _ = opened [Organ.Auto] in
  let tf6, _ = answered t6 (Error (Failure.Plantnet Plantnet.Quota_used_up)) in
  let _, cmds6 = Layer.step tf6 Layer.Add in
  Alcotest.(check commands_t) "Failed Used_up -> no command" [] cmds6

let photo_added_tests () =
  let t, _ = opened [Organ.Auto] in
  let tp, _ = answered t (Ok (Lazy.force uncertain)) in
  let ta, cmds =
    Layer.step tp (Layer.Photo_added (Some (Organ.Given Organ.Leaf)))
  in
  Alcotest.(check organ_sent_list_t)
    "the photo's organ appended"
    [Organ.Auto; Organ.Given Organ.Leaf]
    ta.organs;
  Alcotest.(check organ_opt_list_t)
    "detected padded with None" (tp.detected @ [None]) ta.detected;
  Alcotest.(check bool) "no_reject = false" false ta.no_reject;
  Alcotest.(check int) "seq + 1" (tp.seq + 1) ta.seq;
  Alcotest.(check commands_t)
    "re-ask"
    [
      Layer.Send
        {
          seq = ta.seq;
          request =
            {
              flora = "all";
              no_reject = false;
              organs = [Organ.Auto; Organ.Given Organ.Leaf];
            };
        };
      Layer.Wait_slow {seq = ta.seq; ms = Layer.slow_ms};
    ]
    cmds;
  let tn, cmds2 = Layer.step tp (Layer.Photo_added None) in
  Alcotest.(check state_t) "Photo_added None: unchanged" tp tn;
  Alcotest.(check commands_t) "no command" [] cmds2;
  let five = List.init 5 (fun _ -> Organ.Auto) in
  let t5, _ = opened five in
  let tp5, _ =
    answered t5
      (Ok (identified_of (answer_of ~detected:(List.init 5 (fun _ -> None)) ())))
  in
  let ta5, cmds3 = Layer.step tp5 (Layer.Photo_added (Some Organ.Auto)) in
  Alcotest.(check state_t) "5 photos: unchanged" tp5 ta5;
  Alcotest.(check commands_t) "no command" [] cmds3;
  let tnp, _ =
    answered t
      (Ok (identified_of (answer_of ~proposals:[] ~detected:[None] ())))
  in
  let tnpa, cmds4 = Layer.step tnp (Layer.Photo_added (Some Organ.Auto)) in
  Alcotest.(check organ_sent_list_t)
    "Failed No_plant: the photo appended" [Organ.Auto; Organ.Auto] tnpa.organs;
  Alcotest.(check organ_opt_list_t)
    "Failed No_plant: detected padded" [None; None] tnpa.detected;
  Alcotest.(check int) "Failed No_plant: seq + 1" (tnp.seq + 1) tnpa.seq;
  Alcotest.(check commands_t)
    "Failed No_plant: re-ask"
    [
      Layer.Send
        {
          seq = tnpa.seq;
          request =
            {
              flora = "all";
              no_reject = false;
              organs = [Organ.Auto; Organ.Auto];
            };
        };
      Layer.Wait_slow {seq = tnpa.seq; ms = Layer.slow_ms};
    ]
    cmds4;
  List.iter
    (fun (name, err) ->
      let tf, _ = answered t (Error err) in
      let tfa, cmds = Layer.step tf (Layer.Photo_added (Some Organ.Auto)) in
      Alcotest.(check state_t) (name ^ ": unchanged") tf tfa;
      Alcotest.(check commands_t) (name ^ ": no command") [] cmds)
    [
      ("Failed Used_up", Failure.Plantnet Plantnet.Quota_used_up);
      ("Failed Key_refused", Failure.Plantnet Plantnet.Key_refused);
    ]

(* A photo being taken: a second tap or a re-ask waits for it, so that it is
   neither taken twice nor dropped by a phase change. *)
let taking_tests () =
  let t, _ = opened [Organ.Auto] in
  let tp, _ = answered t (Ok (Lazy.force uncertain)) in
  let tt, cmds = Layer.step tp Layer.Add in
  Alcotest.(check bool) "Add: taking" true tt.taking;
  Alcotest.(check commands_t)
    "Add: Take_photo"
    [Layer.Take_photo (Organ.Given Organ.Leaf)]
    cmds;
  List.iter
    (fun (name, ev) ->
      let t2, cmds2 = Layer.step tt ev in
      Alcotest.(check state_t) (name ^ " while taking: unchanged") tt t2;
      Alcotest.(check commands_t) (name ^ " while taking: no command") [] cmds2)
    [
      ("Add", Layer.Add);
      ("Set_organ", Layer.Set_organ {photo = 0; organ = Organ.Fruit});
      ("Set_flora", Layer.Set_flora (Some flora_so));
    ];
  let ta, cmds3 =
    Layer.step tt (Layer.Photo_added (Some (Organ.Given Organ.Leaf)))
  in
  Alcotest.(check bool) "Photo_added: not taking" false ta.taking;
  Alcotest.(check organ_sent_list_t)
    "Photo_added: kept"
    [Organ.Auto; Organ.Given Organ.Leaf]
    ta.organs;
  Alcotest.(check int)
    "Photo_added: one Send" 1
    (List.length
       (List.filter (function Layer.Send _ -> true | _ -> false) cmds3));
  let tc, cmds4 = Layer.step tt (Layer.Photo_added None) in
  Alcotest.(check state_t)
    "Photo_added None: taking cleared" {tt with taking = false} tc;
  Alcotest.(check commands_t) "Photo_added None: no command" [] cmds4;
  let _, cmds5 = Layer.step tc Layer.Add in
  Alcotest.(check commands_t)
    "Add after a cancel: Take_photo again"
    [Layer.Take_photo (Organ.Given Organ.Leaf)]
    cmds5;
  let tf, _ = answered t (Error Failure.Not_sent_offline) in
  let tft, _ = Layer.step tf Layer.Add in
  List.iter
    (fun (name, ev) ->
      let t2, cmds2 = Layer.step tft ev in
      Alcotest.(check state_t) (name ^ " while taking: unchanged") tft t2;
      Alcotest.(check commands_t) (name ^ " while taking: no command") [] cmds2)
    [("Retry", Layer.Retry)];
  let tnp, _ =
    answered t
      (Ok (identified_of (answer_of ~proposals:[] ~detected:[None] ())))
  in
  let tnpt, _ = Layer.step tnp Layer.Add in
  let tnpf, cmds7 = Layer.step tnpt Layer.Force in
  Alcotest.(check state_t) "Force while taking: unchanged" tnpt tnpf;
  Alcotest.(check commands_t) "Force while taking: no command" [] cmds7;
  let tb, cmds6 = Layer.step tt Layer.Back in
  Alcotest.(check phase_t)
    "Back while taking closes" (Layer.Closed Layer.Left) tb.phase;
  Alcotest.(check commands_t) "[Close Left]" [Layer.Close Layer.Left] cmds6

let accepts_photo_tests () =
  let t, _ = opened [Organ.Auto] in
  Alcotest.(check bool) "Sending" false (Layer.accepts_photo t);
  let tp, _ = answered t (Ok (Lazy.force uncertain)) in
  Alcotest.(check bool) "Proposals" true (Layer.accepts_photo tp);
  let tnp, _ =
    answered t
      (Ok (identified_of (answer_of ~proposals:[] ~detected:[None] ())))
  in
  Alcotest.(check bool) "Failed No_plant" true (Layer.accepts_photo tnp);
  let tu, _ = answered t (Error (Failure.Plantnet Plantnet.Quota_used_up)) in
  Alcotest.(check bool) "Failed Used_up" false (Layer.accepts_photo tu);
  let five = List.init 5 (fun _ -> Organ.Auto) in
  let tp5, _ =
    answered
      (fst (opened five))
      (Ok (identified_of (answer_of ~detected:(List.init 5 (fun _ -> None)) ())))
  in
  Alcotest.(check bool) "5 photos" false (Layer.accepts_photo tp5);
  let tc, _ = Layer.step tp Layer.Back in
  Alcotest.(check bool) "Closed" false (Layer.accepts_photo tc)

let set_flora_tests () =
  let t, _ = opened [Organ.Auto] in
  let tp, _ = answered t (Ok (Lazy.force uncertain)) in
  let tf, cmds = Layer.step tp (Layer.Set_flora (Some flora_so)) in
  Alcotest.(check flora_opt_t) "flora set" (Some flora_so) tf.flora;
  Alcotest.(check bool) "no_reject reset to false" false tf.no_reject;
  Alcotest.(check commands_t)
    "Save_flora :: re-ask"
    [
      Layer.Save_flora (Some flora_so);
      Layer.Send {seq = tf.seq; request = Layer.request tf};
      Layer.Wait_slow {seq = tf.seq; ms = Layer.slow_ms};
    ]
    cmds;
  Alcotest.(check string)
    "request.flora is the chosen id" flora_so.id (Layer.request tf).flora;
  let tsame, cmds2 = Layer.step tp (Layer.Set_flora None) in
  Alcotest.(check state_t) "Set_flora None from None: unchanged" tp tsame;
  Alcotest.(check commands_t) "no command" [] cmds2;
  (* [tf] just re-asked, so its phase is [Sending], where [Set_flora] does not
     match; answer it first to get back to [Proposals] with [flora] still
     [Some flora_so], then clear it. *)
  let tf_answered, _ = answered tf (Ok (Lazy.force uncertain)) in
  let tnone, cmds3 = Layer.step tf_answered (Layer.Set_flora None) in
  Alcotest.(check flora_opt_t)
    "Set_flora None from Some: flora cleared" None tnone.flora;
  Alcotest.(check string)
    "Set_flora None from Some: request flora is \"all\"" Plantnet.automatic
    (Layer.request tnone).flora;
  Alcotest.(check commands_t)
    "Save_flora None :: re-ask"
    [
      Layer.Save_flora None;
      Layer.Send {seq = tnone.seq; request = Layer.request tnone};
      Layer.Wait_slow {seq = tnone.seq; ms = Layer.slow_ms};
    ]
    cmds3

let force_tests () =
  let t, _ = opened [Organ.Auto] in
  let empty = answer_of ~proposals:[] ~detected:[None] () in
  let tf, _ = answered t (Ok (identified_of empty)) in
  Alcotest.(check phase_t)
    "No_plant {can_force = true}"
    (Layer.Failed (Failure.No_plant {can_force = true}))
    tf.phase;
  let tfo, cmds = Layer.step tf Layer.Force in
  Alcotest.(check bool) "no_reject = true" true tfo.no_reject;
  Alcotest.(check bool)
    "request.no_reject = true" true (Layer.request tfo).no_reject;
  Alcotest.(check commands_t)
    "re-ask"
    [
      Layer.Send {seq = tfo.seq; request = Layer.request tfo};
      Layer.Wait_slow {seq = tfo.seq; ms = Layer.slow_ms};
    ]
    cmds;
  let tf2, _ = answered tfo (Error (Failure.Plantnet Plantnet.No_plant)) in
  Alcotest.(check phase_t)
    "forced 404 -> No_plant {can_force = false}"
    (Layer.Failed (Failure.No_plant {can_force = false}))
    tf2.phase;
  let tf3, cmds2 = Layer.step tf2 Layer.Force in
  Alcotest.(check state_t) "Force then (can_force = false): unchanged" tf2 tf3;
  Alcotest.(check commands_t) "no command" [] cmds2;
  let tf4, _ = answered tfo (Ok (identified_of empty)) in
  Alcotest.(check phase_t)
    "forced empty Ok -> No_plant {can_force = false}"
    (Layer.Failed (Failure.No_plant {can_force = false}))
    tf4.phase

let no_reject_reset_tests () =
  let t, _ = opened [Organ.Auto] in
  let tnp, _ =
    answered t
      (Ok (identified_of (answer_of ~proposals:[] ~detected:[None] ())))
  in
  let tforced, _ = Layer.step tnp Layer.Force in
  let tprop, _ = answered tforced (Ok (Lazy.force uncertain)) in
  Alcotest.(check bool)
    "no_reject stays true after a forced Ok answer" true tprop.no_reject;
  let treset, _ =
    Layer.step tprop (Layer.Set_organ {photo = 0; organ = Organ.Leaf})
  in
  Alcotest.(check bool)
    "Set_organ re-ask resets no_reject" false treset.no_reject;
  Alcotest.(check bool)
    "request.no_reject = false" false (Layer.request treset).no_reject;
  let tphoto, _ =
    Layer.step tprop (Layer.Photo_added (Some (Organ.Given Organ.Fruit)))
  in
  Alcotest.(check bool)
    "Photo_added re-ask resets no_reject" false tphoto.no_reject;
  let tflora, _ = Layer.step tprop (Layer.Set_flora (Some flora_so)) in
  Alcotest.(check bool)
    "Set_flora re-ask resets no_reject" false tflora.no_reject;
  let tkeyoff, _ =
    answered tforced (Error (Failure.Plantnet Plantnet.Key_not_exposed))
  in
  Alcotest.(check phase_t)
    "forced request, Key_not_exposed -> Failed Not_answered"
    (Layer.Failed Failure.Not_answered) tkeyoff.phase;
  Alcotest.(check bool)
    "no_reject stays true in the Failed state" true tkeyoff.no_reject;
  let tretry, _ = Layer.step tkeyoff Layer.Retry in
  Alcotest.(check bool) "Retry keeps no_reject true" true tretry.no_reject;
  Alcotest.(check bool)
    "request.no_reject = true" true (Layer.request tretry).no_reject

let retry_tests () =
  List.iter
    (fun (err, reasks) ->
      let t, _ = opened [Organ.Auto] in
      let tf, _ = answered t (Error err) in
      let tr, cmds = Layer.step tf Layer.Retry in
      let label = Failure.show (Failure.of_error ~no_reject:false err) in
      match reasks with
      | true ->
          Alcotest.(check int)
            (Printf.sprintf "%s: seq + 1" label)
            (tf.seq + 1) tr.seq;
          Alcotest.(check commands_t)
            (Printf.sprintf "%s: re-ask" label)
            [
              Layer.Send {seq = tr.seq; request = Layer.request tr};
              Layer.Wait_slow {seq = tr.seq; ms = Layer.slow_ms};
            ]
            cmds
      | false ->
          Alcotest.(check state_t) (Printf.sprintf "%s: unchanged" label) tf tr;
          Alcotest.(check commands_t)
            (Printf.sprintf "%s: no command" label)
            [] cmds)
    [
      (Failure.Plantnet Plantnet.Key_not_exposed, true);
      (Failure.Not_sent_offline, true);
      (Failure.Plantnet Plantnet.Quota_used_up, false);
      (Failure.Plantnet Plantnet.Key_refused, false);
      (Failure.Plantnet Plantnet.No_key, false);
      (Failure.Preview_unreadable, false);
      (Failure.Plantnet Plantnet.No_plant, false);
    ]

let retake_and_keep_unnamed_tests () =
  let t, _ = opened [Organ.Auto] in
  let tf, _ = answered t (Error (Failure.Plantnet Plantnet.Quota_used_up)) in
  let tr, cmds = Layer.step tf Layer.Retake in
  Alcotest.(check phase_t)
    "Noter: Retake -> Closed Retake" (Layer.Closed Layer.Retake) tr.phase;
  Alcotest.(check commands_t) "[Close Retake]" [Layer.Close Layer.Retake] cmds;
  let tk, cmds2 = Layer.step tf Layer.Keep_unnamed in
  Alcotest.(check phase_t)
    "Noter: Keep_unnamed -> Closed Keep_unnamed"
    (Layer.Closed Layer.Keep_unnamed) tk.phase;
  Alcotest.(check commands_t)
    "[Close Keep_unnamed]"
    [Layer.Close Layer.Keep_unnamed]
    cmds2;
  let tp, _ = answered t (Ok (Lazy.force uncertain)) in
  let tpr, cmds_p = Layer.step tp Layer.Retake in
  Alcotest.(check state_t) "Noter: Retake while Proposals unchanged" tp tpr;
  Alcotest.(check commands_t) "no command" [] cmds_p;
  let tq, _ =
    opened ~caller:(Caller.Queue {index = 1; total = 1}) [Organ.Auto]
  in
  let tqf, _ = answered tq (Error (Failure.Plantnet Plantnet.Quota_used_up)) in
  let tqr, cmds3 = Layer.step tqf Layer.Retake in
  Alcotest.(check state_t) "Queue: Retake unchanged" tqf tqr;
  Alcotest.(check commands_t) "no command" [] cmds3;
  let tqk, cmds4 = Layer.step tqf Layer.Keep_unnamed in
  Alcotest.(check state_t) "Queue: Keep_unnamed unchanged" tqf tqk;
  Alcotest.(check commands_t) "no command" [] cmds4;
  let tn, _ =
    opened ~caller:(Caller.Free_name (Plant_id.fresh ())) [Organ.Auto]
  in
  let tnf, _ = answered tn (Error (Failure.Plantnet Plantnet.Quota_used_up)) in
  List.iter
    (fun (name, ev) ->
      let t2, cmds = Layer.step tnf ev in
      Alcotest.(check state_t) ("Free_name: " ^ name ^ " unchanged") tnf t2;
      Alcotest.(check commands_t) "no command" [] cmds)
    [("Retake", Layer.Retake); ("Keep_unnamed", Layer.Keep_unnamed)]

(* No request without a tap: a representative set of reachable states (open,
   Sending, Proposals certain/uncertain, Failed per a few error classes,
   Closed), checked against events that must never emit a [Send], and
   against the re-ask events, each cell with its exact count. *)
let no_request_without_a_tap () =
  let send_count cmds =
    List.length
      (List.filter (function Layer.Send _ -> true | _ -> false) cmds)
  in
  let sending, _ = opened [Organ.Auto] in
  let proposals_certain, _ =
    answered (fst (opened [Organ.Auto; Organ.Auto])) (Ok (Lazy.force certain))
  in
  let proposals_uncertain, _ = answered sending (Ok (Lazy.force uncertain)) in
  let failed_no_plant, _ =
    answered sending
      (Ok (identified_of (answer_of ~proposals:[] ~detected:[None] ())))
  in
  let failed_not_answered, _ =
    answered sending (Error (Failure.Plantnet Plantnet.Key_not_exposed))
  in
  let failed_offline, _ = answered sending (Error Failure.Not_sent_offline) in
  let failed_used_up, _ =
    answered sending (Error (Failure.Plantnet Plantnet.Quota_used_up))
  in
  let closed, _ = Layer.step sending Layer.Back in
  let states =
    [
      ("Sending", sending);
      ("Proposals certain", proposals_certain);
      ("Proposals uncertain", proposals_uncertain);
      ("Failed No_plant", failed_no_plant);
      ("Failed Not_answered", failed_not_answered);
      ("Failed Offline", failed_offline);
      ("Failed Used_up", failed_used_up);
      ("Closed", closed);
    ]
  in
  let never_send_events =
    [
      ("Slow 1", Layer.Slow 1);
      ("Slow 999 (stale)", Layer.Slow 999);
      ("Answered", Layer.Answered {seq = 1; result = Ok (Lazy.force uncertain)});
      ("Choose 0", Layer.Choose 0);
      ("Choose 5 (out of range)", Layer.Choose 5);
      ("None_matches", Layer.None_matches);
      ("Back", Layer.Back);
      ("Add", Layer.Add);
      ("Photo_added None", Layer.Photo_added None);
      ("Retake", Layer.Retake);
      ("Keep_unnamed", Layer.Keep_unnamed);
    ]
  in
  List.iter
    (fun (state_name, state) ->
      List.iter
        (fun (ev_name, ev) ->
          let _, cmds = Layer.step state ev in
          Alcotest.(check int)
            (Printf.sprintf "%s + %s: no Send" state_name ev_name)
            0 (send_count cmds))
        never_send_events)
    states;
  (* Fruit: an organ neither fixture detects, so Set_organ changes it. *)
  let reask_events =
    [
      ("Set_organ", Layer.Set_organ {photo = 0; organ = Organ.Fruit});
      ( "Photo_added (Some _)",
        Layer.Photo_added (Some (Organ.Given Organ.Fruit)) );
      ("Set_flora (changing)", Layer.Set_flora (Some flora_so));
      ("Force", Layer.Force);
      ("Retry", Layer.Retry);
    ]
  in
  (* The cells that send exactly one request; every other one sends none and
     emits no command at all (no Save_flora either). *)
  let sends = function
    | ( ("Proposals certain" | "Proposals uncertain"),
        ("Set_organ" | "Photo_added (Some _)" | "Set_flora (changing)") ) ->
        true
    | ( ("Failed No_plant" | "Failed Not_answered" | "Failed Offline"),
        "Photo_added (Some _)" ) ->
        true
    | "Failed No_plant", "Force" -> true
    | ("Failed Not_answered" | "Failed Offline"), "Retry" -> true
    | (_ : string), (_ : string) -> false
  in
  List.iter
    (fun (state_name, state) ->
      List.iter
        (fun (ev_name, ev) ->
          let _, cmds = Layer.step state ev in
          let label = Printf.sprintf "%s + %s" state_name ev_name in
          match sends (state_name, ev_name) with
          | true ->
              Alcotest.(check int) (label ^ ": one Send") 1 (send_count cmds)
          | false -> Alcotest.(check commands_t) (label ^ ": nothing") [] cmds)
        reask_events)
    states

let add_tile_fn_tests () =
  let proposals_certain, _ =
    answered (fst (opened [Organ.Auto; Organ.Auto])) (Ok (Lazy.force certain))
  in
  Alcotest.(check suggestion_opt_t)
    "Proposals -> Organ.suggest of the effective organs"
    (Organ.suggest (Layer.effective_organs proposals_certain))
    (Layer.add_tile proposals_certain);
  let failed_no_plant, _ =
    answered
      (fst (opened [Organ.Auto]))
      (Ok (identified_of (answer_of ~proposals:[] ~detected:[None] ())))
  in
  Alcotest.(check suggestion_opt_t)
    "Failed (No_plant _) -> Some Add_photo" (Some Organ.Add_photo)
    (Layer.add_tile failed_no_plant);
  let failed_used_up, _ =
    answered
      (fst (opened [Organ.Auto]))
      (Error (Failure.Plantnet Plantnet.Quota_used_up))
  in
  Alcotest.(check suggestion_opt_t)
    "Failed Used_up -> None" None
    (Layer.add_tile failed_used_up);
  let five = List.init 5 (fun _ -> Organ.Auto) in
  let five_proposals, _ =
    answered
      (fst (opened five))
      (Ok (identified_of (answer_of ~detected:(List.init 5 (fun _ -> None)) ())))
  in
  Alcotest.(check suggestion_opt_t)
    "5 photos -> None" None
    (Layer.add_tile five_proposals);
  let sending, _ = opened [Organ.Auto] in
  Alcotest.(check suggestion_opt_t)
    "Sending -> None" None (Layer.add_tile sending)

let layer_tests =
  [
    Alcotest.test_case
      "open_: Sending/seq 1/commands, flora, 7 organs kept to 5, [] -> Closed \
       Left"
      `Quick open_tests;
    Alcotest.test_case
      "Slow: sets slow on the matching seq, ignores a stale or non-Sending one"
      `Quick slow_tests;
    Alcotest.test_case
      "Answered Ok: Proposals/uncertain, detected, padding and truncation to \
       the organs length"
      `Quick answered_ok_tests;
    Alcotest.test_case
      "Answered: a stale seq or a settled phase changes nothing" `Quick
      answered_stale_or_settled_tests;
    Alcotest.test_case
      "Answered Ok with no proposal -> Failed (No_plant {can_force = true})"
      `Quick answered_empty_proposals_tests;
    Alcotest.test_case
      "Answered Error: each error -> Failed (Failure.of_error ...), \
       Key_not_exposed -> Not_answered"
      `Quick answered_error_tests;
    Alcotest.test_case
      "Choose: in range closes with Chosen, out of range or outside Proposals \
       is unchanged"
      `Quick choose_tests;
    Alcotest.test_case
      "None_matches: closes from Proposals, unchanged elsewhere" `Quick
      none_matches_tests;
    Alcotest.test_case
      "effective_organs: the given organ, else the detected one, else unknown"
      `Quick effective_organs_tests;
    Alcotest.test_case
      "Back closes with Left from any phase; events after Closed change nothing"
      `Quick back_tests;
    Alcotest.test_case
      "Set_organ: a changed organ re-asks, the same organ or an out-of-range \
       photo does not"
      `Quick set_organ_tests;
    Alcotest.test_case
      "Add: the suggested organ's Take_photo, or none past 5 photos or where \
       re-asking cannot help"
      `Quick add_tile_tests;
    Alcotest.test_case
      "Photo_added: a new photo re-asks from Proposals or a re-askable \
       failure; None, past 5 photos or a blocked failure changes nothing"
      `Quick photo_added_tests;
    Alcotest.test_case
      "A photo being taken: a second Add or a re-ask waits for Photo_added"
      `Quick taking_tests;
    Alcotest.test_case
      "accepts_photo: Proposals or a re-askable failure with room" `Quick
      accepts_photo_tests;
    Alcotest.test_case
      "Set_flora: a changed flora saves and re-asks with that id; unchanged \
       otherwise"
      `Quick set_flora_tests;
    Alcotest.test_case
      "Force: sets no_reject and re-asks; a second Force after can_force turns \
       false is unchanged"
      `Quick force_tests;
    Alcotest.test_case
      "A re-ask after a forced request resets no_reject; Retry keeps it" `Quick
      no_reject_reset_tests;
    Alcotest.test_case "Retry: re-asks only where Failure.retry is true" `Quick
      retry_tests;
    Alcotest.test_case
      "Retake/Keep_unnamed: close for Noter, unchanged for Queue" `Quick
      retake_and_keep_unnamed_tests;
    Alcotest.test_case
      "No request without a tap, over a scripted walk of states" `Quick
      no_request_without_a_tap;
    Alcotest.test_case
      "add_tile: Organ.suggest in Proposals, Add_photo for No_plant, None past \
       5 photos or where it cannot help"
      `Quick add_tile_fn_tests;
  ]

(* ============================================================ *)
(* Text *)
(* ============================================================ *)

let constants_tests () =
  Alcotest.(check string) "title" "Identification" Text.title;
  Alcotest.(check string) "back_label" "Retour" Text.back_label;
  Alcotest.(check string) "sending" "Envoi à Pl@ntNet…" Text.sending;
  Alcotest.(check string) "skeleton_label" "Pl@ntNet…" Text.skeleton_label;
  Alcotest.(check string) "continue_" "Continuer sans attendre" Text.continue_;
  Alcotest.(check string)
    "none_matches" "Aucune ne correspond" Text.none_matches;
  Alcotest.(check string)
    "organ_menu_label" "Organe de la photo" Text.organ_menu_label;
  Alcotest.(check string)
    "flora_menu_label" "Flore Pl@ntNet" Text.flora_menu_label;
  Alcotest.(check string) "retry" "Réessayer" Text.retry;
  Alcotest.(check string)
    "force" "Voir quand même les propositions peu probables" Text.force;
  Alcotest.(check string) "retake" "Reprendre la photo" Text.retake

let not_kept_and_keep_unnamed_tests () =
  Alcotest.(check string)
    "not_kept, 1 photo" "Pl@ntNet ne conserve pas la photo."
    (Text.not_kept ~photos:1);
  Alcotest.(check string)
    "not_kept, 2 photos" "Pl@ntNet ne conserve pas les photos."
    (Text.not_kept ~photos:2);
  Alcotest.(check string)
    "keep_unnamed, 1 photo" "Garder la photo, sans nom"
    (Text.keep_unnamed ~photos:1);
  Alcotest.(check string)
    "keep_unnamed, 2 photos" "Garder les photos, sans nom"
    (Text.keep_unnamed ~photos:2)

let kicker_tests () =
  Alcotest.(check string) "Noter" "Pl@ntNet" (Text.kicker Caller.Noter);
  Alcotest.(check string)
    "Free_name" "Pl@ntNet"
    (Text.kicker (Caller.Free_name (Plant_id.fresh ())));
  Alcotest.(check string)
    "Queue" "À identifier · 1 / 3"
    (Text.kicker (Caller.Queue {index = 1; total = 3}))

let proposals_label_tests () =
  Alcotest.(check string)
    "Noter, None" "Propositions"
    (Text.proposals_label Caller.Noter ~count:None);
  Alcotest.(check string)
    "Noter, Some 5" "Propositions · 5"
    (Text.proposals_label Caller.Noter ~count:(Some 5));
  let queue = Caller.Queue {index = 1; total = 3} in
  Alcotest.(check string)
    "Queue, None" "Propositions Pl@ntNet"
    (Text.proposals_label queue ~count:None);
  Alcotest.(check string)
    "Queue, Some 5" "Propositions Pl@ntNet · 5"
    (Text.proposals_label queue ~count:(Some 5))

let flora_label_tests () =
  Alcotest.(check string)
    "None -> Automatique" "Automatique" (Text.flora_label None);
  Alcotest.(check string)
    "Some f -> f.title" "Europe du Sud-Ouest"
    (Text.flora_label (Some flora_so))

let percent_tests () =
  Alcotest.(check string) "0.44239" "44 %" (Text.percent 0.44239);
  Alcotest.(check string)
    "0.00355 (tiny, positive)" "< 1 %" (Text.percent 0.00355);
  Alcotest.(check string) "0." "0 %" (Text.percent 0.);
  Alcotest.(check string) "1." "100 %" (Text.percent 1.);
  Alcotest.(check string) "0.82" "82 %" (Text.percent 0.82);
  Alcotest.(check string) "negative clamped to 0" "0 %" (Text.percent (-0.5));
  Alcotest.(check string) "1.5 clamped to 100" "100 %" (Text.percent 1.5);
  Alcotest.(check string) "0.005 rounds up" "1 %" (Text.percent 0.005);
  Alcotest.(check string) "0.004 shows < 1 %" "< 1 %" (Text.percent 0.004)

let bar_width_tests () =
  Alcotest.(check string) "0.44239" "44.2%" (Text.bar_width 0.44239);
  Alcotest.(check string) "1.5 clamped to 1" "100%" (Text.bar_width 1.5);
  Alcotest.(check string) "-1 clamped to 0" "0%" (Text.bar_width (-1.))

let common_names_tests () =
  let p0 = first_proposal (Lazy.force certain_answer) in
  Alcotest.(check (option string))
    "joined by \" · \", decoded order"
    (Some "Rose de Chine · Hibiscus · Hibiscus rose de Chine")
    (Text.common_names p0);
  Alcotest.(check (option string))
    "[] -> None" None
    (Text.common_names {p0 with common_names = []})

let organ_badge_and_tile_organ_tests () =
  Alcotest.(check string)
    "Some Flower" "fleur ▾"
    (Text.organ_badge (Some Organ.Flower));
  Alcotest.(check string) "None" "organe ▾" (Text.organ_badge None);
  Alcotest.(check (option string))
    "Some" (Some "fleur")
    (Text.tile_organ (Some Organ.Flower));
  Alcotest.(check (option string)) "None" None (Text.tile_organ None)

let add_hint_tests () =
  Alcotest.(check string)
    "Add Flower" "Une fleur en plus départage les espèces proches."
    (Text.add_hint (Organ.Add Organ.Flower));
  Alcotest.(check string)
    "Add Leaf" "Une feuille en plus départage les espèces proches."
    (Text.add_hint (Organ.Add Organ.Leaf));
  Alcotest.(check string)
    "Add Fruit" "Un fruit en plus départage les espèces proches."
    (Text.add_hint (Organ.Add Organ.Fruit));
  Alcotest.(check string)
    "Add Bark" "L'écorce en plus départage les espèces proches."
    (Text.add_hint (Organ.Add Organ.Bark));
  Alcotest.(check string)
    "Add Habit" "Le port en plus départage les espèces proches."
    (Text.add_hint (Organ.Add Organ.Habit));
  Alcotest.(check string)
    "Add_photo" "Une photo en plus départage les espèces proches."
    (Text.add_hint Organ.Add_photo)

let owned_and_action_tests () =
  let p = Fixtures.plant_with () in
  let o : Owned.t = {plant = p; observations = 2} in
  Alcotest.(check string)
    "owned, 2 obs."
    (Printf.sprintf "Dans ma collection · %s · 2 obs." p.display_name)
    (Text.owned o);
  Alcotest.(check string) "action Choose" "Choisir" (Text.action Caller.Choose);
  Alcotest.(check string) "action Link" "Lier" (Text.action Caller.Link);
  Alcotest.(check string) "action Create" "+ Créer" (Text.action Caller.Create)

let failure_title_and_body_tests () =
  Alcotest.(check string)
    "No_plant title" "Aucune plante reconnue"
    (Text.failure_title (Failure.No_plant {can_force = true}));
  Alcotest.(check string)
    "Not_answered title" "Pl@ntNet n'a pas répondu"
    (Text.failure_title Failure.Not_answered);
  Alcotest.(check string)
    "Offline title" "Hors-ligne"
    (Text.failure_title Failure.Offline);
  Alcotest.(check string)
    "Used_up title" "Quota du jour atteint"
    (Text.failure_title Failure.Used_up);
  Alcotest.(check string)
    "Key_refused title" "Clé API refusée"
    (Text.failure_title Failure.Key_refused);
  Alcotest.(check string)
    "No_key title" "Aucune clé API"
    (Text.failure_title Failure.No_key);
  Alcotest.(check string)
    "Unreadable title" "Photo illisible"
    (Text.failure_title Failure.Unreadable);
  Alcotest.(check string)
    "No_plant body, 1 photo" "Pas de plante détectée sur cette photo."
    (Text.failure_body ~photos:1 (Failure.No_plant {can_force = true}));
  Alcotest.(check string)
    "No_plant body, 2 photos" "Pas de plante détectée sur ces photos."
    (Text.failure_body ~photos:2 (Failure.No_plant {can_force = false}));
  Alcotest.(check string)
    "Not_answered body" "Réessayez dans un moment."
    (Text.failure_body ~photos:1 Failure.Not_answered);
  Alcotest.(check string)
    "Offline body" "Rien n'a été envoyé : réessayez avec le réseau."
    (Text.failure_body ~photos:1 Failure.Offline);
  Alcotest.(check string)
    "Used_up body"
    "Les 500 identifications Pl@ntNet du jour sont utilisées : réessayez \
     demain."
    (Text.failure_body ~photos:1 Failure.Used_up);
  Alcotest.(check string)
    "Key_refused body" "Pl@ntNet a refusé la clé : vérifiez-la dans Réglages."
    (Text.failure_body ~photos:1 Failure.Key_refused);
  Alcotest.(check string)
    "No_key body is Identify_settings.no_key_line" Is.no_key_line
    (Text.failure_body ~photos:1 Failure.No_key);
  Alcotest.(check string)
    "Unreadable body"
    "Une photo n'a pas pu être lue sur le téléphone : rien n'a été envoyé."
    (Text.failure_body ~photos:1 Failure.Unreadable)

let pinned_key_not_exposed_shown_as_unreachable () =
  let a =
    Failure.of_error ~no_reject:false
      (Failure.Plantnet Plantnet.Key_not_exposed)
  in
  let b =
    Failure.of_error ~no_reject:false
      (Failure.Plantnet (Plantnet.Unreachable (Plantnet.Server 503)))
  in
  Alcotest.(check string)
    "same title as an unreachable Pl@ntNet" (Text.failure_title b)
    (Text.failure_title a);
  Alcotest.(check string)
    "same body as an unreachable Pl@ntNet"
    (Text.failure_body ~photos:1 b)
    (Text.failure_body ~photos:1 a)

let reask_blocked_tests () =
  let key = ready_key () in
  Alcotest.(check (option string))
    "Ready: None" None
    (Text.reask_blocked (Is.Ready key));
  Alcotest.(check (option string))
    "Offline: the offline line"
    (Some "Hors-ligne : rien ne peut être envoyé à Pl@ntNet.")
    (Text.reask_blocked Is.Offline);
  Alcotest.(check (option string))
    "No_key: Identify_settings.no_key_line" (Some Is.no_key_line)
    (Text.reask_blocked Is.No_key);
  Alcotest.(check (option string))
    "Waiting: None (disabled, no line)" None
    (Text.reask_blocked Is.Waiting)

let no_forbidden_wording_tests () =
  let forbidden = ["cors"; "origin"; "localhost"; "expos"; "api-key"] in
  let check_text msg text =
    let lower = String.lowercase_ascii text in
    List.iter
      (fun bad ->
        Alcotest.(check bool)
          (Printf.sprintf "%s: no %S" msg bad)
          false
          (Support_text.contains ~sub:bad lower))
      forbidden
  in
  let failures =
    [
      Failure.No_plant {can_force = true};
      Failure.No_plant {can_force = false};
      Failure.Not_answered;
      Failure.Offline;
      Failure.Used_up;
      Failure.Key_refused;
      Failure.No_key;
      Failure.Unreadable;
    ]
  in
  List.iter
    (fun f ->
      check_text ("failure_title " ^ Failure.show f) (Text.failure_title f);
      check_text
        ("failure_body ~photos:1 " ^ Failure.show f)
        (Text.failure_body ~photos:1 f);
      check_text
        ("failure_body ~photos:2 " ^ Failure.show f)
        (Text.failure_body ~photos:2 f))
    failures;
  let callers =
    [
      Caller.Noter;
      Caller.Queue {index = 1; total = 3};
      Caller.Free_name (Plant_id.fresh ());
    ]
  in
  List.iter
    (fun c ->
      check_text "kicker" (Text.kicker c);
      check_text "proposals_label ~count:None"
        (Text.proposals_label c ~count:None);
      check_text "proposals_label ~count:(Some 3)"
        (Text.proposals_label c ~count:(Some 3)))
    callers;
  let key = ready_key () in
  let gates = [Is.Ready key; Is.Waiting; Is.No_key; Is.Offline] in
  List.iter
    (fun g ->
      match Text.reask_blocked g with
      | None -> ()
      | Some s -> check_text "reask_blocked" s)
    gates;
  let suggestions =
    [
      Organ.Add Organ.Flower;
      Organ.Add Organ.Leaf;
      Organ.Add Organ.Fruit;
      Organ.Add Organ.Bark;
      Organ.Add Organ.Habit;
      Organ.Add_photo;
    ]
  in
  List.iter (fun s -> check_text "add_hint" (Text.add_hint s)) suggestions;
  List.iter
    (fun (name, text) -> check_text name text)
    [
      ("title", Text.title);
      ("back_label", Text.back_label);
      ("sending", Text.sending);
      ("not_kept 1", Text.not_kept ~photos:1);
      ("not_kept 2", Text.not_kept ~photos:2);
      ("skeleton_label", Text.skeleton_label);
      ("continue_", Text.continue_);
      ("flora_label None", Text.flora_label None);
      ("organ_badge None", Text.organ_badge None);
      ("action Choose", Text.action Caller.Choose);
      ("action Link", Text.action Caller.Link);
      ("action Create", Text.action Caller.Create);
      ("none_matches", Text.none_matches);
      ("organ_menu_label", Text.organ_menu_label);
      ("flora_menu_label", Text.flora_menu_label);
      ("retry", Text.retry);
      ("force", Text.force);
      ("retake", Text.retake);
      ("keep_unnamed 1", Text.keep_unnamed ~photos:1);
      ("keep_unnamed 2", Text.keep_unnamed ~photos:2);
    ];
  List.iter
    (fun o -> check_text "organ_badge" (Text.organ_badge (Some o)))
    Organ.all

let text_tests =
  [
    Alcotest.test_case "constant texts" `Quick constants_tests;
    Alcotest.test_case "not_kept and keep_unnamed: singular/plural" `Quick
      not_kept_and_keep_unnamed_tests;
    Alcotest.test_case "kicker: Pl@ntNet, or the queue's index / total" `Quick
      kicker_tests;
    Alcotest.test_case "proposals_label: the four Caller × count cases" `Quick
      proposals_label_tests;
    Alcotest.test_case "flora_label: None is Automatique, Some f is f.title"
      `Quick flora_label_tests;
    Alcotest.test_case
      "percent: rounding, clamping, and \"< 1 %\" for a tiny positive score"
      `Quick percent_tests;
    Alcotest.test_case "bar_width: at most one decimal, clamped to [0, 1]"
      `Quick bar_width_tests;
    Alcotest.test_case
      "common_names: joined by \" · \" in decoded order, [] -> None" `Quick
      common_names_tests;
    Alcotest.test_case "organ_badge and tile_organ" `Quick
      organ_badge_and_tile_organ_tests;
    Alcotest.test_case "add_hint: every suggestion's hint" `Quick add_hint_tests;
    Alcotest.test_case "owned and action texts" `Quick owned_and_action_tests;
    Alcotest.test_case "failure_title and failure_body: every Failure.t" `Quick
      failure_title_and_body_tests;
    Alcotest.test_case
      "pinned: Key_not_exposed shows the same title/body as an unreachable \
       Pl@ntNet (user decision)"
      `Quick pinned_key_not_exposed_shown_as_unreachable;
    Alcotest.test_case "reask_blocked: Ready/Offline/No_key/Waiting" `Quick
      reask_blocked_tests;
    Alcotest.test_case
      "no text ever names cors/origin/localhost/exposing/the api-key \
       parameter, over every Failure.t, both photo counts, every Caller.t, \
       every gate and every suggestion"
      `Quick no_forbidden_wording_tests;
  ]

(* ============================================================ *)

let identify =
  List.concat
    [caller_tests; owned_tests; failure_tests; layer_tests; text_tests]
