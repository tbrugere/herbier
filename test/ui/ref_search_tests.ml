(* Ref_search: 4i's reference search state machine, without timers or
   network. *)

module Ref_search = Herbier_ui_model.Ref_search
module Resolve = Herbier_refs.Resolve

let digitalis_taxon = Fixtures.digitalis_taxon

let cand key : Resolve.Candidate.t =
  {taxon = {digitalis_taxon with key}; french = []}

let status_str = function
  | Ref_search.Blank -> "Blank"
  | Ref_search.Pending -> "Pending"
  | Ref_search.Found cs ->
      Printf.sprintf "Found [%s]"
        (String.concat ", "
           (List.map
              (fun (c : Resolve.Candidate.t) -> string_of_int c.taxon.key)
              cs))
  | Ref_search.Offline -> "Offline"
  | Ref_search.Failed m -> "Failed " ^ m

let status =
  Alcotest.testable
    (fun f s -> Format.pp_print_string f (status_str s))
    Ref_search.equal_status

let effect_str = function
  | Ref_search.No_effect -> "No_effect"
  | Ref_search.Wait {seq; ms} ->
      Printf.sprintf "Wait {seq = %d; ms = %d}" seq ms
  | Ref_search.Fetch {seq; q} -> Printf.sprintf "Fetch {seq = %d; q = %S}" seq q

let check_effect what expected eff =
  Alcotest.(check string) what expected (effect_str eff)

let ref_search_init () =
  (match Ref_search.init ~online:true "digitale" with
  | t, Ref_search.Fetch {seq = 0; q = "digitale"} ->
      Alcotest.(check status) "status" Ref_search.Pending (Ref_search.status t)
  | _, e ->
      Alcotest.failf "expected Fetch {seq=0; q=\"digitale\"}, got %s"
        (effect_str e));
  (match Ref_search.init ~online:false "x" with
  | t, Ref_search.No_effect ->
      Alcotest.(check status) "offline" Ref_search.Offline (Ref_search.status t)
  | _, e -> Alcotest.failf "expected No_effect, got %s" (effect_str e));
  match Ref_search.init ~online:true " " with
  | t, Ref_search.No_effect ->
      Alcotest.(check status) "blank" Ref_search.Blank (Ref_search.status t)
  | _, e -> Alcotest.failf "expected No_effect, got %s" (effect_str e)

let ref_search_debounce_sequence () =
  let t0 = fst (Ref_search.init ~online:true "") in
  let t1, e1 = Ref_search.typed ~online:true "di" t0 in
  let t2, e2 = Ref_search.typed ~online:true "dig" t1 in
  let t3, e3 = Ref_search.typed ~online:true "digi" t2 in
  Alcotest.(check int) "debounce_ms" 300 Ref_search.debounce_ms;
  check_effect "di" "Wait {seq = 1; ms = 300}" e1;
  check_effect "dig" "Wait {seq = 2; ms = 300}" e2;
  check_effect "digi" "Wait {seq = 3; ms = 300}" e3;
  check_effect "elapsed, stale seq 1" "No_effect"
    (snd (Ref_search.elapsed ~online:true ~seq:1 t3));
  check_effect "elapsed, stale seq 2" "No_effect"
    (snd (Ref_search.elapsed ~online:true ~seq:2 t3));
  let t4, e4 = Ref_search.elapsed ~online:true ~seq:3 t3 in
  check_effect "elapsed, current seq" "Fetch {seq = 3; q = \"digi\"}" e4;
  Alcotest.(check status)
    "still Pending" Ref_search.Pending (Ref_search.status t4)

let ref_search_stale_answer_ignored () =
  let t0 = fst (Ref_search.init ~online:true "") in
  let t1, _ = Ref_search.typed ~online:true "di" t0 in
  let t2, _ = Ref_search.typed ~online:true "dig" t1 in
  let t3, _ = Ref_search.typed ~online:true "digi" t2 in
  let stale = Ref_search.answered ~seq:1 (Ok [cand 1]) t3 in
  Alcotest.(check status)
    "an older seq changes nothing" Ref_search.Pending (Ref_search.status stale);
  Alcotest.(check int) "seq unchanged" 3 (Ref_search.seq stale);
  let current = Ref_search.answered ~seq:3 (Ok [cand 1; cand 2]) t3 in
  Alcotest.(check status)
    "the current seq's answer"
    (Ref_search.Found [cand 1; cand 2])
    (Ref_search.status current)

