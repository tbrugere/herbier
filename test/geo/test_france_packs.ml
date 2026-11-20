(* France_packs: the « Toute la France » plan (what to download, in
   which order, the size estimate) and the run (a functor over a fake IO:
   order, skip-present, retry/backoff, cancel) and the failure classes. No
   Brr; native. *)

module Communes = Herbier_geo.Communes
module Geocode = Herbier_geo.Geocode
module Code = Communes.Code
module France_packs = Herbier_geo.France_packs
module France_sizes = Herbier_geo.France_sizes
module Fixture = Herbier_test_support.Fixture

let code s =
  match Code.of_string s with
  | Some c -> c
  | None -> failwith (s ^ " is not a département code")

let d code_s name : Communes.departement = {code = code code_s; name}

let codes ds =
  List.map (fun (dep : Communes.departement) -> Code.to_string dep.code) ds

(* ---------- fixtures (same plumbing as test_communes.ml) ---------- *)

let json_fixture name =
  match Geocode.json_of_string (Fixture.read name) with
  | Ok j -> j
  | Error e -> failwith (name ^ ": " ^ Geocode.error_to_string e)

let departements_json =
  lazy (json_fixture "geoplateforme_wfs_departements.json")

let departements_list =
  lazy
    (match Communes.departements (Lazy.force departements_json) with
    | Ok ds -> ds
    | Error e -> failwith ("departements: " ^ Geocode.error_to_string e))

let communes_90_json = lazy (json_fixture "geoplateforme_wfs_communes_90.json")

let pack_90 =
  lazy
    (match
       Communes.pack_of_payload ~departement:(code "90")
         (Lazy.force communes_90_json)
     with
    | Ok p -> p
    | Error e -> failwith ("pack_of_payload 90: " ^ Geocode.error_to_string e))

let pack_976 =
  lazy
    (match
       Communes.pack_of_payload ~departement:(code "976")
         (json_fixture "geoplateforme_wfs_communes_976.json")
     with
    | Ok p -> p
    | Error e -> failwith ("pack_of_payload 976: " ^ Geocode.error_to_string e))

(* ---------- testables ---------- *)

let plan_testable =
  Alcotest.testable
    (fun f (p : France_packs.plan) ->
      Format.fprintf f
        "{total=%d; present=%d; estimate_bytes=%d; transfer_bytes=%d; \
         todo=[%s]; departements=[%s]}"
        p.total p.present p.estimate_bytes p.transfer_bytes
        (String.concat "," (codes p.todo))
        (String.concat "," (codes p.departements)))
    France_packs.equal_plan

(* ---------- backoff_ms ---------- *)

let backoff_ms_is_5_20_60_seconds () =
  Alcotest.(check (list int))
    "backoff_ms" [5_000; 20_000; 60_000] France_packs.backoff_ms

(* ---------- plan ---------- *)

let plan_full_scope_all_todo () =
  let list = Lazy.force departements_list in
  let p = France_packs.plan ~downloaded:[] list in
  Alcotest.(check int) "total" 101 p.total;
  Alcotest.(check int) "present" 0 p.present;
  Alcotest.(check (list string))
    "todo = the list, order kept" (codes list) (codes p.todo);
  (match p.todo with
  | first :: _ ->
      Alcotest.(check string) "first" "01" (Code.to_string first.code)
  | [] -> Alcotest.fail "expected a non-empty todo");
  (match List.rev p.todo with
  | last :: _ -> Alcotest.(check string) "last" "976" (Code.to_string last.code)
  | [] -> Alcotest.fail "expected a non-empty todo");
  List.iter
    (fun c ->
      Alcotest.(check bool)
        (Printf.sprintf "contains %s" c)
        true
        (List.mem c (codes p.todo)))
    ["2A"; "2B"; "971"; "972"; "973"; "974"; "976"];
  (* 52,9 Mo stored, 65,7 Mo gzip for the whole list, as France_sizes measured
     them on measured_on. *)
  Alcotest.(check int) "estimate_bytes" 52_923_990 p.estimate_bytes;
  Alcotest.(check int) "transfer_bytes" 65_729_719 p.transfer_bytes

