let () =
  Alcotest.run "refs"
    [
      Test_request.suite;
      Test_gbif.suite;
      Test_wikidata.suite;
      Test_wikipedia.suite;
      Test_payload.suite;
      Test_projection.suite;
    ]
