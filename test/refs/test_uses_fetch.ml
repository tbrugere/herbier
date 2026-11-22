(* Herbier_refs.Uses_fetch.program: the Pl@ntUse call run beside Regional,
   over Fake_net. *)

module Uses_fetch = Herbier_refs.Uses_fetch
module Regional = Herbier_refs.Regional
module Plantuse = Herbier_refs.Sources.Plantuse
module Step = Herbier_refs.Step
module Request = Herbier_refs.Request
module Payload = Herbier_refs.Payload
module Source = Herbier_domain.Reference.Source
module Status = Herbier_domain.Reference.Status

let status =
  Alcotest.testable
    (fun f s -> Format.pp_print_string f (Status.to_string s))
    (fun a b -> String.equal (Status.to_string a) (Status.to_string b))

let url (r : Request.t) = r.url

let digitalis_request =
  match Plantuse.page ~titles:["Digitalis purpurea"] with
  | Some r -> r
  | None -> Alcotest.fail "Plantuse.page gave None"

let input ?(name = Some "Digitalis purpurea") ?(taxref = Some 94959)
    ?(settled = true) () : Regional.input =
  {Regional.name; taxref; settled}

let one_row name rows =
  match rows with
  | [r] -> r
  | rs -> Alcotest.failf "%s: expected 1 row, got %d" name (List.length rs)

let no_net = Fake_net.fixtures []

(* ---------- no name ---------- *)

let no_name_settled_is_missing () =
  let i = input ~name:None ~settled:true () in
  let r = one_row "no name, settled" (Step.run no_net (Uses_fetch.program i)) in
  Alcotest.check status "missing" Status.Missing r.status;
  Alcotest.(check bool)
    "empty payload" true
    (Yojson.Safe.equal r.payload (`Assoc []))

let no_name_not_settled_is_failed () =
  let i = input ~name:None ~settled:false () in
  let r =
    one_row "no name, not settled" (Step.run no_net (Uses_fetch.program i))
  in
  Alcotest.check status "failed" Status.Failed r.status;
  Alcotest.(check bool)
    "empty payload" true
    (Yojson.Safe.equal r.payload (`Assoc []))

(* ---------- found / missing / failed ---------- *)

let digitalis_found () =
  let i = input () in
  let net =
    Fake_net.with_
      (Fake_net.plantuse_table ~titles:["Digitalis purpurea"]
         "plantuse_page_digitalis_purpurea.json")
      no_net
  in
  let prog = Uses_fetch.program i in
  Alcotest.(check (list string))
    "one request, the fixture's URL"
    [url digitalis_request]
    (List.map url (Step.requests net prog));
  let r = one_row "digitalis" (Step.run net prog) in
  Alcotest.check status "complete" Status.Complete r.status;
  Alcotest.(check bool)
    "payload is Payload.plantuse ~page:(Some the fixture body)" true
    (Yojson.Safe.equal r.payload
       (Payload.plantuse
          ~page:
            (Some
               (Fake_net.json_of_fixture "plantuse_page_digitalis_purpurea.json"))));
  Alcotest.(check string) "source" "plantuse" (Source.to_string r.source)

let fallopia_missing () =
  let i = input ~name:(Some "Fallopia japonica") () in
  let net =
    Fake_net.with_
      (Fake_net.plantuse_table ~titles:["Fallopia japonica"]
         "plantuse_page_fallopia_japonica.json")
      no_net
  in
  let r = one_row "fallopia" (Step.run net (Uses_fetch.program i)) in
  Alcotest.check status "missing (the source answered, no page found)"
    Status.Missing r.status;
  Alcotest.(check bool)
    "payload keeps the answer as {page}" true
    (Yojson.Safe.equal r.payload
       (Payload.plantuse
          ~page:
            (Some
               (Fake_net.json_of_fixture "plantuse_page_fallopia_japonica.json"))))

let answer_failed_is_failed () =
  let i = input () in
  let net = Fake_net.with_ [(url digitalis_request, Step.Failed "x")] no_net in
  let r = one_row "failed" (Step.run net (Uses_fetch.program i)) in
  Alcotest.check status "failed" Status.Failed r.status;
  Alcotest.(check bool)
    "empty payload" true
    (Yojson.Safe.equal r.payload (`Assoc []))

let answer_absent_is_failed () =
  let i = input () in
  let net = Fake_net.with_ [(url digitalis_request, Step.Absent)] no_net in
  let r = one_row "absent" (Step.run net (Uses_fetch.program i)) in
  Alcotest.check status "failed (MediaWiki never 404s a query)" Status.Failed
    r.status

let case name f = (name, `Quick, f)

let suite =
  ( "uses_fetch",
    [
      case "name None, settled: no request, Missing {}"
        no_name_settled_is_missing;
      case "name None, not settled: Failed {}" no_name_not_settled_is_failed;
      case "Digitalis: one request, Complete {page}" digitalis_found;
      case "Fallopia: page missing: Missing {page}" fallopia_missing;
      case "a Failed answer: Failed {}" answer_failed_is_failed;
      case "an Absent answer: Failed {}" answer_absent_is_failed;
    ] )
