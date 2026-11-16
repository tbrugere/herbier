let () =
  Alcotest.run "domain"
    [
      ("ids", Test_ids.tests);
      ("enums", Test_enums.tests);
      ("photo", Test_photo.tests);
      ("places", Test_places.tests);
      ("link", Test_link.tests);
      ("text", Test_text.tests);
      ("text same_email", Test_text.same_email_tests);
      ("bbox", Test_bbox.tests);
      ("fold", Test_fold.tests);
      ("schema dump", Test_schema_dump.tests);
      ("merge", Test_merge.tests);
    ]
