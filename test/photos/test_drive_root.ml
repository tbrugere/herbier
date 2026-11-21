(* Drive.resolve_root, Drive.rename_root, and put_original / start_session
   with a stored root: hand-written answers, then renames, moves, trashes and
   deletes over Fake_drive. *)

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
  Format.fprintf ppf "{result = %a; root = %a; name = %a}" pp_a r.result
    Drive.pp_root_change r.root
    (Format.pp_print_option
       ~none:(fun ppf () -> Format.pp_print_string ppf "None")
       (fun ppf (s : Drive.folder_name) ->
         Format.fprintf ppf "Some %S" (s :> string)))
    r.name

let rooted_t (a : 'a Alcotest.testable) : 'a Drive.rooted Alcotest.testable =
  Alcotest.testable
    (pp_rooted (Alcotest.pp a))
    (Drive.equal_rooted (Alcotest.equal a))

let string_result_rooted = rooted_t Test_drive.string_result
let put_result_rooted = rooted_t Test_drive.put_result
let start_result_rooted = rooted_t Test_drive.start_result

let folder_name_t =
  Alcotest.testable
    (fun ppf (n : Drive.folder_name) -> Format.fprintf ppf "%S" (n :> string))
    (fun (a : Drive.folder_name) (b : Drive.folder_name) ->
      String.equal (a :> string) (b :> string))

let name_result_rooted =
  rooted_t Alcotest.(result folder_name_t Test_drive.error_t)

(* [Already_there] names a constructor of both [Drive.put] and [Drive.start]:
   these two helpers pin which type is meant, everywhere below. *)
let already_there_put (f : Drive.file) : Drive.put = Drive.Already_there f
let already_there_start (f : Drive.file) : Drive.start = Drive.Already_there f

(* ---------- roots, names and answers ---------- *)

let fname = Test_drive.fname
let root ?id ?(name = "Herbier") () : Drive.root = {id; name = fname name}

(* A get_folder / update_name 2xx answer. *)
let folder_answer ?(name = "Herbier") ?(mime = Drive.folder_mime)
    ?(trashed = false) id =
  answer
    (Yojson.Safe.to_string
       (`Assoc
          [
            ("id", `String id);
            ("name", `String name);
            ("mimeType", `String mime);
            ("trashed", `Bool trashed);
          ]))

let app_not_authorized =
  answer ~status:403
    {|{"error":{"code":403,"message":"The user has not granted the app 123 write access to the file R1.","errors":[{"reason":"appNotAuthorizedToFile"}]}}|}

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

(* A stored id that is no longer usable: forgotten, then « Herbier » (or the
   stored name) found or created at My Drive's root. *)
let gone_case title gone_answer =
  ( title,
    `Quick,
    fun () ->
      let prog = Drive.resolve_root (root ~id:"R1" ()) in
      let responses =
        [gone_answer; answer {|{"files":[]}|}; answer {|{"id":"R2"}|}]
      in
      check_requests "get_folder, find, create"
        [
          Drive.get_folder ~file_id:"R1";
          Drive.find_folder ~name:"Herbier" ~parent:Drive.Root;
          Drive.create_folder ~name:"Herbier" ~parent:Drive.Root;
        ]
        (Drive.requests (seq_net responses) prog);
      Alcotest.check string_result_rooted "resolve_root"
        {result = Ok "R2"; root = Store "R2"; name = Some (fname "Herbier")}
        (Drive.run (seq_net responses) prog) )

let resolve_root_tests =
  [
    ( "nothing stored, nothing at the root: find then create under the default \
       name, the new id and the name are stored",
      `Quick,
      fun () ->
        let prog = Drive.resolve_root (root ()) in
        let responses = [answer {|{"files":[]}|}; answer {|{"id":"R1"}|}] in
        check_requests "find, create"
          [
            Drive.find_folder ~name:"Herbier" ~parent:Drive.Root;
            Drive.create_folder ~name:"Herbier" ~parent:Drive.Root;
          ]
          (Drive.requests (seq_net responses) prog);
        Alcotest.check string_result_rooted "resolve_root"
          {result = Ok "R1"; root = Store "R1"; name = Some (fname "Herbier")}
          (Drive.run (seq_net responses) prog) );
    ( "nothing stored, a stored name: an app-made folder of that name, the \
       oldest entry wins, one request",
      `Quick,
      fun () ->
        let prog = Drive.resolve_root (root ~name:"Plantes" ()) in
        let responses = [answer {|{"files":[{"id":"P0"},{"id":"P9"}]}|}] in
        check_requests "find alone"
          [Drive.find_folder ~name:"Plantes" ~parent:Drive.Root]
          (Drive.requests (seq_net responses) prog);
        Alcotest.check string_result_rooted "resolve_root"
          {result = Ok "P0"; root = Store "P0"; name = Some (fname "Plantes")}
          (Drive.run (seq_net responses) prog) );
    ( "nothing stored, a stored name, none found: created under that name",
      `Quick,
      fun () ->
        let prog = Drive.resolve_root (root ~name:"Plantes" ()) in
        let responses = [answer {|{"files":[]}|}; answer {|{"id":"P1"}|}] in
        check_requests "find, create"
          [
            Drive.find_folder ~name:"Plantes" ~parent:Drive.Root;
            Drive.create_folder ~name:"Plantes" ~parent:Drive.Root;
          ]
          (Drive.requests (seq_net responses) prog);
        Alcotest.check string_result_rooted "resolve_root"
          {result = Ok "P1"; root = Store "P1"; name = Some (fname "Plantes")}
          (Drive.run (seq_net responses) prog) );
    ( "nothing stored, the create fails with a 500: the error, Keep, no name",
      `Quick,
      fun () ->
        let prog = Drive.resolve_root (root ~name:"Plantes" ()) in
        let responses = [answer {|{"files":[]}|}; answer ~status:500 "{}"] in
        Alcotest.check string_result_rooted "resolve_root"
          {result = Error (Drive.Server 500); root = Keep; name = None}
          (Drive.run (seq_net responses) prog) );
    ( "a stored id that is usable: kept wherever it is, its Drive name learnt, \
       exactly one get_folder",
      `Quick,
      fun () ->
        let prog = Drive.resolve_root (root ~id:"R1" ()) in
        let responses = [folder_answer ~name:"Mes plantes" "R1"] in
        check_requests "get_folder alone"
          [Drive.get_folder ~file_id:"R1"]
          (Drive.requests (seq_net responses) prog);
        Alcotest.check string_result_rooted "resolve_root"
          {result = Ok "R1"; root = Keep; name = Some (fname "Mes plantes")}
          (Drive.run (seq_net responses) prog) );
    gone_case
      "a stored id that is trashed: forgotten, a new Herbier found or created \
       at the root, the new id stored"
      (folder_answer ~trashed:true "R1");
    gone_case "a stored id that is gone (404): the same fallback"
      (answer ~status:404 (Fake_drive.not_found_404 ()));
    gone_case
      "a stored id answering 403 appNotAuthorizedToFile: the same fallback"
      app_not_authorized;
    gone_case "a stored id that is not a folder: the same fallback"
      (folder_answer ~mime:"image/jpeg" "R1");
    ( "a stored id that is gone, a stored name: the fallback looks up and \
       creates that name",
      `Quick,
      fun () ->
        let prog = Drive.resolve_root (root ~id:"R1" ~name:"Plantes" ()) in
        let responses =
          [
            folder_answer ~trashed:true ~name:"Plantes" "R1";
            answer {|{"files":[]}|};
            answer {|{"id":"R2"}|};
          ]
        in
        check_requests "get_folder, find Plantes, create Plantes"
          [
            Drive.get_folder ~file_id:"R1";
            Drive.find_folder ~name:"Plantes" ~parent:Drive.Root;
            Drive.create_folder ~name:"Plantes" ~parent:Drive.Root;
          ]
          (Drive.requests (seq_net responses) prog);
        Alcotest.check string_result_rooted "resolve_root"
          {result = Ok "R2"; root = Store "R2"; name = Some (fname "Plantes")}
          (Drive.run (seq_net responses) prog) );
    ( "a stored id that is gone (404): an older app-made folder of the name is \
       adopted",
      `Quick,
      fun () ->
        let prog = Drive.resolve_root (root ~id:"R1" ()) in
        let responses =
          [
            answer ~status:404 (Fake_drive.not_found_404 ());
            answer {|{"files":[{"id":"OLD"}]}|};
          ]
        in
        check_requests "get_folder, find"
          [
            Drive.get_folder ~file_id:"R1";
            Drive.find_folder ~name:"Herbier" ~parent:Drive.Root;
          ]
          (Drive.requests (seq_net responses) prog);
        Alcotest.check string_result_rooted "resolve_root"
          {result = Ok "OLD"; root = Store "OLD"; name = Some (fname "Herbier")}
          (Drive.run (seq_net responses) prog) );
    ( "a stored id that is trashed, and creating the replacement fails: the \
       old id is forgotten, the error reported, no name",
      `Quick,
      fun () ->
        let prog = Drive.resolve_root (root ~id:"R1" ()) in
        let responses =
          [
            folder_answer ~trashed:true "R1";
            answer {|{"files":[]}|};
            answer ~status:403
              {|{"error":{"code":403,"errors":[{"reason":"storageQuotaExceeded"}]}}|};
          ]
        in
        Alcotest.check string_result_rooted "resolve_root"
          {result = Error Drive.Quota_full; root = Forget; name = None}
          (Drive.run (seq_net responses) prog) );
    ( "a stored id's get_folder answers 401 (recorded): the error, nothing \
       else sent, the stored id kept",
      `Quick,
      fun () ->
        let prog = Drive.resolve_root (root ~id:"R1" ()) in
        let responses =
          [
            answer ~status:401
              (fixture "files_get_folder_meta_invalid_token_401");
          ]
        in
        check_requests "get_folder alone"
          [Drive.get_folder ~file_id:"R1"]
          (Drive.requests (seq_net responses) prog);
        Alcotest.check string_result_rooted "resolve_root"
          {result = Error Drive.Unauthorized; root = Keep; name = None}
          (Drive.run (seq_net responses) prog) );
    ( "a stored id's get_folder is unreachable: Network, the stored id kept",
      `Quick,
      fun () ->
        let prog = Drive.resolve_root (root ~id:"R1" ()) in
        let responses = [Drive.Unreachable "timeout"] in
        Alcotest.check string_result_rooted "resolve_root"
          {result = Error (Drive.Network "timeout"); root = Keep; name = None}
          (Drive.run (seq_net responses) prog) );
    ( "a stored id's get_folder answers 200 without trashed: a root folder \
       Malformed, the stored id kept",
      `Quick,
      fun () ->
        let prog = Drive.resolve_root (root ~id:"R1" ()) in
        let responses =
          [
            answer
              {|{"id":"R1","name":"Herbier","mimeType":"application/vnd.google-apps.folder"}|};
          ]
        in
        Alcotest.check string_result_rooted "resolve_root"
          {
            result = Error (Drive.Root_folder (Drive.Malformed "trashed"));
            root = Keep;
            name = None;
          }
          (Drive.run (seq_net responses) prog) );
    ( "a stored id's get_folder answers another 403: a root folder error \
       (Account), the stored id kept, nothing else sent",
      `Quick,
      fun () ->
        let prog = Drive.resolve_root (root ~id:"R1" ()) in
        let responses =
          [
            answer ~status:403
              {|{"error":{"code":403,"message":"m","errors":[{"reason":"somethingElse"}]}}|};
          ]
        in
        check_requests "get_folder alone"
          [Drive.get_folder ~file_id:"R1"]
          (Drive.requests (seq_net responses) prog);
        let http =
          Drive.Http
            {status = 403; reason = Some "somethingElse"; message = Some "m"}
        in
        Alcotest.check string_result_rooted "resolve_root"
          {result = Error (Drive.Root_folder http); root = Keep; name = None}
          (Drive.run (seq_net responses) prog);
        Alcotest.check Test_drive.scope_t "scope" Drive.Account
          (Drive.error_scope (Drive.Root_folder http)) );
    ( "nothing stored, the root's create answers without an id: a root folder \
       error",
      `Quick,
      fun () ->
        let prog = Drive.resolve_root (root ()) in
        let responses = [answer {|{"files":[]}|}; answer "{}"] in
        Alcotest.check string_result_rooted "resolve_root"
          {
            result = Error (Drive.Root_folder (Drive.Malformed "id"));
            root = Keep;
            name = None;
          }
          (Drive.run (seq_net responses) prog) );
  ]

(* ---------- put_original / start_session, already there ---------- *)

let file0 n : Drive.file =
  {
    id = Printf.sprintf "FILE%d" n;
    web_view_link = Some (Printf.sprintf "https://drive.test/FILE%d" n);
  }

let files_answer n =
  answer
    (Printf.sprintf
       {|{"files":[{"id":"FILE%d","webViewLink":"https://drive.test/FILE%d"}]}|}
       n n)

let already_there_tests =
  let start_case title r n =
    ( title,
      `Quick,
      fun () ->
        let t = mk_target (10 + n) in
        let prog = Drive.start_session ~root:r t in
        check_requests "find_original alone"
          [Drive.find_original ~id:t.photo_id]
          (Drive.requests (seq_net [files_answer n]) prog);
        Alcotest.check start_result_rooted "start_session"
          {
            result = Ok (already_there_start (file0 n));
            root = Keep;
            name = None;
          }
          (Drive.run (seq_net [files_answer n]) prog) )
  in
  let put_case title r n =
    ( title,
      `Quick,
      fun () ->
        let o = mk_original (10 + n) in
        let prog = Drive.put_original ~root:r o in
        check_requests "find_original alone"
          [Drive.find_original ~id:o.target.photo_id]
          (Drive.requests (seq_net [files_answer n]) prog);
        Alcotest.check put_result_rooted "put_original"
          {result = Ok (already_there_put (file0 n)); root = Keep; name = None}
          (Drive.run (seq_net [files_answer n]) prog) )
  in
  [
    start_case
      "start_session, a file already there, root stored: Keep, no name, one \
       request"
      (root ~id:"R1" ()) 0;
    start_case
      "start_session, a file already there, nothing stored: Keep, no name, one \
       request"
      (root ~name:"Plantes" ()) 1;
    put_case
      "put_original, a file already there, root stored: Keep, no name, one \
       request"
      (root ~id:"R1" ()) 2;
    put_case
      "put_original, a file already there, nothing stored: Keep, no name, one \
       request"
      (root ()) 3;
  ]

(* ---------- start_session ~root, nothing already there ---------- *)

let session_metadata (t : Drive.target) folder_id : Drive.metadata =
  {
    name = t.name;
    mime = t.mime;
    folder_id;
    photo_id = t.photo_id;
    sha256 = t.sha256;
  }

let start_session_root_tests =
  [
    ( "a stored root usable: the species folder is found inside it, no \
       find_folder of the root by name, the Drive name reported",
      `Quick,
      fun () ->
        let t = mk_target 14 in
        let prog = Drive.start_session ~root:(root ~id:"R1" ()) t in
        let responses =
          [
            answer {|{"files":[]}|};
            folder_answer ~name:"Plantes 2026" "R1";
            answer {|{"files":[{"id":"S1"}]}|};
            answer ~headers:[("location", Test_drive.session_url)] "{}";
          ]
        in
        let reqs = Drive.requests (seq_net responses) prog in
        check_requests "find_original, get_folder, find species, create_session"
          [
            Drive.find_original ~id:t.photo_id;
            Drive.get_folder ~file_id:"R1";
            Drive.find_folder ~name:t.species ~parent:(Drive.Folder "R1");
            Drive.create_session (session_metadata t "S1");
          ]
          reqs;
        Alcotest.(check bool)
          "never looks the root up by name" false
          (List.exists
             (Drive.equal_request
                (Drive.find_folder ~name:"Herbier" ~parent:Drive.Root))
             reqs);
        Alcotest.check start_result_rooted "start_session"
          {
            result = Ok (Drive.Session Test_drive.session_url);
            root = Keep;
            name = Some (fname "Plantes 2026");
          }
          (Drive.run (seq_net responses) prog) );
    ( "nothing stored, a stored name: the root is looked up and created under \
       that name",
      `Quick,
      fun () ->
        let t = mk_target 18 in
        let prog = Drive.start_session ~root:(root ~name:"Plantes" ()) t in
        let responses =
          [
            answer {|{"files":[]}|};
            answer {|{"files":[]}|};
            answer {|{"id":"P1"}|};
            answer {|{"files":[{"id":"S1"}]}|};
            answer ~headers:[("location", Test_drive.session_url)] "{}";
          ]
        in
        check_requests
          "find_original, find Plantes, create Plantes, species, session"
          [
            Drive.find_original ~id:t.photo_id;
            Drive.find_folder ~name:"Plantes" ~parent:Drive.Root;
            Drive.create_folder ~name:"Plantes" ~parent:Drive.Root;
            Drive.find_folder ~name:t.species ~parent:(Drive.Folder "P1");
            Drive.create_session (session_metadata t "S1");
          ]
          (Drive.requests (seq_net responses) prog);
        Alcotest.check start_result_rooted "start_session"
          {
            result = Ok (Drive.Session Test_drive.session_url);
            root = Store "P1";
            name = Some (fname "Plantes");
          }
          (Drive.run (seq_net responses) prog) );
    ( "nothing stored, the root is created, then the species folder fails to \
       create: the error, the new root and its name still stored",
      `Quick,
      fun () ->
        let t = mk_target 15 in
        let prog = Drive.start_session ~root:(root ()) t in
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
            Drive.find_folder ~name:"Herbier" ~parent:Drive.Root;
            Drive.create_folder ~name:"Herbier" ~parent:Drive.Root;
            Drive.find_folder ~name:t.species ~parent:(Drive.Folder "R1");
            Drive.create_folder ~name:t.species ~parent:(Drive.Folder "R1");
          ]
          (Drive.requests (seq_net responses) prog);
        Alcotest.check start_result_rooted "start_session"
          {
            result = Error (Drive.Server 500);
            root = Store "R1";
            name = Some (fname "Herbier");
          }
          (Drive.run (seq_net responses) prog) );
    ( "a stored root usable, then the species lookup fails: Keep and the \
       learnt name survive the error",
      `Quick,
      fun () ->
        let t = mk_target 19 in
        let prog = Drive.start_session ~root:(root ~id:"R1" ()) t in
        let responses =
          [
            answer {|{"files":[]}|};
            folder_answer ~name:"Autre" "R1";
            answer ~status:503 "{}";
          ]
        in
        Alcotest.check start_result_rooted "start_session"
          {
            result = Error (Drive.Server 503);
            root = Keep;
            name = Some (fname "Autre");
          }
          (Drive.run (seq_net responses) prog) );
    ( "a stored root trashed, and creating its replacement fails: the error, \
       the trashed id still forgotten",
      `Quick,
      fun () ->
        let t = mk_target 17 in
        let prog = Drive.start_session ~root:(root ~id:"R1" ()) t in
        let responses =
          [
            answer {|{"files":[]}|};
            folder_answer ~trashed:true "R1";
            answer {|{"files":[]}|};
            answer ~status:403
              {|{"error":{"code":403,"errors":[{"reason":"storageQuotaExceeded"}]}}|};
          ]
        in
        check_requests "find_original, get_folder, find root, create root"
          [
            Drive.find_original ~id:t.photo_id;
            Drive.get_folder ~file_id:"R1";
            Drive.find_folder ~name:"Herbier" ~parent:Drive.Root;
            Drive.create_folder ~name:"Herbier" ~parent:Drive.Root;
          ]
          (Drive.requests (seq_net responses) prog);
        Alcotest.check start_result_rooted "start_session"
          {result = Error Drive.Quota_full; root = Forget; name = None}
          (Drive.run (seq_net responses) prog) );
  ]

(* ---------- put_original ~root, nothing already there ---------- *)

let put_original_root_tests =
  [
    ( "a stored root usable: the file is uploaded into the species folder \
       found inside it, the Drive name reported",
      `Quick,
      fun () ->
        let o = mk_original 16 in
        let prog = Drive.put_original ~root:(root ~id:"R1" ()) o in
        let responses =
          [
            answer {|{"files":[]}|};
            folder_answer "R1";
            answer {|{"files":[{"id":"S1"}]}|};
            answer {|{"id":"FILE9","webViewLink":"https://drive.test/FILE9"}|};
          ]
        in
        let upload_into_s1 =
          Drive.create_original
            (session_metadata o.target "S1")
            ~boundary:o.boundary
        in
        check_requests
          "find_original, get_folder, find species, create_original"
          [
            Drive.find_original ~id:o.target.photo_id;
            Drive.get_folder ~file_id:"R1";
            Drive.find_folder ~name:o.target.species ~parent:(Drive.Folder "R1");
            upload_into_s1;
          ]
          (Drive.requests (seq_net responses) prog);
        Alcotest.check put_result_rooted "put_original"
          {
            result =
              Ok
                (Drive.Created
                   {
                     Drive.id = "FILE9";
                     web_view_link = Some "https://drive.test/FILE9";
                   });
            root = Keep;
            name = Some (fname "Herbier");
          }
          (Drive.run (seq_net responses) prog) );
  ]

(* ---------- rename_root ---------- *)

let rename_case ?(id = "R1") title responses ~expected_requests expected =
  ( title,
    `Quick,
    fun () ->
      let prog = Drive.rename_root (root ~id ()) ~name:(fname "Plantes") in
      check_requests "requests" expected_requests
        (Drive.requests (seq_net responses) prog);
      Alcotest.check name_result_rooted "rename_root" expected
        (Drive.run (seq_net responses) prog) )

let patch_r1 = Drive.update_name ~file_id:"R1" ~name:(fname "Plantes")
let find_plantes = Drive.find_folder ~name:"Plantes" ~parent:Drive.Root
let find_herbier = Drive.find_folder ~name:"Herbier" ~parent:Drive.Root
let create_plantes = Drive.create_folder ~name:"Plantes" ~parent:Drive.Root

(* The folder is gone: an app-made « Plantes » at the root is created. *)
let gone_rename_case title gone_answer =
  rename_case title
    [gone_answer; answer {|{"files":[]}|}; answer {|{"id":"R2"}|}]
    ~expected_requests:[patch_r1; find_plantes; create_plantes]
    {
      result = Ok (fname "Plantes");
      root = Store "R2";
      name = Some (fname "Plantes");
    }

let rename_root_tests =
  [
    rename_case
      "a usable root: exactly one PATCH, Ok with Drive's name, Keep, the name \
       learnt"
      [folder_answer ~name:"Plantes" "R1"]
      ~expected_requests:[patch_r1]
      {
        result = Ok (fname "Plantes");
        root = Keep;
        name = Some (fname "Plantes");
      };
    rename_case
      "the answer's name wins over the asked one (Drive is the source of truth)"
      [folder_answer ~name:"Plantes (1)" "R1"]
      ~expected_requests:[patch_r1]
      {
        result = Ok (fname "Plantes (1)");
        root = Keep;
        name = Some (fname "Plantes (1)");
      };
    gone_rename_case
      "a trashed answer: the folder is gone, Plantes found or created at the \
       root, stored"
      (folder_answer ~name:"Plantes" ~trashed:true "R1");
    gone_rename_case "a not-a-folder answer: the same fallback"
      (folder_answer ~name:"Plantes" ~mime:"image/jpeg" "R1");
    gone_rename_case "a 404: the same fallback"
      (answer ~status:404 (Fake_drive.not_found_404 ()));
    gone_rename_case "a 403 appNotAuthorizedToFile: the same fallback"
      app_not_authorized;
    rename_case
      "gone, an app-made Plantes already at the root: adopted, nothing created"
      [
        answer ~status:404 (Fake_drive.not_found_404 ());
        answer {|{"files":[{"id":"P0"},{"id":"P9"}]}|};
      ]
      ~expected_requests:[patch_r1; find_plantes]
      {
        result = Ok (fname "Plantes");
        root = Store "P0";
        name = Some (fname "Plantes");
      };
    rename_case
      "gone, and the fallback's create fails with a 500: the error, the old id \
       forgotten, no name"
      [
        answer ~status:404 (Fake_drive.not_found_404 ());
        answer {|{"files":[]}|};
        answer ~status:500 "{}";
      ]
      ~expected_requests:[patch_r1; find_plantes; create_plantes]
      {result = Error (Drive.Server 500); root = Forget; name = None};
    rename_case "a 401 (recorded): Unauthorized, Keep, one request"
      [answer ~status:401 (fixture "files_update_name_invalid_token_401")]
      ~expected_requests:[patch_r1]
      {result = Error Drive.Unauthorized; root = Keep; name = None};
    rename_case
      "a 403 insufficientPermissions: Scope_missing, not wrapped in Root_folder"
      [
        answer ~status:403
          {|{"error":{"code":403,"errors":[{"reason":"insufficientPermissions"}]}}|};
      ]
      ~expected_requests:[patch_r1]
      {result = Error Drive.Scope_missing; root = Keep; name = None};
    rename_case "a 500: Server 500, Keep"
      [answer ~status:500 "{}"]
      ~expected_requests:[patch_r1]
      {result = Error (Drive.Server 500); root = Keep; name = None};
    rename_case "another 403: Http, not wrapped in Root_folder"
      [
        answer ~status:403
          {|{"error":{"code":403,"message":"m","errors":[{"reason":"somethingElse"}]}}|};
      ]
      ~expected_requests:[patch_r1]
      {
        result =
          Error
            (Drive.Http
               {status = 403; reason = Some "somethingElse"; message = Some "m"});
        root = Keep;
        name = None;
      };
    rename_case "unreachable: Network, Keep" [Drive.Unreachable "x"]
      ~expected_requests:[patch_r1]
      {result = Error (Drive.Network "x"); root = Keep; name = None};
    rename_case "a 2xx that is not JSON: Malformed, not wrapped, Keep"
      [answer "<html>"]
      ~expected_requests:[patch_r1]
      {result = Error (Drive.Malformed "not JSON"); root = Keep; name = None};
    ( "no root stored, no Herbier at the root: Plantes looked up then created, \
       stored",
      `Quick,
      fun () ->
        let prog = Drive.rename_root (root ()) ~name:(fname "Plantes") in
        let responses =
          [
            answer {|{"files":[]}|};
            answer {|{"files":[]}|};
            answer {|{"id":"P1"}|};
          ]
        in
        check_requests "find Herbier, find Plantes, create"
          [find_herbier; find_plantes; create_plantes]
          (Drive.requests (seq_net responses) prog);
        Alcotest.check name_result_rooted "rename_root"
          {
            result = Ok (fname "Plantes");
            root = Store "P1";
            name = Some (fname "Plantes");
          }
          (Drive.run (seq_net responses) prog) );
    ( "no root stored, no Herbier, a Plantes found: adopted",
      `Quick,
      fun () ->
        let prog = Drive.rename_root (root ()) ~name:(fname "Plantes") in
        let responses =
          [answer {|{"files":[]}|}; answer {|{"files":[{"id":"P0"}]}|}]
        in
        check_requests "find Herbier, find Plantes"
          [find_herbier; find_plantes]
          (Drive.requests (seq_net responses) prog);
        Alcotest.check name_result_rooted "rename_root"
          {
            result = Ok (fname "Plantes");
            root = Store "P0";
            name = Some (fname "Plantes");
          }
          (Drive.run (seq_net responses) prog) );
    ( "no root stored, the app's Herbier at the root: that one renamed and \
       stored, nothing created",
      `Quick,
      fun () ->
        let prog = Drive.rename_root (root ()) ~name:(fname "Plantes") in
        let responses =
          [
            answer {|{"files":[{"id":"H0"},{"id":"H9"}]}|};
            folder_answer ~name:"Plantes" "H0";
          ]
        in
        check_requests "find Herbier, one PATCH of it"
          [
            find_herbier; Drive.update_name ~file_id:"H0" ~name:(fname "Plantes");
          ]
          (Drive.requests (seq_net responses) prog);
        Alcotest.check name_result_rooted "rename_root"
          {
            result = Ok (fname "Plantes");
            root = Store "H0";
            name = Some (fname "Plantes");
          }
          (Drive.run (seq_net responses) prog) );
    ( "no root stored, Herbier found, the PATCH fails: the error, Herbier \
       stored anyway, no name",
      `Quick,
      fun () ->
        let prog = Drive.rename_root (root ()) ~name:(fname "Plantes") in
        let responses =
          [answer {|{"files":[{"id":"H0"}]}|}; answer ~status:500 "{}"]
        in
        Alcotest.check name_result_rooted "rename_root"
          {result = Error (Drive.Server 500); root = Store "H0"; name = None}
          (Drive.run (seq_net responses) prog) );
    ( "no root stored, the Herbier found is gone by the PATCH: Plantes found \
       or created, nothing forgotten on error",
      `Quick,
      fun () ->
        let prog = Drive.rename_root (root ()) ~name:(fname "Plantes") in
        let responses =
          [
            answer {|{"files":[{"id":"H0"}]}|};
            answer ~status:404 (Fake_drive.not_found_404 ());
            answer {|{"files":[]}|};
            answer ~status:500 "{}";
          ]
        in
        Alcotest.check name_result_rooted "rename_root"
          {result = Error (Drive.Server 500); root = Keep; name = None}
          (Drive.run (seq_net responses) prog) );
    ( "no root stored, the name unchanged: Herbier found or created, no PATCH",
      `Quick,
      fun () ->
        let prog = Drive.rename_root (root ()) ~name:(fname "Herbier") in
        let responses = [answer {|{"files":[{"id":"H0"}]}|}] in
        check_requests "find alone" [find_herbier]
          (Drive.requests (seq_net responses) prog);
        Alcotest.check name_result_rooted "rename_root"
          {
            result = Ok (fname "Herbier");
            root = Store "H0";
            name = Some (fname "Herbier");
          }
          (Drive.run (seq_net responses) prog) );
    ( "no root stored, the lookup fails: the error, Keep",
      `Quick,
      fun () ->
        let prog = Drive.rename_root (root ()) ~name:(fname "Plantes") in
        let responses = [answer ~status:500 "{}"] in
        Alcotest.check name_result_rooted "rename_root"
          {result = Error (Drive.Server 500); root = Keep; name = None}
          (Drive.run (seq_net responses) prog) );
    ( "no root stored, the create fails: the error, Keep (nothing to forget)",
      `Quick,
      fun () ->
        let prog = Drive.rename_root (root ()) ~name:(fname "Plantes") in
        let responses =
          [
            answer {|{"files":[]}|};
            answer {|{"files":[]}|};
            answer ~status:500 "{}";
          ]
        in
        Alcotest.check name_result_rooted "rename_root"
          {result = Error (Drive.Server 500); root = Keep; name = None}
          (Drive.run (seq_net responses) prog) );
  ]

(* ---------- name_to_store ---------- *)

let name_to_store_tests =
  let case title ~stored_name learnt expected =
    ( title,
      `Quick,
      fun () ->
        Alcotest.(check (option string))
          "name_to_store" expected
          (Option.map
             (fun (n : Drive.folder_name) -> (n :> string))
             (Drive.name_to_store ~stored_name (Option.map fname learnt))) )
  in
  [
    case "nothing learnt: nothing" ~stored_name:(Some "Herbier") None None;
    case "the stored name, padded: nothing" ~stored_name:(Some " Plantes ")
      (Some "Plantes") None;
    case "a blank stored name: the learnt one" ~stored_name:(Some "  ")
      (Some "Plantes") (Some "Plantes");
    case "another name: the learnt one" ~stored_name:(Some "Herbier")
      (Some "Plantes") (Some "Plantes");
    case "nothing stored: the learnt one" ~stored_name:None (Some "Herbier")
      (Some "Herbier");
  ]

(* ---------- renames, moves, trashes and deletes, over Fake_drive ---------- *)

let apply_root_change stored = function
  | Drive.Keep -> stored
  | Drive.Store id -> Some id
  | Drive.Forget -> None

(* The root as the app would store it after a run: the id change, and the
   name Drive.name_to_store gives. *)
let apply (r : _ Drive.rooted) (stored : Drive.root) : Drive.root =
  {
    id = apply_root_change stored.id r.root;
    name =
      Option.value
        (Drive.name_to_store ~stored_name:(Some (stored.name :> string)) r.name)
        ~default:stored.name;
  }

(* One start with the stored root, and the stored root after it. *)
let start fake stored target =
  let r =
    Drive.run (Fake_drive.net fake) (Drive.start_session ~root:stored target)
  in
  (r, apply r stored)

let rename fake stored name =
  let r =
    Drive.run (Fake_drive.net fake)
      (Drive.rename_root stored ~name:(fname name))
  in
  (r, apply r stored)

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

let check_name what expected (r : _ Drive.rooted) =
  Alcotest.(check (option string))
    (what ^ ": name reported") expected
    (Option.map (fun (n : Drive.folder_name) -> (n :> string)) r.name)

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

let folder_by_id fake id =
  match
    List.find_opt
      (fun (f : Fake_drive.folder) -> f.id = id)
      (Fake_drive.folders fake)
  with
  | Some f -> f
  | None -> Alcotest.failf "no folder %s in the fake" id

(* A rename in the app, a move in Drive, a rename in Drive, a trash in Drive,
   each followed by an upload. *)
let rename_keeps_uploads () =
  let fake = Fake_drive.create () in
  let species = "Digitalis purpurea" in
  let a, stored = start fake (root ()) (mk_target ~species 1) in
  let (_ : Drive.start) = expect_ok "A" a in
  let f1 = expect_store "A" a in
  check_name "A" (Some "Herbier") a;
  let spec_a = folder_named fake ~name:species ~parent:(Drive.Folder f1) in
  let r, stored = rename fake stored "Plantes" in
  Alcotest.check name_result_rooted "rename"
    {result = Ok (fname "Plantes"); root = Keep; name = Some (fname "Plantes")}
    r;
  Alcotest.(check string)
    "the fake's root folder is now named Plantes" "Plantes"
    (folder_by_id fake f1).name;
  let other = Fake_drive.add_folder fake ~name:"Archives" ~parent:Drive.Root in
  Fake_drive.move fake ~id:f1 ~parent:(Drive.Folder other);
  let folder_count = List.length (Fake_drive.folders fake) in
  let b, stored = start fake stored (mk_target ~species 2) in
  let (_ : Drive.start) = expect_ok "B" b in
  check_keep "B" b;
  check_name "B" (Some "Plantes") b;
  Alcotest.(check int)
    "B: no folder created" folder_count
    (List.length (Fake_drive.folders fake));
  Alcotest.(check (list string))
    "B: session into the same species folder, inside the moved root"
    [spec_a.id; spec_a.id] (Fake_drive.sessions fake);
  let c, stored = start fake stored (mk_target ~species:"Rosa gallica" 3) in
  let (_ : Drive.start) = expect_ok "C" c in
  check_keep "C" c;
  let spec_c =
    folder_named fake ~name:"Rosa gallica" ~parent:(Drive.Folder f1)
  in
  Alcotest.(check (list string))
    "C: a new species folder, created inside the moved root"
    [spec_a.id; spec_a.id; spec_c.id]
    (Fake_drive.sessions fake);
  Fake_drive.rename fake ~id:f1 ~name:"Autre";
  let d, stored = start fake stored (mk_target ~species 4) in
  let (_ : Drive.start) = expect_ok "D" d in
  check_keep "D" d;
  check_name "D: a rename done in Drive is learnt" (Some "Autre") d;
  Fake_drive.trash fake ~id:f1;
  let e, (_ : Drive.root) = start fake stored (mk_target ~species 5) in
  let (_ : Drive.start) = expect_ok "E" e in
  let new_root = expect_store "E" e in
  check_name "E" (Some "Autre") e;
  Alcotest.(check string)
    "E: the new root is created under the stored name, at My Drive's root"
    (folder_named fake ~name:"Autre" ~parent:Drive.Root).id new_root

let gone_is_forgotten ~forget () =
  let fake = Fake_drive.create () in
  let species = "Digitalis purpurea" in
  let a, stored = start fake (root ()) (mk_target ~species 1) in
  let (_ : Drive.start) = expect_ok "A" a in
  let root_id = expect_store "A" a in
  forget fake ~id:root_id;
  let d, stored = start fake stored (mk_target ~species 4) in
  let (_ : Drive.start) = expect_ok "D" d in
  let new_root_id = expect_store "D" d in
  let new_root = folder_named fake ~name:"Herbier" ~parent:Drive.Root in
  Alcotest.(check string)
    "D: the new id is the new Herbier folder" new_root.id new_root_id;
  let spec_d =
    folder_named fake ~name:species ~parent:(Drive.Folder new_root_id)
  in
  Alcotest.(check (option string))
    "D: its session is into the new species folder" (Some spec_d.id)
    (List.nth_opt (Fake_drive.sessions fake) 1);
  let e, (_ : Drive.root) = start fake stored (mk_target ~species 5) in
  let (_ : Drive.start) = expect_ok "E" e in
  check_keep "E" e;
  Alcotest.(check (option string))
    "E: into the same new species folder" (Some spec_d.id)
    (List.nth_opt (Fake_drive.sessions fake) 2)

(* A folder picked before migration 6 and kept by it: under an arbitrary
   parent, with its own name; it stays the root while it answers. *)
let former_pick_kept () =
  let fake = Fake_drive.create () in
  let species = "Digitalis purpurea" in
  let parent_p = Fake_drive.add_folder fake ~name:"P" ~parent:Drive.Root in
  let picked =
    Fake_drive.add_folder fake ~name:"Mes plantes"
      ~parent:(Drive.Folder parent_p)
  in
  let a, stored =
    start fake (root ~id:picked ~name:"Mes plantes" ()) (mk_target ~species 30)
  in
  let (_ : Drive.start) = expect_ok "A" a in
  check_keep "A" a;
  check_name "A" (Some "Mes plantes") a;
  Alcotest.(check (option string))
    "A: the root is unchanged" (Some picked) stored.id;
  let spec = folder_named fake ~name:species ~parent:(Drive.Folder picked) in
  Alcotest.(check (list string))
    "A: one session, into the species folder inside the picked folder" [spec.id]
    (Fake_drive.sessions fake);
  Alcotest.(check int)
    "A: no folder named Herbier anywhere" 0
    (List.length (folders_named fake "Herbier"))

(* A former pick no longer reachable: a new folder under its name, at My
   Drive's root. *)
let former_pick_gone () =
  let fake = Fake_drive.create () in
  let species = "Digitalis purpurea" in
  let parent_p = Fake_drive.add_folder fake ~name:"P" ~parent:Drive.Root in
  let picked =
    Fake_drive.add_folder fake ~name:"Mes plantes"
      ~parent:(Drive.Folder parent_p)
  in
  Fake_drive.delete fake ~id:picked;
  let a, (_ : Drive.root) =
    start fake (root ~id:picked ~name:"Mes plantes" ()) (mk_target ~species 31)
  in
  let (_ : Drive.start) = expect_ok "A" a in
  let new_root = expect_store "A" a in
  check_name "A" (Some "Mes plantes") a;
  Alcotest.(check string)
    "A: a new « Mes plantes » at My Drive's root"
    (folder_named fake ~name:"Mes plantes" ~parent:Drive.Root).id new_root

let rename_scenario_tests =
  [
    ( "rename in the app, move and rename in Drive, trash: uploads follow the \
       root, its name is learnt, a lost root is re-created under the stored \
       name",
      `Quick,
      rename_keeps_uploads );
    ( "trashed is forgotten, a new one at the root",
      `Quick,
      gone_is_forgotten ~forget:(fun fake ~id -> Fake_drive.trash fake ~id) );
    ( "deleted (404) is forgotten, a new one at the root",
      `Quick,
      gone_is_forgotten ~forget:(fun fake ~id -> Fake_drive.delete fake ~id) );
    ( "a former pick outside My Drive's root stays the root while it answers",
      `Quick,
      former_pick_kept );
    ( "a former pick that is gone: a new folder under its name at the root",
      `Quick,
      former_pick_gone );
    ( "rename over the fake: an unknown id falls back to creating the name",
      `Quick,
      fun () ->
        let fake = Fake_drive.create () in
        let r, (_ : Drive.root) = rename fake (root ~id:"NOPE" ()) "Plantes" in
        let id = expect_store "rename" r in
        Alcotest.check name_result_rooted "rename"
          {
            result = Ok (fname "Plantes");
            root = Store id;
            name = Some (fname "Plantes");
          }
          r;
        Alcotest.(check string)
          "the created folder is Plantes at the root"
          (folder_named fake ~name:"Plantes" ~parent:Drive.Root).id id );
  ]

(* ---------- same_account, account_to_store ---------- *)

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

let account_to_store_tests =
  let case name ~stored ~account expected =
    ( name,
      `Quick,
      fun () ->
        Alcotest.(check (option string))
          "account_to_store" expected
          (Drive.account_to_store ~stored ~account) )
  in
  [
    case "the same account, case and spaces aside: nothing to write"
      ~stored:(Some " A@x.fr") ~account:"a@X.FR " None;
    case "another account: written, trimmed" ~stored:(Some "a@x.fr")
      ~account:" b@x.fr " (Some "b@x.fr");
    case "nothing stored: written" ~stored:None ~account:"a@x.fr"
      (Some "a@x.fr");
  ]

(* An install that used Drive before it had its own account: its root id is
   the signed-in account's, which seed_account stores once so it is kept. *)
let seed_account_tests =
  let case name ~stored ~root ~session_email expected =
    ( name,
      `Quick,
      fun () ->
        Alcotest.(check (option string))
          "seed_account" expected
          (Drive.seed_account ~stored ~root ~session_email) )
  in
  [
    case "no account, a root id, signed in: the session's email (trimmed)"
      ~stored:None ~root:(Some "R1") ~session_email:(Some " me@x.fr ")
      (Some "me@x.fr");
    case "an account already stored: nothing" ~stored:(Some "drive@x.fr")
      ~root:(Some "R1") ~session_email:(Some "me@x.fr") None;
    case "no root id (a new install): nothing" ~stored:None ~root:None
      ~session_email:(Some "me@x.fr") None;
    case "no session email: nothing" ~stored:None ~root:(Some "R1")
      ~session_email:None None;
    case "a blank session email: nothing" ~stored:None ~root:(Some "R1")
      ~session_email:(Some "  ") None;
  ]

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

(* The id,trashed answers (get_trashed, the health check's shape). *)
let presence_test name expected =
  ( Printf.sprintf "%s: presence decodes it" name,
    `Quick,
    fun () ->
      with_fixture_id name (fun ~body ~id ->
          Alcotest.check Test_drive.presence_result "presence" (Ok expected)
            (Drive.run (seq_net [answer body]) (Drive.presence ~file_id:id))) )

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
    presence_test "files_get_folder_present_200" Drive.Present;
    presence_test "files_get_folder_moved_200" Drive.Present;
    presence_test "files_get_folder_trashed_200" Drive.Trashed;
    ( "files_get_folder_meta_usable_200: resolve_root keeps it, one request, \
       its recorded name learnt",
      `Quick,
      fun () ->
        with_fixture_id "files_get_folder_meta_usable_200" (fun ~body ~id ->
            let prog = Drive.resolve_root (root ~id ()) in
            check_requests "get_folder alone"
              [Drive.get_folder ~file_id:id]
              (Drive.requests (seq_net [answer body]) prog);
            Alcotest.check string_result_rooted "resolve_root"
              {
                result = Ok id;
                root = Keep;
                name = Some (fname "Herbier-fixtures-renamed");
              }
              (Drive.run (seq_net [answer body]) prog)) );
    ( "files_get_folder_meta_trashed_200: resolve_root forgets it, finds or \
       creates a new one",
      `Quick,
      fun () ->
        with_fixture_id "files_get_folder_meta_trashed_200" (fun ~body ~id ->
            let prog = Drive.resolve_root (root ~id ()) in
            let responses =
              [answer body; answer {|{"files":[]}|}; answer {|{"id":"N1"}|}]
            in
            check_requests "get_folder, find, create"
              [
                Drive.get_folder ~file_id:id;
                Drive.find_folder ~name:"Herbier" ~parent:Drive.Root;
                Drive.create_folder ~name:"Herbier" ~parent:Drive.Root;
              ]
              (Drive.requests (seq_net responses) prog);
            Alcotest.check string_result_rooted "resolve_root"
              {
                result = Ok "N1";
                root = Store "N1";
                name = Some (fname "Herbier");
              }
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
    ( "files_update_name_200: rename_root is Ok with the recorded name, Keep",
      `Quick,
      fun () ->
        with_fixture_id "files_update_name_200" (fun ~body ~id ->
            let prog =
              Drive.rename_root (root ~id ())
                ~name:(fname "Herbier-fixtures-renamed")
            in
            Alcotest.check name_result_rooted "rename_root"
              {
                result = Ok (fname "Herbier-fixtures-renamed");
                root = Keep;
                name = Some (fname "Herbier-fixtures-renamed");
              }
              (Drive.run (seq_net [answer body]) prog)) );
    ( "files_update_name_trashed_200: rename_root finds or creates the name at \
       the root",
      `Quick,
      fun () ->
        with_fixture_id "files_update_name_trashed_200" (fun ~body ~id ->
            let name = fname "Herbier-fixtures-renamed" in
            let prog = Drive.rename_root (root ~id ()) ~name in
            let responses =
              [answer body; answer {|{"files":[]}|}; answer {|{"id":"N1"}|}]
            in
            check_requests "update_name, find, create"
              [
                Drive.update_name ~file_id:id ~name;
                Drive.find_folder ~name:"Herbier-fixtures-renamed"
                  ~parent:Drive.Root;
                Drive.create_folder ~name:"Herbier-fixtures-renamed"
                  ~parent:Drive.Root;
              ]
              (Drive.requests (seq_net responses) prog);
            Alcotest.check name_result_rooted "rename_root"
              {result = Ok name; root = Store "N1"; name = Some name}
              (Drive.run (seq_net responses) prog)) );
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
