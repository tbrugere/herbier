module Photo = Herbier_domain.Photo

let photo original_target upload_state : Photo.t =
  let t0 = Ptime.epoch in
  {
    id = Herbier_domain.Ids.Photo_id.fresh ();
    observation_id = Herbier_domain.Ids.Observation_id.fresh ();
    taken_at = t0;
    width = 1;
    height = 1;
    sha256 = "";
    preview_path = "";
    preview_bucket_key = None;
    original_target;
    drive_file_id = None;
    upload_state;
    created_at = t0;
    updated_at = t0;
    deleted_at = None;
  }

(* Every (target, state) pair: only a Drive original not there yet waits. *)
let awaiting () =
  List.iter
    (fun target ->
      List.iter
        (fun state ->
          let expected =
            match (target, state) with
            | Photo.Original_target.Drive, Photo.Upload_state.Pending
            | Drive, Failed ->
                true
            | Drive, (Uploaded | Original_missing)
            | App_only, (Pending | Uploaded | Failed | Original_missing) ->
                false
          in
          Alcotest.(check bool)
            (Photo.Original_target.to_string target
            ^ " "
            ^ Photo.Upload_state.to_string state)
            expected
            (Photo.awaiting_drive (photo target state)))
        Photo.Upload_state.all)
    Photo.Original_target.all

let tests = [Alcotest.test_case "awaiting_drive" `Quick awaiting]
