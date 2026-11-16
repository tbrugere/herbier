(* Drive.resolve_root, and put_original / start_session with a stored root:
   hand-written answers, then moves, renames, trashes and deletes over
   Fake_drive. *)

module Drive = Herbier_photos.Drive
module Ids = Herbier_domain.Ids
module Fixture = Herbier_test_support.Fixture
module Value = Herbier_test_support.Value

let fixture name = Fixture.read ("drive_" ^ name ^ ".json")
let answer = Test_drive.answer
let seq_net = Test_drive.seq_net
let check_requests = Test_drive.check_requests

(* ---------- testables ---------- *)

let root_change_t = Test_drive.root_change_t

let pp_rooted pp_a ppf (r : 'a Drive.rooted) =
  Format.fprintf ppf "{result = %a; root = %a}" pp_a r.result
    Drive.pp_root_change r.root

let rooted_t (a : 'a Alcotest.testable) : 'a Drive.rooted Alcotest.testable =
  Alcotest.testable
    (pp_rooted (Alcotest.pp a))
    (Drive.equal_rooted (Alcotest.equal a))

let string_result_rooted = rooted_t Test_drive.string_result
let put_result_rooted = rooted_t Test_drive.put_result
let start_result_rooted = rooted_t Test_drive.start_result

(* [Already_there] names a constructor of both [Drive.put] and [Drive.start]:
   these two helpers pin which type is meant, everywhere below. *)
let already_there_put (f : Drive.file) : Drive.put = Drive.Already_there f
let already_there_start (f : Drive.file) : Drive.start = Drive.Already_there f

(* ---------- targets and originals ---------- *)

let photo_id n = Value.id "photo id" Ids.Photo_id.of_string (Value.uuid7 n)
let sha256_hex = String.concat "" (List.init 4 (fun _ -> "0123456789abcdef"))
let default_species = "Digitalis purpurea"

let mk_target ?(species = default_species) n : Drive.target =
  {
    species;
    name = Printf.sprintf "2026-06-14 10.32.05 photo%d.jpg" n;
    mime = "image/jpeg";
    photo_id = photo_id n;
    sha256 = sha256_hex;
  }

let mk_original ?species n : Drive.original =
  {
    target = mk_target ?species n;
    boundary = "herbier-000102030405060708090a0b0c0d0e0f";
  }

(* ---------- resolve_root ---------- *)

let resolve_root_tests =
  [
    ( "nothing stored, nothing at the root: find then create, the new id is \
       stored",
      `Quick,
      fun () ->
        let prog = Drive.resolve_root ~stored:None in
        let responses = [answer {|{"files":[]}|}; answer {|{"id":"R1"}|}] in
        check_requests "find, create"
          [
            Drive.find_folder ~name:Drive.root_folder ~parent:Drive.Root;
            Drive.create_folder ~name:Drive.root_folder ~parent:Drive.Root;
          ]
          (Drive.requests (seq_net responses) prog);
        Alcotest.check string_result_rooted "resolve_root"
          Drive.{result = Ok "R1"; root = Store "R1"}
          (Drive.run (seq_net responses) prog) );
    ( "nothing stored, an existing Herbier at the root: found, the oldest \
       entry wins, its id is stored",
      `Quick,
      fun () ->
        let prog = Drive.resolve_root ~stored:None in
        let responses = [answer {|{"files":[{"id":"R0"},{"id":"R9"}]}|}] in
        check_requests "find alone"
          [Drive.find_folder ~name:Drive.root_folder ~parent:Drive.Root]
          (Drive.requests (seq_net responses) prog);
        Alcotest.check string_result_rooted "resolve_root"
          Drive.{result = Ok "R0"; root = Store "R0"}
          (Drive.run (seq_net responses) prog) );
    ( "a stored id that is present: kept wherever it is and whatever its name, \
       exactly one request",
      `Quick,
      fun () ->
        let prog = Drive.resolve_root ~stored:(Some "R1") in
        let responses = [answer {|{"id":"R1","trashed":false}|}] in
        check_requests "get_trashed alone"
          [Drive.get_trashed ~file_id:"R1"]
          (Drive.requests (seq_net responses) prog);
        Alcotest.check string_result_rooted "resolve_root"
          Drive.{result = Ok "R1"; root = Keep}
          (Drive.run (seq_net responses) prog) );
    ( "a stored id that is trashed: forgotten, a new Herbier found or created \
       at the root, the new id stored",
      `Quick,
      fun () ->
        let prog = Drive.resolve_root ~stored:(Some "R1") in
        let responses =
          [
            answer {|{"id":"R1","trashed":true}|};
            answer {|{"files":[]}|};
            answer {|{"id":"N1"}|};
          ]
        in
        check_requests "get_trashed, find, create"
          [
            Drive.get_trashed ~file_id:"R1";
            Drive.find_folder ~name:Drive.root_folder ~parent:Drive.Root;
            Drive.create_folder ~name:Drive.root_folder ~parent:Drive.Root;
          ]
          (Drive.requests (seq_net responses) prog);
        Alcotest.check string_result_rooted "resolve_root"
          Drive.{result = Ok "N1"; root = Store "N1"}
          (Drive.run (seq_net responses) prog) );
    ( "a stored id that is gone (404): forgotten, an older Herbier at the root \
       is adopted",
      `Quick,
      fun () ->
        let prog = Drive.resolve_root ~stored:(Some "R1") in
        let responses =
          [
            answer ~status:404 (Fake_drive.not_found_404 ());
            answer {|{"files":[{"id":"OLD"}]}|};
          ]
        in
        check_requests "get_trashed, find"
          [
            Drive.get_trashed ~file_id:"R1";
            Drive.find_folder ~name:Drive.root_folder ~parent:Drive.Root;
          ]
          (Drive.requests (seq_net responses) prog);
        Alcotest.check string_result_rooted "resolve_root"
          Drive.{result = Ok "OLD"; root = Store "OLD"}
          (Drive.run (seq_net responses) prog) );
    ( "a stored id that is trashed, and creating the replacement fails: the \
       old id is forgotten, the error is reported",
      `Quick,
      fun () ->
        let prog = Drive.resolve_root ~stored:(Some "R1") in
        let quota_body =
          {|{"error":{"code":403,"errors":[{"reason":"storageQuotaExceeded"}]}}|}
        in
        let responses =
          [
            answer {|{"id":"R1","trashed":true}|};
            answer {|{"files":[]}|};
            answer ~status:403 quota_body;
          ]
        in
        check_requests "get_trashed, find, create"
          [
            Drive.get_trashed ~file_id:"R1";
            Drive.find_folder ~name:Drive.root_folder ~parent:Drive.Root;
            Drive.create_folder ~name:Drive.root_folder ~parent:Drive.Root;
          ]
          (Drive.requests (seq_net responses) prog);
        Alcotest.check string_result_rooted "resolve_root"
          Drive.{result = Error Drive.Quota_full; root = Forget}
          (Drive.run (seq_net responses) prog) );
    ( "a stored id's get_trashed answers 401: the error is reported, nothing \
       else sent, the stored id is kept",
      `Quick,
      fun () ->
        let prog = Drive.resolve_root ~stored:(Some "R1") in
        let responses =
          [answer ~status:401 (fixture "files_get_invalid_token_401")]
        in
        check_requests "get_trashed alone"
          [Drive.get_trashed ~file_id:"R1"]
          (Drive.requests (seq_net responses) prog);
        Alcotest.check string_result_rooted "resolve_root"
          Drive.{result = Error Drive.Unauthorized; root = Keep}
          (Drive.run (seq_net responses) prog) );
    ( "a stored id's get_trashed is unreachable: Network, the stored id is kept",
      `Quick,
      fun () ->
        let prog = Drive.resolve_root ~stored:(Some "R1") in
        let responses = [Drive.Unreachable "timeout"] in
        Alcotest.check string_result_rooted "resolve_root"
          Drive.{result = Error (Drive.Network "timeout"); root = Keep}
          (Drive.run (seq_net responses) prog) );
    ( "a stored id's get_trashed answers 200 without a trashed field: \
       Malformed, the stored id is kept",
      `Quick,
      fun () ->
        let prog = Drive.resolve_root ~stored:(Some "R1") in
        let responses = [answer {|{"id":"R1"}|}] in
        Alcotest.check string_result_rooted "resolve_root"
          Drive.
            {
              result = Error (Drive.Root_folder (Drive.Malformed "trashed"));
              root = Keep;
            }
          (Drive.run (seq_net responses) prog) );
    ( "a stored id's get_trashed answers 403 appNotAuthorizedToFile: forgotten \
       as if gone, a new Herbier found or created at the root",
      `Quick,
      fun () ->
        let prog = Drive.resolve_root ~stored:(Some "R1") in
        let responses =
          [
            answer ~status:403
              {|{"error":{"code":403,"message":"The user has not granted the app 123 read access to the file R1.","errors":[{"reason":"appNotAuthorizedToFile"}]}}|};
            answer {|{"files":[]}|};
            answer {|{"id":"N1"}|};
          ]
        in
        check_requests "get_trashed, find, create"
          [
            Drive.get_trashed ~file_id:"R1";
            Drive.find_folder ~name:Drive.root_folder ~parent:Drive.Root;
            Drive.create_folder ~name:Drive.root_folder ~parent:Drive.Root;
          ]
          (Drive.requests (seq_net responses) prog);
        Alcotest.check string_result_rooted "resolve_root"
          Drive.{result = Ok "N1"; root = Store "N1"}
          (Drive.run (seq_net responses) prog) );
    ( "a stored id's get_trashed answers another 403: a root folder error \
       (Account), the stored id is kept, nothing else sent",
      `Quick,
      fun () ->
        let prog = Drive.resolve_root ~stored:(Some "R1") in
        let responses =
          [
            answer ~status:403
              {|{"error":{"code":403,"message":"m","errors":[{"reason":"somethingElse"}]}}|};
          ]
        in
        check_requests "get_trashed alone"
          [Drive.get_trashed ~file_id:"R1"]
          (Drive.requests (seq_net responses) prog);
        let r = Drive.run (seq_net responses) prog in
        let http =
          Drive.Http
            {status = 403; reason = Some "somethingElse"; message = Some "m"}
        in
        Alcotest.check string_result_rooted "resolve_root"
          Drive.{result = Error (Drive.Root_folder http); root = Keep}
          r;
        Alcotest.check Test_drive.scope_t "scope" Drive.Account
          (Drive.error_scope (Drive.Root_folder http)) );
    ( "nothing stored, the root's create answers without an id: a root folder \
       error",
      `Quick,
      fun () ->
        let prog = Drive.resolve_root ~stored:None in
        let responses = [answer {|{"files":[]}|}; answer "{}"] in
        Alcotest.check string_result_rooted "resolve_root"
          Drive.
            {
              result = Error (Drive.Root_folder (Drive.Malformed "id"));
              root = Keep;
            }
          (Drive.run (seq_net responses) prog) );
  ]

(* ---------- put_original / start_session, already there ---------- *)

let already_there_tests =
  [
    ( "start_session, a file already there, root stored: Keep, one request",
      `Quick,
      fun () ->
        let t = mk_target 10 in
        let prog = Drive.start_session ~root:(Some "R1") t in
        let resp =
          answer
            {|{"files":[{"id":"FILE0","webViewLink":"https://drive.test/FILE0"}]}|}
        in
        check_requests "find_original alone"
          [Drive.find_original ~id:t.photo_id]
          (Drive.requests (seq_net [resp]) prog);
        Alcotest.check start_result_rooted "start_session"
          Drive.
            {
              result =
                Ok
                  (already_there_start
                     {
                       Drive.id = "FILE0";
                       web_view_link = Some "https://drive.test/FILE0";
                     });
              root = Keep;
            }
          (Drive.run (seq_net [resp]) prog) );
    ( "start_session, a file already there, nothing stored: Keep, one request",
      `Quick,
      fun () ->
        let t = mk_target 11 in
        let prog = Drive.start_session ~root:None t in
        let resp =
          answer
            {|{"files":[{"id":"FILE1","webViewLink":"https://drive.test/FILE1"}]}|}
        in
        check_requests "find_original alone"
          [Drive.find_original ~id:t.photo_id]
          (Drive.requests (seq_net [resp]) prog);
        Alcotest.check start_result_rooted "start_session"
          Drive.
            {
              result =
                Ok
                  (already_there_start
                     {
                       Drive.id = "FILE1";
                       web_view_link = Some "https://drive.test/FILE1";
                     });
              root = Keep;
            }
          (Drive.run (seq_net [resp]) prog) );
    ( "put_original, a file already there, root stored: Keep, one request",
      `Quick,
      fun () ->
        let o = mk_original 12 in
        let prog = Drive.put_original ~root:(Some "R1") o in
        let resp =
          answer
            {|{"files":[{"id":"FILE2","webViewLink":"https://drive.test/FILE2"}]}|}
        in
        check_requests "find_original alone"
          [Drive.find_original ~id:o.target.photo_id]
          (Drive.requests (seq_net [resp]) prog);
        Alcotest.check put_result_rooted "put_original"
          Drive.
            {
              result =
                Ok
                  (already_there_put
                     {
                       Drive.id = "FILE2";
                       web_view_link = Some "https://drive.test/FILE2";
                     });
              root = Keep;
            }
          (Drive.run (seq_net [resp]) prog) );
    ( "put_original, a file already there, nothing stored: Keep, one request",
      `Quick,
      fun () ->
        let o = mk_original 13 in
        let prog = Drive.put_original ~root:None o in
        let resp =
          answer
            {|{"files":[{"id":"FILE3","webViewLink":"https://drive.test/FILE3"}]}|}
        in
        check_requests "find_original alone"
          [Drive.find_original ~id:o.target.photo_id]
          (Drive.requests (seq_net [resp]) prog);
        Alcotest.check put_result_rooted "put_original"
          Drive.
            {
              result =
                Ok
                  (already_there_put
                     {
                       Drive.id = "FILE3";
                       web_view_link = Some "https://drive.test/FILE3";
                     });
              root = Keep;
            }
          (Drive.run (seq_net [resp]) prog) );
  ]

(* ---------- start_session ~root, nothing already there ---------- *)

let start_session_root_tests =
  [
    ( "a stored root present: the species folder is found inside it, no \
       find_folder of the root by name",
      `Quick,
      fun () ->
        let t = mk_target 14 in
        let prog = Drive.start_session ~root:(Some "R1") t in
        let responses =
          [
            answer {|{"files":[]}|};
            answer {|{"id":"R1","trashed":false}|};
            answer {|{"files":[{"id":"S1"}]}|};
            answer ~headers:[("location", Test_drive.session_url)] "{}";
          ]
        in
        let reqs = Drive.requests (seq_net responses) prog in
        check_requests
          "find_original, get_trashed, find species, create_session"
          [
            Drive.find_original ~id:t.photo_id;
            Drive.get_trashed ~file_id:"R1";
            Drive.find_folder ~name:t.species ~parent:(Drive.Folder "R1");
            Drive.create_session
              {
                name = t.name;
                mime = t.mime;
                folder_id = "S1";
                photo_id = t.photo_id;
                sha256 = t.sha256;
              };
          ]
          reqs;
        Alcotest.(check bool)
          "never looks the root up by name" false
          (List.exists
             (Drive.equal_request
                (Drive.find_folder ~name:Drive.root_folder ~parent:Drive.Root))
             reqs);
        Alcotest.check start_result_rooted "start_session"
          Drive.
            {result = Ok (Drive.Session Test_drive.session_url); root = Keep}
          (Drive.run (seq_net responses) prog) );
    ( "nothing stored, the root is created, then the species folder fails to \
       create: the error is reported, the new root stays stored",
      `Quick,
      fun () ->
        let t = mk_target 15 in
        let prog = Drive.start_session ~root:None t in
        let responses =
          [
            answer {|{"files":[]}|};
            answer {|{"files":[]}|};
            answer {|{"id":"R1"}|};
            answer {|{"files":[]}|};
            answer ~status:500 "{}";
          ]
        in
        check_requests "stops after the species folder's create"
          [
            Drive.find_original ~id:t.photo_id;
            Drive.find_folder ~name:Drive.root_folder ~parent:Drive.Root;
            Drive.create_folder ~name:Drive.root_folder ~parent:Drive.Root;
            Drive.find_folder ~name:t.species ~parent:(Drive.Folder "R1");
            Drive.create_folder ~name:t.species ~parent:(Drive.Folder "R1");
          ]
          (Drive.requests (seq_net responses) prog);
        Alcotest.check start_result_rooted "start_session"
          Drive.{result = Error (Drive.Server 500); root = Store "R1"}
          (Drive.run (seq_net responses) prog) );
    ( "a stored root trashed, and creating its replacement fails: the error is \
       reported, the trashed id is still forgotten",
      `Quick,
      fun () ->
        let t = mk_target 17 in
        let prog = Drive.start_session ~root:(Some "R1") t in
        let responses =
          [
            answer {|{"files":[]}|};
            answer {|{"id":"R1","trashed":true}|};
            answer {|{"files":[]}|};
            answer ~status:403
              {|{"error":{"code":403,"errors":[{"reason":"storageQuotaExceeded"}]}}|};
          ]
        in
        check_requests "find_original, get_trashed, find root, create root"
          [
            Drive.find_original ~id:t.photo_id;
            Drive.get_trashed ~file_id:"R1";
            Drive.find_folder ~name:Drive.root_folder ~parent:Drive.Root;
            Drive.create_folder ~name:Drive.root_folder ~parent:Drive.Root;
          ]
          (Drive.requests (seq_net responses) prog);
        Alcotest.check start_result_rooted "start_session"
          Drive.{result = Error Drive.Quota_full; root = Forget}
          (Drive.run (seq_net responses) prog) );
  ]

(* ---------- put_original ~root, nothing already there ---------- *)

let put_original_root_tests =
  [
    ( "a stored root present: the file is uploaded into the species folder \
       found inside it",
      `Quick,
      fun () ->
        let o = mk_original 16 in
        let prog = Drive.put_original ~root:(Some "R1") o in
        let responses =
          [
            answer {|{"files":[]}|};
            answer {|{"id":"R1","trashed":false}|};
            answer {|{"files":[{"id":"S1"}]}|};
            answer {|{"id":"FILE9","webViewLink":"https://drive.test/FILE9"}|};
          ]
        in
        let upload_into_s1 =
          Drive.create_original
            {
              name = o.target.name;
              mime = o.target.mime;
              folder_id = "S1";
              photo_id = o.target.photo_id;
              sha256 = o.target.sha256;
            }
            ~boundary:o.boundary
        in
        check_requests
          "find_original, get_trashed, find species, create_original"
          [
            Drive.find_original ~id:o.target.photo_id;
            Drive.get_trashed ~file_id:"R1";
            Drive.find_folder ~name:o.target.species ~parent:(Drive.Folder "R1");
            upload_into_s1;
          ]
          (Drive.requests (seq_net responses) prog);
        Alcotest.check put_result_rooted "put_original"
          Drive.
            {
              result =
                Ok
                  (Drive.Created
                     {
                       Drive.id = "FILE9";
                       web_view_link = Some "https://drive.test/FILE9";
                     });
              root = Keep;
            }
          (Drive.run (seq_net responses) prog) );
  ]

(* ---------- moves, renames, trashes and deletes, over Fake_drive ---------- *)

let apply_root_change stored = function
  | Drive.Keep -> stored
  | Drive.Store id -> Some id
  | Drive.Forget -> None

(* One start with the stored root, and the stored root after it. *)
let start fake stored target =
  let r =
    Drive.run (Fake_drive.net fake) (Drive.start_session ~root:stored target)
  in
  (r, apply_root_change stored r.root)

let expect_ok what (r : _ Drive.rooted) =
  match r.result with
  | Ok v -> v
  | Error e ->
      Alcotest.failf "%s: unexpected error %s" what (Drive.error_to_string e)

let expect_store what (r : _ Drive.rooted) =
  match r.root with
  | Drive.Store id -> id
  | (Drive.Keep | Drive.Forget) as other ->
      Alcotest.failf "%s: expected a stored root, got %a" what
        Drive.pp_root_change other

let check_keep what (r : _ Drive.rooted) =
  Alcotest.check root_change_t (what ^ ": root is Keep") Drive.Keep r.root

(* Not trashed: after a forget, the old trashed root keeps its name next to the
   new one. *)
let folder_named fake ~name ~parent =
  match
    List.filter
      (fun (f : Fake_drive.folder) ->
        (not f.trashed) && f.name = name && f.parent = parent)
      (Fake_drive.folders fake)
  with
  | [f] -> f
  | [] ->
      Alcotest.failf "no non-trashed folder named %s under the given parent"
        name
  | _ :: _ :: _ ->
      Alcotest.failf
        "more than one non-trashed folder named %s under the given parent" name

let folders_named fake name =
  List.filter
    (fun (f : Fake_drive.folder) -> f.name = name)
    (Fake_drive.folders fake)

let moved_and_renamed () =
  let fake = Fake_drive.create () in
  let species = "Digitalis purpurea" in
  let a, stored = start fake None (mk_target ~species 1) in
  let (_ : Drive.start) = expect_ok "A" a in
  let root_id = expect_store "A" a in
  let root = folder_named fake ~name:Drive.root_folder ~parent:Drive.Root in
  Alcotest.(check string)
    "A: the stored id is the created root's id" root.id root_id;
  let spec_a = folder_named fake ~name:species ~parent:(Drive.Folder root_id) in
  Alcotest.(check (list string))
    "A: one session, into the species folder" [spec_a.id]
    (Fake_drive.sessions fake);
  let archives =
    Fake_drive.add_folder fake ~name:"Archives" ~parent:Drive.Root
  in
  Fake_drive.move fake ~id:root_id ~parent:(Drive.Folder archives);
  Fake_drive.rename fake ~id:root_id ~name:"Plantes 2026";
  let folder_count = List.length (Fake_drive.folders fake) in
  let b, stored = start fake stored (mk_target ~species 2) in
  let (_ : Drive.start) = expect_ok "B" b in
  check_keep "B" b;
  Alcotest.(check int)
    "B: no folder created" folder_count
    (List.length (Fake_drive.folders fake));
  Alcotest.(check int)
    "B: no folder named Herbier anywhere" 0
    (List.length (folders_named fake Drive.root_folder));
  Alcotest.(check (list string))
    "B: session into the same species folder" [spec_a.id; spec_a.id]
    (Fake_drive.sessions fake);
  let c, (_ : string option) =
    start fake stored (mk_target ~species:"Rosa gallica" 3)
  in
  let (_ : Drive.start) = expect_ok "C" c in
  check_keep "C" c;
  let spec_c =
    folder_named fake ~name:"Rosa gallica" ~parent:(Drive.Folder root_id)
  in
  Alcotest.(check (list string))
    "C: session into the new species folder, created inside the root"
    [spec_a.id; spec_a.id; spec_c.id]
    (Fake_drive.sessions fake)

let gone_is_forgotten ~forget () =
  let fake = Fake_drive.create () in
  let species = "Digitalis purpurea" in
  let a, stored = start fake None (mk_target ~species 1) in
  let (_ : Drive.start) = expect_ok "A" a in
  let root_id = expect_store "A" a in
  forget fake ~id:root_id;
  let d, stored = start fake stored (mk_target ~species 4) in
  let (_ : Drive.start) = expect_ok "D" d in
  let new_root_id = expect_store "D" d in
  let new_root = folder_named fake ~name:Drive.root_folder ~parent:Drive.Root in
  Alcotest.(check string)
    "D: the new id is the new Herbier folder" new_root.id new_root_id;
  let spec_d =
    folder_named fake ~name:species ~parent:(Drive.Folder new_root_id)
  in
  Alcotest.(check (option string))
    "D: its session is into the new species folder" (Some spec_d.id)
    (List.nth_opt (Fake_drive.sessions fake) 1);
  let e, (_ : string option) = start fake stored (mk_target ~species 5) in
  let (_ : Drive.start) = expect_ok "E" e in
  check_keep "E" e;
  Alcotest.(check (option string))
    "E: into the same new species folder" (Some spec_d.id)
    (List.nth_opt (Fake_drive.sessions fake) 2)

let trashed_is_forgotten () =
  gone_is_forgotten ~forget:(fun fake ~id -> Fake_drive.trash fake ~id) ()

let deleted_is_forgotten () =
  gone_is_forgotten ~forget:(fun fake ~id -> Fake_drive.delete fake ~id) ()

let renamed_root_kept () =
  let fake = Fake_drive.create () in
  let species = "Digitalis purpurea" in
  let a, stored = start fake None (mk_target ~species 1) in
  let (_ : Drive.start) = expect_ok "A" a in
  let root_id = expect_store "A" a in
  Fake_drive.rename fake ~id:root_id ~name:"Mes plantes";
  let folder_count = List.length (Fake_drive.folders fake) in
  let b, (_ : string option) = start fake stored (mk_target ~species 2) in
  let (_ : Drive.start) = expect_ok "B" b in
  check_keep "B" b;
  Alcotest.(check int)
    "B: no new Herbier folder created" folder_count
    (List.length (Fake_drive.folders fake));
  Alcotest.(check int)
    "B: no folder named Herbier anywhere" 0
    (List.length (folders_named fake Drive.root_folder))

let move_rename_trash_tests =
  [
    ("moved and renamed keeps uploads going into it", `Quick, moved_and_renamed);
    ("trashed is forgotten, a new one at the root", `Quick, trashed_is_forgotten);
    ("404 is forgotten, a new one at the root", `Quick, deleted_is_forgotten);
    ( "a renamed root still at My Drive's root is kept, not duplicated",
      `Quick,
      renamed_root_kept );
  ]

(* ---------- a picked folder as root, outside My Drive's root ---------- *)

let picked_folder_as_root () =
  let fake = Fake_drive.create () in
  let species = "Digitalis purpurea" in
  let parent_p = Fake_drive.add_folder fake ~name:"P" ~parent:Drive.Root in
  let picked =
    Fake_drive.add_folder fake ~name:"Mes plantes"
      ~parent:(Drive.Folder parent_p)
  in
  let a, stored = start fake (Some picked) (mk_target ~species 30) in
  let (_ : Drive.start) = expect_ok "A" a in
  check_keep "A" a;
  Alcotest.(check (option string))
    "A: the root is unchanged" (Some picked) stored;
  let spec = folder_named fake ~name:species ~parent:(Drive.Folder picked) in
  Alcotest.(check (list string))
    "A: one session, into the species folder inside the picked folder" [spec.id]
    (Fake_drive.sessions fake);
  Alcotest.(check int)
    "A: no folder named Herbier anywhere" 0
    (List.length (folders_named fake Drive.root_folder))

let picked_folder_moved_and_renamed () =
  let fake = Fake_drive.create () in
  let species = "Digitalis purpurea" in
  let parent_p = Fake_drive.add_folder fake ~name:"P" ~parent:Drive.Root in
  let picked =
    Fake_drive.add_folder fake ~name:"Mes plantes"
      ~parent:(Drive.Folder parent_p)
  in
  let a, stored = start fake (Some picked) (mk_target ~species 31) in
  let (_ : Drive.start) = expect_ok "A" a in
  check_keep "A" a;
  let spec_a = folder_named fake ~name:species ~parent:(Drive.Folder picked) in
  let archives =
    Fake_drive.add_folder fake ~name:"Archives" ~parent:Drive.Root
  in
  Fake_drive.move fake ~id:picked ~parent:(Drive.Folder archives);
  Fake_drive.rename fake ~id:picked ~name:"Mes plantes 2026";
  let folder_count = List.length (Fake_drive.folders fake) in
  let b, (_ : string option) = start fake stored (mk_target ~species 32) in
  let (_ : Drive.start) = expect_ok "B" b in
  check_keep "B" b;
  Alcotest.(check int)
    "B: no folder created" folder_count
    (List.length (Fake_drive.folders fake));
  Alcotest.(check (list string))
    "B: session into the same species folder" [spec_a.id; spec_a.id]
    (Fake_drive.sessions fake)

let picked_folder_gone_is_forgotten ~forget () =
  let fake = Fake_drive.create () in
  let species = "Digitalis purpurea" in
  let parent_p = Fake_drive.add_folder fake ~name:"P" ~parent:Drive.Root in
  let picked =
    Fake_drive.add_folder fake ~name:"Mes plantes"
      ~parent:(Drive.Folder parent_p)
  in
  let a, stored = start fake (Some picked) (mk_target ~species 33) in
  let (_ : Drive.start) = expect_ok "A" a in
  check_keep "A" a;
  forget fake ~id:picked;
  let d, stored = start fake stored (mk_target ~species 34) in
  let (_ : Drive.start) = expect_ok "D" d in
  let new_root_id = expect_store "D" d in
  let new_root = folder_named fake ~name:Drive.root_folder ~parent:Drive.Root in
  Alcotest.(check string)
    "D: the new id is a new Herbier folder, at My Drive's root" new_root.id
    new_root_id;
  let spec_d =
    folder_named fake ~name:species ~parent:(Drive.Folder new_root_id)
  in
  Alcotest.(check (option string))
    "D: its session is into the new species folder, inside the new root"
    (Some spec_d.id)
    (List.nth_opt (Fake_drive.sessions fake) 1);
  let e, (_ : string option) = start fake stored (mk_target ~species 35) in
  let (_ : Drive.start) = expect_ok "E" e in
  check_keep "E" e;
  Alcotest.(check (option string))
    "E: into the same new species folder" (Some spec_d.id)
    (List.nth_opt (Fake_drive.sessions fake) 2)

let picked_folder_trashed_is_forgotten () =
  picked_folder_gone_is_forgotten
    ~forget:(fun fake ~id -> Fake_drive.trash fake ~id)
    ()

let picked_folder_deleted_is_forgotten () =
  picked_folder_gone_is_forgotten
    ~forget:(fun fake ~id -> Fake_drive.delete fake ~id)
    ()

let moved_herbier_pick_then_default () =
  let fake = Fake_drive.create () in
  let species = "Digitalis purpurea" in
  let a, stored = start fake None (mk_target ~species 40) in
  let (_ : Drive.start) = expect_ok "A" a in
  let herbier = expect_store "A" a in
  let archives =
    Fake_drive.add_folder fake ~name:"Archives" ~parent:Drive.Root
  in
  Fake_drive.move fake ~id:herbier ~parent:(Drive.Folder archives);
  Fake_drive.rename fake ~id:herbier ~name:"Herbier 2026";
  let picked =
    Fake_drive.add_folder fake ~name:"Mes plantes" ~parent:Drive.Root
  in
  let ids =
    Drive.pick_root {root = stored; picked = None; default = None} ~id:picked
  in
  let b, (_ : string option) = start fake ids.root (mk_target ~species 41) in
  let (_ : Drive.start) = expect_ok "B" b in
  let ids = Drive.default_root ids in
  Alcotest.(check (option string))
    "« Par défaut »: the moved Herbier is the root again" (Some herbier)
    ids.root;
  let folder_count = List.length (Fake_drive.folders fake) in
  let c, (_ : string option) = start fake ids.root (mk_target ~species 42) in
  let (_ : Drive.start) = expect_ok "C" c in
  check_keep "C" c;
  Alcotest.(check int)
    "C: no folder created" folder_count
    (List.length (Fake_drive.folders fake));
  let spec = folder_named fake ~name:species ~parent:(Drive.Folder herbier) in
  Alcotest.(check (option string))
    "C: its session is into the moved Herbier's species folder" (Some spec.id)
    (List.nth_opt (Fake_drive.sessions fake) 2)

let picked_folder_tests =
  [
    ( "a picked folder under an arbitrary parent (not Root) is the root: the \
       species folder is created inside it, no Herbier folder is ever looked \
       up or created",
      `Quick,
      picked_folder_as_root );
    ( "a picked folder, moved and renamed in Drive, keeps uploads going into it",
      `Quick,
      picked_folder_moved_and_renamed );
    ( "a picked folder, trashed, is forgotten: the next upload goes into a new \
       Herbier folder at My Drive's root",
      `Quick,
      picked_folder_trashed_is_forgotten );
    ( "a picked folder, deleted (404), is forgotten: the same fallback",
      `Quick,
      picked_folder_deleted_is_forgotten );
    ( "Herbier moved, a pick, « Par défaut »: uploads go into the moved Herbier",
      `Quick,
      moved_herbier_pick_then_default );
  ]

(* ---------- pick_root, default_root ---------- *)

let pp_root_ids ppf (ids : Drive.root_ids) =
  let o = Format.(pp_print_option ~none:(fun ppf () -> fprintf ppf "None")) in
  Format.fprintf ppf "{root = %a; picked = %a; default = %a}"
    (o Format.pp_print_string) ids.root (o Format.pp_print_string) ids.picked
    (o Format.pp_print_string) ids.default

let root_ids_t = Alcotest.testable pp_root_ids Drive.equal_root_ids
let ids ?root ?picked ?default () : Drive.root_ids = {root; picked; default}

let root_ids_tests =
  let case name expected actual =
    (name, `Quick, fun () -> Alcotest.check root_ids_t name expected actual)
  in
  [
    case "first pick: the app's root is saved as the default"
      (ids ~root:"P" ~picked:"P" ~default:"H" ())
      (Drive.pick_root (ids ~root:"H" ()) ~id:"P");
    case "first pick with no root yet: no default"
      (ids ~root:"P" ~picked:"P" ())
      (Drive.pick_root (ids ()) ~id:"P");
    case "a second pick keeps the saved default"
      (ids ~root:"Q" ~picked:"Q" ~default:"H" ())
      (Drive.pick_root (ids ~root:"P" ~picked:"P" ~default:"H" ()) ~id:"Q");
    case
      "a pick after an upload replaced a lost pick: that new root is the \
       default"
      (ids ~root:"Q" ~picked:"Q" ~default:"N" ())
      (Drive.pick_root (ids ~root:"N" ~picked:"P" ~default:"H" ()) ~id:"Q");
    case "default while a pick is in force: back to the saved default"
      (ids ~root:"H" ())
      (Drive.default_root (ids ~root:"P" ~picked:"P" ~default:"H" ()));
    case "default with nothing saved: the root is unset" (ids ())
      (Drive.default_root (ids ~root:"P" ~picked:"P" ()));
    case "default with no pick in force: the root is kept" (ids ~root:"N" ())
      (Drive.default_root (ids ~root:"N" ~picked:"P" ~default:"H" ()));
  ]

(* ---------- same_account, choose_for_account ---------- *)

(* same_account and choose_for_account decide what one « Dossier Drive »
   write contains: the account when it changes, and the three root keys. *)

let pp_account_choice ppf (c : Drive.account_choice) =
  Format.fprintf ppf "{account = %a; ids = %a}"
    (Format.pp_print_option
       ~none:(fun ppf () -> Format.pp_print_string ppf "None")
       Format.pp_print_string)
    c.account pp_root_ids c.ids

let account_choice_t =
  Alcotest.testable pp_account_choice Drive.equal_account_choice

let same_account_tests =
  let case name ~stored email expected =
    ( name,
      `Quick,
      fun () ->
        Alcotest.(check bool)
          "same_account" expected
          (Drive.same_account ~stored email) )
  in
  [
    case "trimmed and case-insensitive: equal" ~stored:(Some " A@X.fr")
      "a@x.FR " true;
    case "nothing stored: false" ~stored:None "a@x.fr" false;
    case "a different address: false" ~stored:(Some "a@x.fr") "b@x.fr" false;
  ]

let full_ids : Drive.root_ids =
  {root = Some "p1"; picked = Some "p1"; default = Some "h0"}

let choose_for_account_tests =
  let case name ~stored ~account ~folder expected =
    ( name,
      `Quick,
      fun () ->
        Alcotest.check account_choice_t "choose_for_account" expected
          (Drive.choose_for_account full_ids ~stored ~account ~folder) )
  in
  [
    case
      "another account, no pick: the account is stored, every root id dropped"
      ~stored:(Some "old@x.fr") ~account:"new@x.fr" ~folder:None
      {
        Drive.account = Some "new@x.fr";
        ids = {root = None; picked = None; default = None};
      };
    case
      "another account, a pick: the account and the picked id are stored, the \
       old default does not survive"
      ~stored:(Some "old@x.fr") ~account:"new@x.fr" ~folder:(Some "n1")
      {
        Drive.account = Some "new@x.fr";
        ids = {root = Some "n1"; picked = Some "n1"; default = None};
      };
    case "nothing stored yet behaves like another account" ~stored:None
      ~account:"any@x.fr" ~folder:(Some "n1")
      {
        Drive.account = Some "any@x.fr";
        ids = {root = Some "n1"; picked = Some "n1"; default = None};
      };
    case
      "the same account (case-insensitive), a pick: pick_root, account not \
       rewritten"
      ~stored:(Some "old@x.fr") ~account:"OLD@x.fr" ~folder:(Some "n1")
      {
        Drive.account = None;
        ids = {root = Some "n1"; picked = Some "n1"; default = Some "h0"};
      };
    case "the same account, « Par défaut »: default_root"
      ~stored:(Some "old@x.fr") ~account:"OLD@x.fr" ~folder:None
      {
        Drive.account = None;
        ids = {root = Some "h0"; picked = None; default = None};
      };
    case "the account is trimmed before it is compared and stored"
      ~stored:(Some "old@x.fr") ~account:" new@x.fr " ~folder:None
      {
        Drive.account = Some "new@x.fr";
        ids = {root = None; picked = None; default = None};
      };
  ]

(* An install that used Drive before it had its own account: its ids are the
   signed-in account's, which seed_account stores once so they are kept. *)
let seed_account_tests =
  let case name ~stored ids ~session_email expected =
    ( name,
      `Quick,
      fun () ->
        Alcotest.(check (option string))
          "seed_account" expected
          (Drive.seed_account ~stored ids ~session_email) )
  in
  let none : Drive.root_ids = {root = None; picked = None; default = None} in
  [
    case "no account, ids, signed in: the session's email (trimmed)"
      ~stored:None full_ids ~session_email:(Some " me@x.fr ") (Some "me@x.fr");
    case "only a default id is enough" ~stored:None
      {none with default = Some "h0"}
      ~session_email:(Some "me@x.fr") (Some "me@x.fr");
    case "an account already stored: nothing" ~stored:(Some "drive@x.fr")
      full_ids ~session_email:(Some "me@x.fr") None;
    case "no ids (a new install): nothing" ~stored:None none
      ~session_email:(Some "me@x.fr") None;
    case "no session email: nothing" ~stored:None full_ids ~session_email:None
      None;
    case "a blank session email: nothing" ~stored:None full_ids
      ~session_email:(Some "  ") None;
  ]

(* Seeding stores the account the ids belong to: a later choice of that same
   account keeps them, as for any stored account. *)
let seeded_then_same_account () =
  let stored =
    Drive.seed_account ~stored:None full_ids ~session_email:(Some "me@x.fr")
  in
  Alcotest.check account_choice_t "same account after the seed keeps the ids"
    {
      Drive.account = None;
      ids = {root = Some "n1"; picked = Some "n1"; default = Some "h0"};
    }
    (Drive.choose_for_account full_ids ~stored ~account:"ME@x.fr"
       ~folder:(Some "n1"))

(* ---------- recorded fixtures (when present) ---------- *)

let id_field file fields =
  match List.assoc_opt "id" fields with
  | Some (`String id) -> id
  | _ -> Alcotest.failf "%s: no id" file

(* Runs [f ~body ~id] on the recorded fixture [name], or prints a skip line
   while it is not recorded. *)
let with_fixture_id name f =
  let file = "drive_" ^ name ^ ".json" in
  match Fixture.exists file with
  | false -> print_endline ("not recorded yet, skipped: " ^ file)
  | true -> (
      let body = fixture name in
      match Yojson.Safe.from_string body with
      | `Assoc fields -> f ~body ~id:(id_field file fields)
      | _ -> Alcotest.failf "%s: not a JSON object" file)

let present_or_moved_test name =
  ( Printf.sprintf "%s: resolve_root ~stored keeps it, one request" name,
    `Quick,
    fun () ->
      with_fixture_id name (fun ~body ~id ->
          let prog = Drive.resolve_root ~stored:(Some id) in
          let responses = [answer body] in
          check_requests "get_trashed alone"
            [Drive.get_trashed ~file_id:id]
            (Drive.requests (seq_net responses) prog);
          Alcotest.check string_result_rooted "resolve_root"
            Drive.{result = Ok id; root = Keep}
            (Drive.run (seq_net responses) prog)) )

let pp_folder_info_result = Alcotest.pp Test_drive.folder_info_result

(* A recorded files.get of a folder's metadata, through folder_info. *)
let folder_meta_test name check =
  ( Printf.sprintf "%s: folder_info decodes it" name,
    `Quick,
    fun () ->
      with_fixture_id name (fun ~body ~id ->
          let prog = Drive.folder_info ~file_id:id in
          check_requests "get_folder alone"
            [Drive.get_folder ~file_id:id]
            (Drive.requests (seq_net [answer body]) prog);
          check ~id (Drive.run (seq_net [answer body]) prog)) )

let fixture_root_tests =
  [
    present_or_moved_test "files_get_folder_present_200";
    present_or_moved_test "files_get_folder_moved_200";
    ( "files_get_folder_trashed_200: resolve_root ~stored forgets it, finds or \
       creates a new one",
      `Quick,
      fun () ->
        with_fixture_id "files_get_folder_trashed_200" (fun ~body ~id ->
            let prog = Drive.resolve_root ~stored:(Some id) in
            let responses =
              [answer body; answer {|{"files":[]}|}; answer {|{"id":"N1"}|}]
            in
            check_requests "get_trashed, find, create"
              [
                Drive.get_trashed ~file_id:id;
                Drive.find_folder ~name:Drive.root_folder ~parent:Drive.Root;
                Drive.create_folder ~name:Drive.root_folder ~parent:Drive.Root;
              ]
              (Drive.requests (seq_net responses) prog);
            Alcotest.check string_result_rooted "resolve_root"
              Drive.{result = Ok "N1"; root = Store "N1"}
              (Drive.run (seq_net responses) prog)) );
    folder_meta_test "files_get_folder_meta_usable_200" (fun ~id -> function
      | Ok (Drive.Usable {id = id'; name = (_ : string)}) ->
          Alcotest.(check string) "the folder's id" id id'
      | r -> Alcotest.failf "expected Usable, got %a" pp_folder_info_result r);
    folder_meta_test "files_get_folder_meta_trashed_200"
      (fun ~id:(_ : string) ->
        Alcotest.check Test_drive.folder_info_result "folder_info"
          (Ok Drive.Folder_trashed));
    folder_meta_test "files_get_folder_meta_not_folder_200"
      (fun ~id:(_ : string) ->
        Alcotest.check Test_drive.folder_info_result "folder_info"
          (Ok Drive.Not_a_folder));
    ( "files_get_folder_meta_unknown_404: folder_info is Ok No_access",
      `Quick,
      fun () ->
        let file = "drive_files_get_folder_meta_unknown_404.json" in
        match Fixture.exists file with
        | false -> print_endline ("not recorded yet, skipped: " ^ file)
        | true ->
            Alcotest.check Test_drive.folder_info_result "folder_info"
              (Ok Drive.No_access)
              (Drive.run
                 (seq_net
                    [
                      answer ~status:404
                        (fixture "files_get_folder_meta_unknown_404");
                    ])
                 (Drive.folder_info ~file_id:"0000000000000000000000000000000"))
    );
  ]

(* ---------- pp_root_change ---------- *)

let root_change_pp_tests =
  let case expected v =
    ( expected,
      `Quick,
      fun () ->
        Alcotest.(check string)
          "pp_root_change" expected
          (Format.asprintf "%a" Drive.pp_root_change v) )
  in
  [
    case "keep" Drive.Keep;
    case "store R1" (Drive.Store "R1");
    case "forget" Drive.Forget;
  ]
