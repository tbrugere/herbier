let () =
  Alcotest.run "refs"
    [
      Test_request.suite;
      Test_gbif.suite;
      Test_wikidata.suite;
      Test_wikipedia.suite;
      Test_payload.suite;
      Test_projection.suite;
      Test_organ_photos.suite;
      Test_step.suite;
      Test_fanout.suite;
      Test_resolve.suite;
      Test_fetch_rule.suite;
    ]