let plan_with_some_downloaded () =
  let list = Lazy.force departements_list in
  let full = France_packs.plan ~downloaded:[] list in
  let downloaded = [code "90"; code "68"; code "62"] in
  let p = France_packs.plan ~downloaded list in
  Alcotest.(check int) "present" 3 p.present;
  Alcotest.(check int) "total" 101 p.total;
  List.iter
    (fun c ->
      Alcotest.(check bool)
        (Printf.sprintf "%s absent from todo" (Code.to_string c))
        false
        (List.mem (Code.to_string c) (codes p.todo)))
    downloaded;
  Alcotest.(check (list string))
    "the rest, in order"
    (List.filter
       (fun c -> not (List.mem c (List.map Code.to_string downloaded)))
       (codes list))
    (codes p.todo);
  let removed_estimate =
    List.fold_left
      (fun acc c -> acc + France_packs.estimated_bytes c)
      0 downloaded
  in
  Alcotest.(check int)
    "estimate_bytes = previous - removed"
    (full.estimate_bytes - removed_estimate)
    p.estimate_bytes

let plan_downloaded_code_outside_list () =
  let list = Lazy.force departements_list in
  let p = France_packs.plan ~downloaded:[code "975"] list in
  Alcotest.(check int) "present unchanged" 0 p.present

let plan_only_with_downloaded () =
  let list = Lazy.force departements_list in
  let p =
    France_packs.plan
      ~only:[code "90"; code "68"]
      ~downloaded:[code "62"; code "90"]
      list
  in
  Alcotest.(check int) "total = 2" 2 p.total;
  Alcotest.(check int) "present = 1 (62 is outside only)" 1 p.present;
  Alcotest.(check (list string)) "todo = [68]" ["68"] (codes p.todo);
  Alcotest.(check int)
    "estimate_bytes = 68's"
    (France_packs.estimated_bytes (code "68"))
    p.estimate_bytes

let plan_only () =
  let list = Lazy.force departements_list in
  let p =
    France_packs.plan
      ~only:[code "976"; code "90"; code "68"]
      ~downloaded:[] list
  in
  Alcotest.(check (list string))
    "departements = 68, 90, 976 (list order, not only's)" ["68"; "90"; "976"]
    (codes p.departements);
  Alcotest.(check int) "total = 3" 3 p.total;
  let p975 = France_packs.plan ~only:[code "975"] ~downloaded:[] list in
  Alcotest.(check int) "975 absent: total = 0" 0 p975.total;
  Alcotest.(check (list string)) "todo = []" [] (codes p975.todo);
  Alcotest.(check int) "estimate_bytes = 0" 0 p975.estimate_bytes

let plan_all_downloaded () =
  let list = Lazy.force departements_list in
  let downloaded =
    List.map (fun (dep : Communes.departement) -> dep.code) list
  in
  let p = France_packs.plan ~downloaded list in
  Alcotest.(check (list string)) "todo = []" [] (codes p.todo);
  Alcotest.(check int) "present = total" p.total p.present;
  Alcotest.(check int) "estimate_bytes = 0" 0 p.estimate_bytes

let plan_resume_equal () =
  let list = Lazy.force departements_list in
  let full = France_packs.plan ~downloaded:[] list in
  let a = code "01" and b = code "02" in
  Alcotest.(check plan_testable)
    "plan ~downloaded:[a;b] over p.departements = over the original list"
    (France_packs.plan ~downloaded:[a; b] list)
    (France_packs.plan ~downloaded:[a; b] full.departements)

let estimated_bytes_matches_table () =
  List.iter
    (fun (code_s, bytes) ->
      Alcotest.(check int)
        (Printf.sprintf "estimated_bytes %s" code_s)
        bytes
        (France_packs.estimated_bytes (code code_s)))
    France_sizes.table;
  Alcotest.(check int)
    "975 (absent from the table) -> fallback_bytes" France_packs.fallback_bytes
    (France_packs.estimated_bytes (code "975"));
  (* France_sizes median: 533 ko (10, the 51st of 101). *)
  Alcotest.(check int)
    "fallback_bytes is the table's median" 533_169 France_packs.fallback_bytes;
  List.iter
    (fun (code_s, bytes) ->
      Alcotest.(check int)
        (Printf.sprintf "transfer_bytes %s" code_s)
        bytes
        (France_packs.transfer_bytes (code code_s)))
    France_sizes.transfer;
  Alcotest.(check int)
    "975: fallback_bytes scaled by transfer / stored"
    (Float.to_int (533_169. *. 65_729_719. /. 52_923_990.))
    (France_packs.transfer_bytes (code "975"))

