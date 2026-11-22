let () =
  Alcotest.run "refs"
    [
      Test_request.suite;
      Test_gbif.suite;
      Test_wikidata.suite;
      Test_wikipedia.suite;
      Test_tela.suite;
      Test_inpn.suite;
      Test_wiki_text.suite;
      Test_plantuse.suite;
      Test_uses_fetch.suite;
      Test_uses.suite;
      Test_payload.suite;
      Test_projection.suite;
      Test_organ_photos.suite;
      Test_step.suite;
      Test_fanout.suite;
      Test_regional.suite;
      Test_resolve.suite;
      Test_fetch_rule.suite;
    ]