let ref_search_typed_same_text_or_blank () =
  let t0 = fst (Ref_search.init ~online:true "") in
  let t1, _ = Ref_search.typed ~online:true "digi" t0 in
  let same, e = Ref_search.typed ~online:true " digi " t1 in
  check_effect "same text (padded)" "No_effect" e;
  Alcotest.(check status)
    "unchanged" (Ref_search.status t1) (Ref_search.status same);
  Alcotest.(check int) "seq unchanged" (Ref_search.seq t1) (Ref_search.seq same);
  let blank, e2 = Ref_search.typed ~online:true "  " t1 in
  check_effect "blank" "No_effect" e2;
  Alcotest.(check status) "Blank" Ref_search.Blank (Ref_search.status blank);
  Alcotest.(check int)
    "blank bumps seq"
    (Ref_search.seq t1 + 1)
    (Ref_search.seq blank)

let ref_search_answered_unavailable_and_no_species () =
  let t0 = fst (Ref_search.init ~online:true "digi") in
  Alcotest.(check status)
    "Failed" (Ref_search.Failed "m")
    (Ref_search.status
       (Ref_search.answered ~seq:0 (Error (Resolve.Unavailable "m")) t0));
  Alcotest.(check status)
    "No_species is Found []" (Ref_search.Found [])
    (Ref_search.status
       (Ref_search.answered ~seq:0 (Error Resolve.No_species) t0));
  Alcotest.(check status)
    "Observation_link is Found []" (Ref_search.Found [])
    (Ref_search.status
       (Ref_search.answered ~seq:0 (Error Resolve.Observation_link) t0))

let ref_search_network_changes () =
  let t0 = fst (Ref_search.init ~online:true "digi") in
  let offline, e = Ref_search.network ~online:false t0 in
  check_effect "going offline while Pending" "No_effect" e;
  Alcotest.(check status)
    "Offline" Ref_search.Offline
    (Ref_search.status offline);
  Alcotest.(check int)
    "seq bumped (drops the in-flight request)" 1 (Ref_search.seq offline);
  let ignored = Ref_search.answered ~seq:0 (Ok [cand 1]) offline in
  Alcotest.(check status)
    "the in-flight answer is ignored" Ref_search.Offline
    (Ref_search.status ignored);
  let online, e2 = Ref_search.network ~online:true offline in
  check_effect "coming online with a query, at once"
    "Fetch {seq = 2; q = \"digi\"}" e2;
  Alcotest.(check status)
    "Pending" Ref_search.Pending (Ref_search.status online);
  let found = Ref_search.answered ~seq:2 (Ok [cand 1]) online in
  let unaffected, e3 = Ref_search.network ~online:false found in
  check_effect "Found stays shown offline" "No_effect" e3;
  Alcotest.(check status)
    "unchanged"
    (Ref_search.Found [cand 1])
    (Ref_search.status unaffected)

let ref_search_online_while_pending_or_found () =
  let pending = fst (Ref_search.init ~online:true "digi") in
  let t1, e1 = Ref_search.network ~online:true pending in
  check_effect "online while Pending" "No_effect" e1;
  Alcotest.(check status)
    "still Pending" Ref_search.Pending (Ref_search.status t1);
  Alcotest.(check int)
    "seq unchanged while Pending" (Ref_search.seq pending) (Ref_search.seq t1);
  let found = Ref_search.answered ~seq:0 (Ok [cand 1]) pending in
  let t2, e2 = Ref_search.network ~online:true found in
  check_effect "online while Found" "No_effect" e2;
  Alcotest.(check status)
    "still Found"
    (Ref_search.Found [cand 1])
    (Ref_search.status t2);
  Alcotest.(check int)
    "seq unchanged while Found" (Ref_search.seq found) (Ref_search.seq t2)

let ref_search_network_from_failed () =
  let t0 = fst (Ref_search.init ~online:true "digi") in
  let failed =
    Ref_search.answered ~seq:0 (Error (Resolve.Unavailable "m")) t0
  in
  let offline, e = Ref_search.network ~online:false failed in
  check_effect "going offline while Failed" "No_effect" e;
  Alcotest.(check status)
    "Offline" Ref_search.Offline
    (Ref_search.status offline);
  Alcotest.(check int) "seq bumped" 1 (Ref_search.seq offline);
  let online, e2 = Ref_search.network ~online:true failed in
  check_effect "coming online while Failed, at once"
    "Fetch {seq = 1; q = \"digi\"}" e2;
  Alcotest.(check status)
    "Pending" Ref_search.Pending (Ref_search.status online)