let is_date_shape s =
  let digits a b =
    String.length s >= b
    && String.for_all (fun c -> c >= '0' && c <= '9') (String.sub s a (b - a))
  in
  String.length s = 10
  && digits 0 4
  && Char.equal s.[4] '-'
  && digits 5 7
  && Char.equal s.[7] '-'
  && digits 8 10

let france_sizes_table_well_formed () =
  let list = Lazy.force departements_list in
  Alcotest.(check (list string))
    "codes = the fixture list's codes, same order" (codes list)
    (List.map fst France_sizes.table);
  Alcotest.(check (list string))
    "sorted"
    (List.sort String.compare (List.map fst France_sizes.table))
    (List.map fst France_sizes.table);
  let seen = Hashtbl.create 101 in
  List.iter
    (fun (c, _) ->
      Alcotest.(check bool)
        (Printf.sprintf "%s unique" c)
        false (Hashtbl.mem seen c);
      Hashtbl.replace seen c ())
    France_sizes.table;
  List.iter
    (fun (c, bytes) ->
      Alcotest.(check bool)
        (Printf.sprintf "%s is a département code" c)
        true
        (Option.is_some (Code.of_string c));
      Alcotest.(check bool) (Printf.sprintf "%s bytes > 0" c) true (bytes > 0))
    France_sizes.table;
  Alcotest.(check bool)
    "measured_on matches YYYY-MM-DD" true
    (is_date_shape France_sizes.measured_on);
  Alcotest.(check string)
    "France_packs.measured_on = France_sizes.measured_on"
    France_sizes.measured_on France_packs.measured_on;
  Alcotest.(check (list string))
    "transfer: the same codes, same order"
    (List.map fst France_sizes.table)
    (List.map fst France_sizes.transfer);
  List.iter
    (fun (c, bytes) ->
      Alcotest.(check bool) (Printf.sprintf "%s transfer > 0" c) true (bytes > 0))
    France_sizes.transfer;
  (* The fixtures and the table come from the same COG: a table measured
     again (a new COG) means recording these fixtures again. *)
  List.iter
    (fun (code_s, pack) ->
      Alcotest.(check (option int))
        (Printf.sprintf "%s: the table's entry is its fixture's stored size"
           code_s)
        (Some (String.length (Communes.to_string (Lazy.force pack))))
        (List.assoc_opt code_s France_sizes.table))
    [("90", pack_90); ("976", pack_976)]

let plan_tests =
  [
    ( "downloaded = []: todo = the list order-kept, first 01, last 976, \
       overseas included, estimate_bytes sums estimated_bytes",
      `Quick,
      plan_full_scope_all_todo );
    ( "downloaded = [90; 68; 62]: present = 3, those codes dropped, the rest \
       in order, estimate_bytes reduced by their estimated_bytes",
      `Quick,
      plan_with_some_downloaded );
    ( "a downloaded code outside the list (975) changes present not at all",
      `Quick,
      plan_downloaded_code_outside_list );
    ( "only: the list's order wins over only's; an absent valid code gives an \
       empty plan",
      `Quick,
      plan_only );
    ( "only with downloaded: a downloaded code outside only counts for nothing",
      `Quick,
      plan_only_with_downloaded );
    ( "every département downloaded: todo = [], present = total, \
       estimate_bytes = 0",
      `Quick,
      plan_all_downloaded );
    ( "resume: plan over p.departements equals plan over the original list",
      `Quick,
      plan_resume_equal );
    ( "estimated_bytes and transfer_bytes: the tables' own entries, 975's \
       fallback, fallback_bytes is the table's median",
      `Quick,
      estimated_bytes_matches_table );
    ( "France_sizes: one entry per fixture code sorted and unique, all valid \
       codes with positive bytes, transfer on the same codes, measured_on \
       shaped, and the 90 and 976 entries equal to their fixtures' stored size",
      `Quick,
      france_sizes_table_well_formed );
  ]

(* ---------- failure_of_cause ---------- *)

let failure =
  Alcotest.testable
    (fun f e ->
      Format.pp_print_string f
        (match e with
        | France_packs.Transient -> "Transient"
        | Skip -> "Skip"
        | Stop -> "Stop"))
    ( = )

let failure_of_cause_table () =
  List.iter
    (fun (name, cause, expected) ->
      Alcotest.(check failure)
        name expected
        (France_packs.failure_of_cause cause))
    France_packs.
      [
        ("Network", Network, Transient);
        ("Timeout", Timeout, Transient);
        ("Not_json", Not_json, Transient);
        ("429", Status 429, Transient);
        ("500", Status 500, Transient);
        ("503", Status 503, Transient);
        ("599", Status 599, Transient);
        ("401", Status 401, Stop);
        ("403", Status 403, Stop);
        ("400", Status 400, Skip);
        ("404", Status 404, Skip);
        ("600", Status 600, Skip);
        ("Bad_payload", Bad_payload, Skip);
        ("Refused", Refused, Stop);
        ("Local", Local, Stop);
      ]

let failure_tests =
  [
    ( "network, timeout, non-JSON, 429 and 5xx retry; 401, 403, refused and \
       local stop; another status and a bad payload skip",
      `Quick,
      failure_of_cause_table );
  ]

