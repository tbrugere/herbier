(* Herbier_refs.Step: the free monad of GETs, independent of any source. *)

module Step = Herbier_refs.Step
module Request = Herbier_refs.Request
module Source = Herbier_domain.Reference.Source

let req n =
  Request.make Source.Gbif ~base:"https://x.example"
    ~path:[string_of_int n]
    ~query:[]

let req_url n = (req n).Request.url

(* A network stub that answers every request with a fixed response,
   recording the URLs it was asked, in order. *)
let logging () =
  let seen = ref [] in
  let answer (r : Request.t) =
    seen := Request.(r.url) :: !seen;
    Step.Body (`String Request.(r.url))
  in
  (answer, fun () -> List.rev !seen)

let response =
  Alcotest.testable
    (fun f (r : Step.response) ->
      Format.pp_print_string f
        (match r with
        | Body j -> "Body " ^ Yojson.Safe.to_string j
        | Absent -> "Absent"
        | Failed m -> "Failed " ^ m))
    (fun a b ->
      match (a, b) with
      | Step.Body j1, Step.Body j2 -> Yojson.Safe.equal j1 j2
      | Absent, Absent -> true
      | Failed m1, Failed m2 -> String.equal m1 m2
      | _ -> false)

let run_tests =
  [
    ( "run of return makes no request",
      `Quick,
      fun () ->
        let answer, urls = logging () in
        Alcotest.(check int) "value" 1 (Step.run answer (Step.return 1));
        Alcotest.(check (list string)) "requests" [] (urls ()) );
    ( "requests on return is [] without running the network function",
      `Quick,
      fun () ->
        let prog = Step.return "x" in
        Alcotest.(check (list string))
          "requests" []
          (List.map
             (fun (r : Request.t) -> r.url)
             (Step.requests (fun _ -> Step.Absent) prog)) );
  ]

let bind_tests =
  [
    ( "bind sequences two gets, answered and listed in order",
      `Quick,
      fun () ->
        let answer, urls = logging () in
        let prog =
          Step.bind
            (Step.get (req 1))
            (fun r1 ->
              Step.bind (Step.get (req 2)) (fun r2 -> Step.return (r1, r2)))
        in
        let a, b = Step.run answer prog in
        Alcotest.check response "first response"
          (Step.Body (`String (req_url 1)))
          a;
        Alcotest.check response "second response"
          (Step.Body (`String (req_url 2)))
          b;
        Alcotest.(check (list string))
          "run answered in order"
          [req_url 1; req_url 2]
          (urls ());
        Alcotest.(check (list string))
          "requests lists both, in order"
          [req_url 1; req_url 2]
          (List.map (fun (r : Request.t) -> r.url) (Step.requests answer prog))
    );
    ( "a later get is never reached when an earlier one is enough",
      `Quick,
      fun () ->
        let answer, urls = logging () in
        let prog = Step.bind (Step.get (req 1)) (fun _ -> Step.return "done") in
        Alcotest.(check string) "value" "done" (Step.run answer prog);
        Alcotest.(check (list string))
          "only the first request"
          [req_url 1]
          (urls ()) );
  ]

let map_tests =
  [
    ( "map transforms the value, makes the same requests",
      `Quick,
      fun () ->
        let answer, _ = logging () in
        let prog = Step.map (fun r -> (r, true)) (Step.get (req 1)) in
        match Step.run answer prog with
        | r, true ->
            Alcotest.check response "response"
              (Step.Body (`String (req_url 1)))
              r
        | _, false -> Alcotest.fail "map dropped the transformation" );
    ( "let+ keeps exactly the response the network function gave: Body",
      `Quick,
      fun () ->
        let open Step.Syntax in
        let answer _ = Step.Body (`Int 1) in
        let prog =
          let+ r = Step.get (req 1) in
          r
        in
        Alcotest.check response "Body"
          (Step.Body (`Int 1))
          (Step.run answer prog) );
    ( "let+ keeps exactly the response the network function gave: Absent",
      `Quick,
      fun () ->
        let open Step.Syntax in
        let answer _ = Step.Absent in
        let prog =
          let+ r = Step.get (req 1) in
          r
        in
        Alcotest.check response "Absent" Step.Absent (Step.run answer prog) );
    ( "let+ keeps exactly the response the network function gave: Failed",
      `Quick,
      fun () ->
        let open Step.Syntax in
        let answer _ = Step.Failed "timeout" in
        let prog =
          let+ r = Step.get (req 1) in
          r
        in
        Alcotest.check response "Failed" (Step.Failed "timeout")
          (Step.run answer prog) );
    ( "let* chains a continuation off the response, as bind does",
      `Quick,
      fun () ->
        let open Step.Syntax in
        let answer _ = Step.Body (`Int 42) in
        let prog =
          let* r = Step.get (req 1) in
          match r with
          | Step.Body (`Int n) -> Step.return (n + 1)
          | _ -> Step.return 0
        in
        Alcotest.(check int) "value" 43 (Step.run answer prog) );
  ]

let recover_tests =
  [
    ( "recover: a raising continuation ends the program with f of its text",
      `Quick,
      fun () ->
        let open Step.Syntax in
        let answer, urls = logging () in
        let prog =
          let* (_ : Step.response) = Step.get (req 1) in
          let* (_ : Step.response) = Step.get (req 2) in
          failwith "boom"
        in
        let prog =
          Step.recover (fun msg -> Error msg) (Step.map Result.ok prog)
        in
        (match Step.run answer prog with
        | Error msg ->
            Alcotest.(check bool)
              "the exception's text" true
              (String.length msg > 0)
        | Ok () -> Alcotest.fail "expected Error");
        Alcotest.(check (list string))
          "the requests before the raise"
          [req_url 1; req_url 2]
          (urls ()) );
    ( "recover: a program that does not raise is unchanged",
      `Quick,
      fun () ->
        let open Step.Syntax in
        let answer _ = Step.Body (`Int 1) in
        let prog =
          let+ r = Step.get (req 1) in
          match r with Step.Body (`Int n) -> n | _ -> 0
        in
        Alcotest.(check int)
          "value" 1
          (Step.run answer (Step.recover (fun _ -> -1) prog)) );
  ]

let suite = ("step", run_tests @ bind_tests @ map_tests @ recover_tests)
