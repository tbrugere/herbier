let () =
  Alcotest.run "identify"
    ((Test_fixtures.suite :: Test_organ.suites)
    @ Test_plantnet.suites
    @ Test_proposal.suites
    @ Test_make.suites)
