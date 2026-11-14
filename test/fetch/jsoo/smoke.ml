(* Http.get, Geocoder.run, Timed_fetch.request and Timed_fetch.request_blob
   over a stubbed fetch. Each
   case sets the stub's next answer, runs one request and describes the
   outcome as one line: the result, whether the Api-User-Agent header was
   sent, and how many times the response body was read. The lines must equal
   [expected]. The stub is stub.js, preloaded by node before Brr reads the
   fetch global. A mismatch goes to stderr and exits 1 (the geocoder's own
   console lines go to stdout). The exit code stays 1 until every case has
   run, so a future that never resolves fails the run. *)

module Http = Herbier_refs_io.Http
module Timed_fetch = Herbier_bindings.Timed_fetch
module Geocoder = Herbier_geo_io.Geocoder
module Geocode = Herbier_geo.Geocode
module Request = Herbier_refs.Request
module Source = Herbier_domain.Reference.Source

let process = Jv.get Jv.global "process"
let set_exit_code n = Jv.set process "exitCode" (Jv.of_int n)

let observed f =
  let before = Jv.to_int (Jv.get Jv.global "__texts") in
  Fut.map
    (fun line ->
      let ua = Jv.to_list Jv.to_string (Jv.get Jv.global "__ua") in
      Jv.set Jv.global "__ua" (Jv.of_list Jv.of_string []);
      Printf.sprintf "%s | %s | text read %d" line (String.concat "," ua)
        (Jv.to_int (Jv.get Jv.global "__texts") - before))
    (f ())

let http kind source =
  Jv.set Jv.global "__next" (Jv.of_string kind);
  let request =
    Request.make source ~base:"https://example.test" ~path:["x"] ~query:[]
  in
  observed (fun () ->
      Fut.map
        (function
          | Ok body -> "http " ^ kind ^ ": Ok " ^ body
          | Error e -> "http " ^ kind ^ ": " ^ Http.error_to_string e)
        (Http.get ~timeout_ms:50 request))

let geocoder kind request =
  Jv.set Jv.global "__next" (Jv.of_string kind);
  observed (fun () ->
      Fut.map
        (function
          | Ok json -> "geocoder " ^ kind ^ ": Ok " ^ Yojson.Safe.to_string json
          | Error e -> "geocoder " ^ kind ^ ": " ^ Geocoder.error_to_string e)
        (Geocoder.run ~timeout_ms:50
           (Geocode.Get (request, fun json -> Geocode.Done (Ok json)))))

(* Auth's path: the default [Read] policy, the default 15 s timer (so no
   hanging case here; the timer is the one [get] runs with a shorter delay). *)
let request ?(headers = []) kind =
  Jv.set Jv.global "__next" (Jv.of_string kind);
  observed (fun () ->
      Fut.map
        (function
          | Ok {Timed_fetch.status; body; headers = _} ->
              Printf.sprintf "request %s: Ok %d %s" kind status body
          | Error (Timed_fetch.Failed _) when headers <> [] ->
              "request " ^ kind ^ ": Failed"
          | Error e -> "request " ^ kind ^ ": " ^ Timed_fetch.error_to_string e)
        (Timed_fetch.request ~meth:`POST ~url:"https://example.test/token"
           ~headers ~body:(Some "{}")))

(* The Drive upload's path: a Blob framed by Blob_frame, echoed back by the
   stub, under a short timer. *)
let request_blob kind =
  Jv.set Jv.global "__next" (Jv.of_string kind);
  let body =
    Herbier_bindings.Blob_frame.wrap ~prefix:"\xc3\xa9<" ~suffix:">"
      (Brr.Blob.of_jstr (Jstr.v "media"))
  in
  observed (fun () ->
      Fut.map
        (function
          | Ok {Timed_fetch.status; body; headers = _} ->
              Printf.sprintf "request_blob %s: Ok %d %s" kind status body
          | Error e ->
              "request_blob " ^ kind ^ ": " ^ Timed_fetch.error_to_string e)
        (Timed_fetch.request_blob ~timeout_ms:50 ~meth:`POST
           ~url:"https://example.test/upload" ~headers:[] body))

let expected =
  [
    "http ok: Ok {\"a\":1} | ua | text read 1";
    "http ok: Ok {\"a\":1} | no ua | text read 1";
    "http 503: HTTP 503 (retry after 7): busy | ua | text read 1";
    "http 503 unreadable: HTTP 503:  | no ua | text read 1";
    "http 200 unreadable: network: boom | no ua | text read 1";
    "http rejected: network: Failed to fetch | no ua | text read 0";
    "http hangs: timeout | no ua | text read 0";
    "geocoder ok: Ok {\"a\":1} | no ua | text read 1";
    "geocoder 503: photon: HTTP 503 | no ua | text read 0";
    "geocoder 503 unreadable: geoplateforme: HTTP 503 | no ua | text read 0";
    "geocoder 200 unreadable: network: boom | no ua | text read 1";
    "geocoder rejected: network: Failed to fetch | no ua | text read 0";
    "geocoder hangs: timeout | no ua | text read 0";
    "request ok: Ok 200 {\"a\":1} | no ua | text read 1";
    "request 503: Ok 503 busy | no ua | text read 1";
    "request 503 unreadable: Error: boom | no ua | text read 1";
    "request 200 unreadable: Error: boom | no ua | text read 1";
    "request rejected: TypeError: Failed to fetch | no ua | text read 0";
    "request bad header: Failed |  | text read 0";
    "request_blob echo: Ok 200 POST \xc3\xa9<media> | no ua | text read 1";
    "request_blob hangs: timeout | no ua | text read 0";
  ]

let () =
  set_exit_code 1;
  let photon = Geocode.photon_search "x" in
  let ign = Geocode.geoplateforme_lieu_dit {lat = 48.; lon = 7.} in
  let cases =
    [
      (fun () -> http "ok" Source.Wikidata);
      (fun () -> http "ok" Source.Gbif);
      (fun () -> http "503" Source.Wikipedia);
      (fun () -> http "503 unreadable" Source.Gbif);
      (fun () -> http "200 unreadable" Source.Gbif);
      (fun () -> http "rejected" Source.Gbif);
      (fun () -> http "hangs" Source.Gbif);
      (fun () -> geocoder "ok" photon);
      (fun () -> geocoder "503" photon);
      (fun () -> geocoder "503 unreadable" ign);
      (fun () -> geocoder "200 unreadable" photon);
      (fun () -> geocoder "rejected" ign);
      (fun () -> geocoder "hangs" photon);
      (fun () -> request "ok");
      (fun () -> request "503");
      (fun () -> request "503 unreadable");
      (fun () -> request "200 unreadable");
      (fun () -> request "rejected");
      (fun () -> request ~headers:[("x-bad", "a\nb")] "bad header");
      (fun () -> request_blob "echo");
      (fun () -> request_blob "hangs");
    ]
  in
  let all =
    List.fold_left
      (fun acc case ->
        Fut.bind acc (fun lines -> Fut.map (fun l -> l :: lines) (case ())))
      (Fut.return []) cases
  in
  Fut.await all (fun lines ->
      let lines = List.rev lines in
      match List.equal String.equal lines expected with
      | true -> set_exit_code 0
      | false ->
          prerr_endline "got:";
          List.iter prerr_endline lines;
          prerr_endline "expected:";
          List.iter prerr_endline expected)