let ref_search_blank_ignores_network_and_retry () =
  let t0 = fst (Ref_search.init ~online:true "") in
  let t1, e1 = Ref_search.network ~online:true t0 in
  check_effect "online with a blank query" "No_effect" e1;
  Alcotest.(check status) "Blank" Ref_search.Blank (Ref_search.status t1);
  let t2, e2 = Ref_search.retry ~online:true t0 in
  check_effect "retry with a blank query" "No_effect" e2;
  Alcotest.(check status) "Blank" Ref_search.Blank (Ref_search.status t2);
  Alcotest.(check int) "seq unchanged" 0 (Ref_search.seq t2)

let ref_search_typed_and_elapsed_offline () =
  let t0 = fst (Ref_search.init ~online:true "") in
  let t1, e1 = Ref_search.typed ~online:false "abc" t0 in
  check_effect "typed offline" "No_effect" e1;
  Alcotest.(check status) "Offline" Ref_search.Offline (Ref_search.status t1);
  let t2, e2 = Ref_search.elapsed ~online:false ~seq:(Ref_search.seq t1) t1 in
  check_effect "elapsed offline, current seq" "No_effect" e2;
  Alcotest.(check status) "Offline" Ref_search.Offline (Ref_search.status t2)

let ref_search_retry () =
  let t0 = fst (Ref_search.init ~online:true "digi") in
  let failed =
    Ref_search.answered ~seq:0 (Error (Resolve.Unavailable "m")) t0
  in
  let t1, e1 = Ref_search.retry ~online:true failed in
  check_effect "retry online: Fetch at once" "Fetch {seq = 1; q = \"digi\"}" e1;
  Alcotest.(check status) "Pending" Ref_search.Pending (Ref_search.status t1);
  let t2, e2 = Ref_search.retry ~online:false failed in
  check_effect "retry offline" "No_effect" e2;
  Alcotest.(check status) "Offline" Ref_search.Offline (Ref_search.status t2)

let ref_search =
  [
    Alcotest.test_case "network online while Pending or Found: nothing" `Quick
      ref_search_online_while_pending_or_found;
    Alcotest.test_case "init: prefilled online, offline, blank" `Quick
      ref_search_init;
    Alcotest.test_case
      "typed: debounce sequence, elapsed drops the stale timers" `Quick
      ref_search_debounce_sequence;
    Alcotest.test_case
      "answered: a stale seq is ignored, the current one is not" `Quick
      ref_search_stale_answer_ignored;
    Alcotest.test_case "typed: a padded repeat is a no-op, blank clears" `Quick
      ref_search_typed_same_text_or_blank;
    Alcotest.test_case "answered: Unavailable is Failed, No_species is Found []"
      `Quick ref_search_answered_unavailable_and_no_species;
    Alcotest.test_case
      "network: offline drops the request, online retries at once, Found is \
       unaffected"
      `Quick ref_search_network_changes;
    Alcotest.test_case
      "network: Failed goes Offline (seq bumped) or fetches again at once"
      `Quick ref_search_network_from_failed;
    Alcotest.test_case "network and retry leave a blank query alone" `Quick
      ref_search_blank_ignores_network_and_retry;
    Alcotest.test_case "typed and elapsed stay Offline without a network change"
      `Quick ref_search_typed_and_elapsed_offline;
    Alcotest.test_case "retry: online fetches again, offline stays Offline"
      `Quick ref_search_retry;
  ]

(* equal_status on every pair of a set covering each constructor and a
   difference inside Found and Failed: true exactly on the same value. *)
let ref_search_equal_status_pairs () =
  let cand french : Resolve.Candidate.t = {taxon = digitalis_taxon; french} in
  let values =
    [
      Ref_search.Blank;
      Pending;
      Offline;
      Found [];
      Found [cand ["Digitale pourpre"]];
      Found [cand ["Gantelée"]];
      Failed "a";
      Failed "b";
    ]
  in
  List.iteri
    (fun i a ->
      List.iteri
        (fun j b ->
          Alcotest.(check bool)
            (Printf.sprintf "values %d and %d" i j)
            (Int.equal i j)
            (Ref_search.equal_status a b))
        values)
    values

let ref_search =
  ref_search
  @ [
      Alcotest.test_case "equal_status: true exactly on the same value" `Quick
        ref_search_equal_status_pairs;
    ]