(* ---------- run: a scripted fake over the identity IO ---------- *)

(* The test's own failure classes, mapped to France_packs.failure by
   [classify]. *)
type outcome_e = T | S | X

let classify = function
  | T -> France_packs.Transient
  | S -> France_packs.Skip
  | X -> France_packs.Stop

let outcome_e =
  Alcotest.testable
    (fun f e ->
      Format.pp_print_string f (match e with T -> "T" | S -> "S" | X -> "X"))
    ( = )

(* What a test reads back after [R.run]; [download] pops one answer per call
   from the code's queue, recording the call and (through [on_download])
   letting a test flip [cancelled] mid-call; [sleep] records the wait and
   (through [on_sleep]) does the same for a backoff wait. *)
type state = {
  queues : (string, (int, outcome_e) result list ref) Hashtbl.t;
  calls : string list ref; (* reversed *)
  call_counts : (string, int) Hashtbl.t;
  sleeps : int list ref; (* reversed *)
  sleep_count : int ref;
  reports : outcome_e France_packs.step list ref; (* reversed *)
  cancelled : bool ref;
  on_download : (Communes.departement -> int -> unit) ref;
  on_sleep : (int -> int -> unit) ref;
}

let make_state () =
  {
    queues = Hashtbl.create 8;
    calls = ref [];
    call_counts = Hashtbl.create 8;
    sleeps = ref [];
    sleep_count = ref 0;
    reports = ref [];
    cancelled = ref false;
    on_download = ref (fun _ _ -> ());
    on_sleep = ref (fun _ _ -> ());
  }

let set_answers state code_s answers =
  Hashtbl.replace state.queues code_s (ref answers)

let calls state = List.rev !(state.calls)
let sleeps state = List.rev !(state.sleeps)
let reports state = List.rev !(state.reports)

let pop_answer state code_s =
  match Hashtbl.find_opt state.queues code_s with
  | None -> Alcotest.failf "no queued answers for %s" code_s
  | Some q -> (
      match !q with
      | a :: rest ->
          q := rest;
          a
      | [] -> Alcotest.failf "ran out of queued answers for %s" code_s)

module R = France_packs.Make (struct
  type 'a io = 'a

  let return x = x
  let bind x f = f x

  type ctx = state
  type error = outcome_e

  let download state (dep : Communes.departement) =
    let code_s = Code.to_string dep.code in
    state.calls := code_s :: !(state.calls);
    let n =
      1 + Option.value ~default:0 (Hashtbl.find_opt state.call_counts code_s)
    in
    Hashtbl.replace state.call_counts code_s n;
    !(state.on_download) dep n;
    pop_answer state code_s

  let classify = classify

  let sleep state ~ms =
    state.sleeps := ms :: !(state.sleeps);
    incr state.sleep_count;
    !(state.on_sleep) ms !(state.sleep_count)

  let cancelled state = !(state.cancelled)
  let report state step = state.reports := step :: !(state.reports)
end)

