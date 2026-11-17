let () =
  Alcotest.run "ui"
    [
      ("pack_text", Pack_text_tests.pack_text);
      ("zoom", Zoom_tests.zoom);
      ("cover", Cover_tests.cover);
      ("record_plan", Record_plan_tests.record_plan);
      ("local_time", Local_time_tests.local_time);
      ("to_identify", Local_time_tests.to_identify);
      ("plant_form", Plant_form_tests.plant_form);
      ("tag_edits", Tag_edits_tests.tag_edits);
      ("fr_date", Fr_date_tests.fr_date @ Fr_date_tests.ago);
      ("plant_link", Plant_link_tests.plant_link);
      ("ref_search", Ref_search_tests.ref_search);
      ("ref_pick", Ref_pick_tests.ref_pick);
      ("ref_paste", Ref_paste_tests.ref_paste);
      ("ref_text", Ref_text_tests.ref_text);
      ("intercept", Intercept_tests.intercept);
      ("journal_day", Journal_day_tests.journal_day);
      ("map_filter", Map_tests.map_filter);
      ("map_sheet", Map_tests.map_sheet);
      ("list_patch", List_patch_tests.list_patch);
      ("collection_filter", Collection_filter_tests.collection_filter);
      ("journal_filter", Journal_filter_tests.journal_filter);
      ("fr_text", Fr_text_tests.fr_text);
      ("snap", Snap_tests.snap);
      ("parked_entry", Parked_entry_tests.parked_entry);
      ("motion", Motion_tests.motion);
      ("drive_text", Drive_text_tests.drive_text);
      ("drive_sheet", Drive_sheet_tests.tests);
      ("network_text", Network_text_tests.network_text);
      ("server_text", Server_text_tests.server_text);
      ("offline_data", Offline_data_tests.offline_data);
      ("identify_settings", Identify_settings_tests.identify_settings);
    ]