(* One of [R.run]'s reported steps, reduced to what a test checks: the
   département's code, the progress' downloaded, bytes and failed count so
   far, and a retry's numbers. *)
type step_summary =
  | Dl of string * int * int * int
  | Rt of string * int * int * int * int

let summarize = function
  | France_packs.Downloading (p, dep) ->
      Dl
        ( Code.to_string dep.Communes.code,
          p.downloaded,
          p.bytes,
          List.length p.failed )
  | France_packs.Retrying
      {departement; attempt; attempts; wait_ms; progress; error = _} ->
      Rt
        ( Code.to_string departement.Communes.code,
          attempt,
          attempts,
          wait_ms,
          progress.bytes )

let step_summary =
  Alcotest.testable
    (fun f s ->
      Format.pp_print_string f
        (match s with
        | Dl (c, n, b, k) -> Printf.sprintf "Dl(%s,%d,%d,%d)" c n b k
        | Rt (c, a, n, w, b) -> Printf.sprintf "Rt(%s,%d,%d,%d,%d)" c a n w b))
    ( = )

let failed_codes failed =
  List.map (fun (dep, e) -> (Code.to_string dep.Communes.code, e)) failed

let count code_s state =
  List.length (List.filter (String.equal code_s) (calls state))

(* A plan whose todo is exactly [todo]: the rest of [departements] counts as
   downloaded. *)
let run_plan departements todo =
  let in_todo (d : Communes.departement) =
    List.exists
      (fun (t : Communes.departement) -> Code.equal t.code d.code)
      todo
  in
  France_packs.plan
    ~downloaded:
      (List.filter_map
         (fun (d : Communes.departement) ->
           match in_todo d with true -> None | false -> Some d.code)
         departements)
    departements

let d1 = d "01" "Ain"
let d2 = d "02" "Aisne"
let d3 = d "03" "Allier"
let all = run_plan [d1; d2; d3] [d1; d2; d3]

let run_all_ok () =
  let state = make_state () in
  set_answers state "01" [Ok 10];
  set_answers state "02" [Ok 20];
  set_answers state "03" [Ok 30];
  let outcome = R.run state all in
  Alcotest.(check (list string))
    "downloads d1, d2, d3 once each, in order" ["01"; "02"; "03"] (calls state);
  Alcotest.(check (list int)) "no sleep" [] (sleeps state);
  Alcotest.(check (list step_summary))
    "Downloading for d1, d2, d3, with the downloads and bytes so far"
    [Dl ("01", 0, 0, 0); Dl ("02", 1, 10, 0); Dl ("03", 2, 30, 0)]
    (List.map summarize (reports state));
  match outcome with
  | France_packs.Complete p ->
      Alcotest.(check int) "downloaded" 3 p.downloaded;
      Alcotest.(check int) "bytes = the actual sizes, not estimates" 60 p.bytes;
      Alcotest.(check (list (pair string outcome_e)))
        "failed = []" [] (failed_codes p.failed);
      Alcotest.(check int) "position = present + 3" 3 (France_packs.position p)
  | Cancelled _ | Stopped _ -> Alcotest.fail "expected Complete"

let run_skip_present () =
  let state = make_state () in
  set_answers state "01" [Ok 10];
  set_answers state "03" [Ok 30];
  let plan = France_packs.plan ~downloaded:[d2.code] [d1; d2; d3] in
  let outcome = R.run state plan in
  Alcotest.(check (list string))
    "downloads d1 and d3 only" ["01"; "03"] (calls state);
  match outcome with
  | France_packs.Complete p ->
      Alcotest.(check int) "position = 3 = total" 3 (France_packs.position p)
  | Cancelled _ | Stopped _ -> Alcotest.fail "expected Complete"

let run_skip_on_one () =
  let state = make_state () in
  set_answers state "01" [Ok 10];
  set_answers state "02" [Error S];
  set_answers state "03" [Ok 30];
  let outcome = R.run state all in
  Alcotest.(check (list step_summary))
    "d3's report counts d2 as failed"
    [Dl ("01", 0, 0, 0); Dl ("02", 1, 10, 0); Dl ("03", 1, 10, 1)]
    (List.map summarize (reports state));
  match outcome with
  | France_packs.Complete p ->
      Alcotest.(check int) "downloaded = 2" 2 p.downloaded;
      Alcotest.(check int) "bytes = 40: a skipped one adds nothing" 40 p.bytes;
      Alcotest.(check (list (pair string outcome_e)))
        "failed = [(d2, S)]"
        [("02", S)]
        (failed_codes p.failed);
      Alcotest.(check bool)
        "d3 still downloaded" true
        (List.mem "03" (calls state))
  | Cancelled _ | Stopped _ -> Alcotest.fail "expected Complete"

let run_stop_on_one () =
  let state = make_state () in
  set_answers state "01" [Ok 10];
  set_answers state "02" [Error X];
  let outcome = R.run state all in
  Alcotest.(check (list int)) "no sleep" [] (sleeps state);
  Alcotest.(check bool) "d3 never called" false (List.mem "03" (calls state));
  match outcome with
  | France_packs.Stopped (p, e) ->
      Alcotest.(check int) "downloaded = 1" 1 p.downloaded;
      Alcotest.(check (list (pair string outcome_e)))
        "failed = []" [] (failed_codes p.failed);
      Alcotest.(check outcome_e) "error = X" X e
  | Complete _ | Cancelled _ -> Alcotest.fail "expected Stopped"

let d2_steps reports_l =
  List.filter
    (function Dl (c, _, _, _) | Rt (c, _, _, _, _) -> String.equal c "02")
    reports_l

let run_transient_twice_then_ok () =
  let state = make_state () in
  set_answers state "01" [Ok 10];
  set_answers state "02" [Error T; Error T; Ok 20];
  set_answers state "03" [Ok 30];
  let outcome = R.run state all in
  Alcotest.(check (list int))
    "sleeps 5000, 20000" [5_000; 20_000] (sleeps state);
  Alcotest.(check int) "d2 called 3 times" 3 (count "02" state);
  Alcotest.(check (list step_summary))
    "Downloading, Retrying(1/3,5000), Downloading, Retrying(2/3,20000), \
     Downloading, for d2, each with d1's bytes"
    [
      Dl ("02", 1, 10, 0);
      Rt ("02", 1, 3, 5_000, 10);
      Dl ("02", 1, 10, 0);
      Rt ("02", 2, 3, 20_000, 10);
      Dl ("02", 1, 10, 0);
    ]
    (d2_steps (List.map summarize (reports state)));
  match outcome with
  | France_packs.Complete p ->
      Alcotest.(check int) "downloaded = 3" 3 p.downloaded
  | Cancelled _ | Stopped _ -> Alcotest.fail "expected Complete"

let run_backoff_per_departement () =
  let state = make_state () in
  set_answers state "01" [Error T; Ok 10];
  set_answers state "02" [Error T; Error T; Ok 20];
  set_answers state "03" [Error T; Ok 30];
  let outcome = R.run state all in
  Alcotest.(check (list int))
    "each département starts with the whole backoff"
    [5_000; 5_000; 20_000; 5_000]
    (sleeps state);
  Alcotest.(check (list (pair string (pair int int))))
    "Retrying attempts"
    [("01", (1, 3)); ("02", (1, 3)); ("02", (2, 3)); ("03", (1, 3))]
    (List.filter_map
       (function
         | Rt (c, a, n, _, _) -> Some (c, (a, n))
         | Dl ((_ : string), _, _, _) -> None)
       (List.map summarize (reports state)));
  match outcome with
  | France_packs.Complete p ->
      Alcotest.(check int) "downloaded = 3" 3 p.downloaded;
      Alcotest.(check int) "bytes = 60" 60 p.bytes
  | Cancelled _ | Stopped _ -> Alcotest.fail "expected Complete"

let run_transient_exhausted () =
  let state = make_state () in
  set_answers state "01" [Ok 10];
  set_answers state "02" [Error T; Error T; Error T; Error T];
  let outcome = R.run state all in
  Alcotest.(check (list int))
    "sleeps 5000, 20000, 60000" [5_000; 20_000; 60_000] (sleeps state);
  Alcotest.(check int) "d2 called 4 times" 4 (count "02" state);
  Alcotest.(check bool) "d3 never called" false (List.mem "03" (calls state));
  match outcome with
  | France_packs.Stopped (p, e) ->
      Alcotest.(check int) "downloaded = 1" 1 p.downloaded;
      Alcotest.(check (list (pair string outcome_e)))
        "d2 not in failed" [] (failed_codes p.failed);
      Alcotest.(check outcome_e) "error = T" T e
  | Complete _ | Cancelled _ -> Alcotest.fail "expected Stopped"

let run_transient_then_skip () =
  let state = make_state () in
  set_answers state "01" [Ok 10];
  set_answers state "02" [Error T; Error S];
  set_answers state "03" [Ok 30];
  let outcome = R.run state all in
  Alcotest.(check (list int)) "one wait" [5_000] (sleeps state);
  Alcotest.(check int) "d2 called twice" 2 (count "02" state);
  Alcotest.(check bool) "d3 called" true (List.mem "03" (calls state));
  match outcome with
  | France_packs.Complete p ->
      Alcotest.(check int) "downloaded = 2" 2 p.downloaded;
      Alcotest.(check int) "bytes = 40" 40 p.bytes;
      Alcotest.(check (list (pair string outcome_e)))
        "failed = [(d2, S)]"
        [("02", S)]
        (failed_codes p.failed)
  | Cancelled _ | Stopped _ -> Alcotest.fail "expected Complete"

let run_cancelled_before_start () =
  let state = make_state () in
  state.cancelled := true;
  let outcome = R.run state all in
  Alcotest.(check (list string)) "no call" [] (calls state);
  Alcotest.(check (list step_summary))
    "no report" []
    (List.map summarize (reports state));
  Alcotest.(check (list int)) "no sleep" [] (sleeps state);
  match outcome with
  | France_packs.Cancelled p ->
      Alcotest.(check int) "downloaded = 0" 0 p.downloaded
  | Complete _ | Stopped _ -> Alcotest.fail "expected Cancelled"

let cancel_on code_s state =
  state.on_download :=
    fun (dep : Communes.departement) _n ->
      match String.equal (Code.to_string dep.code) code_s with
      | true -> state.cancelled := true
      | false -> ()

let run_cancel_inside_download () =
  let state = make_state () in
  set_answers state "01" [Ok 10];
  set_answers state "02" [Ok 20];
  cancel_on "02" state;
  let outcome = R.run state all in
  Alcotest.(check bool) "d3 never called" false (List.mem "03" (calls state));
  match outcome with
  | France_packs.Cancelled p ->
      Alcotest.(check int) "d2 counted: downloaded = 2" 2 p.downloaded
  | Complete _ | Stopped _ -> Alcotest.fail "expected Cancelled"

let run_cancel_inside_last_download () =
  let state = make_state () in
  set_answers state "01" [Ok 10];
  set_answers state "02" [Ok 20];
  set_answers state "03" [Ok 30];
  cancel_on "03" state;
  let outcome = R.run state all in
  Alcotest.(check (list int)) "no sleep" [] (sleeps state);
  match outcome with
  | France_packs.Complete p ->
      Alcotest.(check int) "downloaded = 3" 3 p.downloaded
  | Cancelled _ | Stopped _ ->
      Alcotest.fail "expected Complete: nothing was left to cancel"

let run_cancel_inside_sleep () =
  let state = make_state () in
  set_answers state "01" [Ok 10];
  set_answers state "02" [Error T];
  (state.on_sleep := fun _ms _n -> state.cancelled := true);
  let outcome = R.run state all in
  Alcotest.(check int) "d2 not retried: called once" 1 (count "02" state);
  Alcotest.(check bool) "d3 never called" false (List.mem "03" (calls state));
  match outcome with
  | France_packs.Cancelled p ->
      Alcotest.(check int) "downloaded = 1" 1 p.downloaded;
      Alcotest.(check (list (pair string outcome_e)))
        "d2 not in failed" [] (failed_codes p.failed)
  | Complete _ | Stopped _ -> Alcotest.fail "expected Cancelled"

let run_resume_after_cancel () =
  let resumed =
    France_packs.plan ~downloaded:[d1.code; d2.code] all.departements
  in
  let state = make_state () in
  set_answers state "03" [Ok 30];
  let outcome = R.run state resumed in
  Alcotest.(check (list string)) "only d3 requested" ["03"] (calls state);
  match outcome with
  | France_packs.Complete p ->
      Alcotest.(check int) "position = 3" 3 (France_packs.position p)
  | Cancelled _ | Stopped _ -> Alcotest.fail "expected Complete"

let run_empty_todo () =
  let state = make_state () in
  let plan = run_plan [d1; d2; d3] [] in
  Alcotest.(check int) "present = 3" 3 plan.present;
  let outcome = R.run state plan in
  Alcotest.(check (list string)) "no call" [] (calls state);
  Alcotest.(check (list step_summary))
    "no report" []
    (List.map summarize (reports state));
  Alcotest.(check (list int)) "no sleep" [] (sleeps state);
  match outcome with
  | France_packs.Complete p ->
      Alcotest.(check int) "downloaded = 0" 0 p.downloaded;
      Alcotest.(check int) "bytes = 0" 0 p.bytes
  | Cancelled _ | Stopped _ -> Alcotest.fail "expected Complete"

(* A deferred IO: [download] parks its continuation and the test resolves it
   by hand, so a run that started a second download before the first one
   ended would be seen. *)
type deferred = {
  parked : (unit -> unit) Queue.t;
  started : string list ref; (* reversed *)
}

module Deferred_run = France_packs.Make (struct
  type 'a io = ('a -> unit) -> unit

  let return x k = k x
  let bind m f k = m (fun x -> f x k)

  type ctx = deferred
  type error = outcome_e

  let download ctx (dep : Communes.departement) k =
    ctx.started := Code.to_string dep.code :: !(ctx.started);
    Queue.add (fun () -> k (Ok 10)) ctx.parked

  let classify = classify
  let sleep (_ : ctx) ~ms:(_ : int) k = k ()
  let cancelled (_ : ctx) = false
  let report (_ : ctx) (_ : error France_packs.step) = ()
end)

let run_one_download_at_a_time () =
  let ctx = {parked = Queue.create (); started = ref []} in
  let result = ref None in
  Deferred_run.run ctx all (fun o -> result := Some o);
  let rec drain expected =
    match expected with
    | [] -> ()
    | code_s :: rest ->
        Alcotest.(check int) "one download pending" 1 (Queue.length ctx.parked);
        Alcotest.(check (option string))
          "the latest started" (Some code_s)
          (List.nth_opt !(ctx.started) 0);
        Alcotest.(check bool) "no result yet" true (Option.is_none !result);
        (Queue.pop ctx.parked) ();
        drain rest
  in
  drain ["01"; "02"; "03"];
  Alcotest.(check int) "nothing pending" 0 (Queue.length ctx.parked);
  match !result with
  | Some (France_packs.Complete p) ->
      Alcotest.(check int) "downloaded = 3" 3 p.downloaded
  | Some (Cancelled _ | Stopped _) | None -> Alcotest.fail "expected Complete"

let run_tests =
  [
    ( "all Ok: downloads in order, no sleep, Downloading with the downloads \
       and bytes so far; Complete with the actual sizes, not estimates",
      `Quick,
      run_all_ok );
    ( "skip present (via France_packs.plan ~downloaded): downloads only todo; \
       position = total",
      `Quick,
      run_skip_present );
    ( "Skip on one département: listed in failed, adds no bytes, the next \
       still runs",
      `Quick,
      run_skip_on_one );
    ( "Stop on one département: ends at once, no sleep, nothing after",
      `Quick,
      run_stop_on_one );
    ( "Transient twice then Ok: retries with backoff, reports Retrying, 3 \
       calls to the same département",
      `Quick,
      run_transient_twice_then_ok );
    ( "Transient on three départements: each starts with the whole backoff",
      `Quick,
      run_backoff_per_departement );
    ( "Transient on every attempt: stops once backoff_ms is exhausted, 4 \
       calls, the next département never called, nothing failed",
      `Quick,
      run_transient_exhausted );
    ( "Transient then Skip on one département: one wait, then skipped",
      `Quick,
      run_transient_then_skip );
    ( "cancelled before the first département: Cancelled at once, nothing sent",
      `Quick,
      run_cancelled_before_start );
    ( "cancel set during a download: that département is kept, the next is \
       never started",
      `Quick,
      run_cancel_inside_download );
    ( "cancel set during the last download: Complete",
      `Quick,
      run_cancel_inside_last_download );
    ( "cancel set during a backoff wait: not retried, not counted as failed",
      `Quick,
      run_cancel_inside_sleep );
    ( "resuming after a cancel downloads only what is still missing",
      `Quick,
      run_resume_after_cancel );
    ( "an empty todo completes at once, with no call, report or sleep",
      `Quick,
      run_empty_todo );
    ( "over a deferred IO, a download starts only once the previous one ended",
      `Quick,
      run_one_download_at_a_time );
  ]

let () =
  Alcotest.run "france_packs"
    [
      ( "backoff_ms",
        [
          ( "backoff_ms waits 5 s, then 20 s, then 60 s",
            `Quick,
            backoff_ms_is_5_20_60_seconds );
        ] );
      ("plan", plan_tests);
      ("failure", failure_tests);
      ("run", run_tests);
    ]
