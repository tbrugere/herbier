(* Herbier_bindings.Cap_filesystem's readdir and rmdir, and
   Herbier_store_io.Files.usage / delete_dir over them, under node, over the
   stub plugin of filesystem_stub.js (preloaded by test/bindings/jsoo/dune).
   readdir's fixture cases decode the same fixture content the stub read from
   disk (exposed as __fixture_readdir_{previews,refthumbs}_json) with Yojson,
   so the expected entries come from the fixture, not a hand copy of it.
   Silent on success; the first mismatch goes to stderr and exits 1
   (smoke.ml's own pattern). *)

module Cap_filesystem = Herbier_bindings.Cap_filesystem
module Cap_error = Herbier_bindings.Cap_error
module Files = Herbier_store_io.Files

let process = Jv.get Jv.global "process"
let set_exit_code n = Jv.set process "exitCode" (Jv.of_int n)

let fail fmt =
  Printf.ksprintf
    (fun m ->
      prerr_endline m;
      Jv.call process "exit" [|Jv.of_int 1|] |> ignore)
    fmt

(* ---------- reading the fixtures (exposed by the stub) ---------- *)

let fixture_json global_name =
  Yojson.Safe.from_string (Jv.to_string (Jv.get Jv.global global_name))

let entry_of_json = function
  | `Assoc fields ->
      let name =
        match List.assoc_opt "name" fields with
        | Some (`String s) -> s
        | _ ->
            fail "fixture entry: missing name";
            ""
      in
      let kind : Cap_filesystem.kind =
        match List.assoc_opt "type" fields with
        | Some (`String "file") -> File
        | Some (`String "directory") -> Directory
        | _ ->
            fail "fixture entry %s: type is not \"file\" or \"directory\"" name;
            File
      in
      let size =
        match List.assoc_opt "size" fields with
        | Some (`Int n) -> n
        | Some (`Float f) -> int_of_float f
        | _ ->
            fail "fixture entry %s: missing size" name;
            0
      in
      ({name; kind; size} : Cap_filesystem.entry)
  | j ->
      fail "fixture entry: not an object (%s)" (Yojson.Safe.to_string j);
      {name = ""; kind = File; size = 0}

let entries_of_fixture global_name =
  match fixture_json global_name with
  | `Assoc fields -> (
      match List.assoc_opt "files" fields with
      | Some (`List l) -> List.map entry_of_json l
      | _ ->
          fail "%s: fixture has no \"files\" array" global_name;
          [])
  | j ->
      fail "%s: fixture is not an object (%s)" global_name
        (Yojson.Safe.to_string j);
      []

(* ---------- the stub's control surface ---------- *)

let clear_last_call () =
  Jv.set Jv.global "__last_call_json" (Jv.of_string "null")

let last_call_json () = Jv.to_string (Jv.get Jv.global "__last_call_json")

let last_call () =
  match Yojson.Safe.from_string (last_call_json ()) with
  | `List [`String name; `Assoc fields] -> (name, fields)
  | j ->
      fail "unexpected __last_call_json: %s" (Yojson.Safe.to_string j);
      ("", [])

let clear_readdir_override () =
  Jv.set Jv.global "__next_readdir_json" Jv.null;
  Jv.set Jv.global "__next_readdir_error" Jv.null;
  Jv.set Jv.global "__readdir_tree_json" Jv.null;
  Jv.set Jv.global "__next_rmdir_error" Jv.null

let set_readdir_json s = Jv.set Jv.global "__next_readdir_json" (Jv.of_string s)

let set_readdir_error s =
  Jv.set Jv.global "__next_readdir_error" (Jv.of_string s)

let set_readdir_tree s = Jv.set Jv.global "__readdir_tree_json" (Jv.of_string s)
let set_rmdir_error s = Jv.set Jv.global "__next_rmdir_error" (Jv.of_string s)
let other_rejection = {|{"code": "OS-PLUG-FILE-0005", "message": "denied"}|}

let str_field fields k =
  match List.assoc_opt k fields with
  | Some (`String s) -> s
  | _ -> Printf.sprintf "<%s missing or not a string>" k

let bool_field fields k =
  match List.assoc_opt k fields with Some (`Bool b) -> Some b | _ -> None

let check_eq what expected actual =
  match String.equal expected actual with
  | true -> ()
  | false -> fail "%s: expected %S, got %S" what expected actual

(* ---------- rendering (diagnostics and equality both) ---------- *)

let kind_str : Cap_filesystem.kind -> string = function
  | File -> "File"
  | Directory -> "Directory"

let entry_str (e : Cap_filesystem.entry) =
  Printf.sprintf "{name = %S; kind = %s; size = %d}" e.name (kind_str e.kind)
    e.size

let entries_str l = "[" ^ String.concat "; " (List.map entry_str l) ^ "]"

let entries_result_str = function
  | Ok l -> "Ok " ^ entries_str l
  | Error e -> "Error (" ^ Cap_error.to_string e ^ ")"

let check_entries what expected actual =
  match
    String.equal (entries_result_str expected) (entries_result_str actual)
  with
  | true -> ()
  | false ->
      fail "%s: expected %s, got %s" what
        (entries_result_str expected)
        (entries_result_str actual)

(* ---------- readdir: the fixtures ---------- *)

let readdir_previews_matches_fixture () =
  clear_readdir_override ();
  clear_last_call ();
  let expected = entries_of_fixture "__fixture_readdir_previews_json" in
  let open Fut.Syntax in
  let+ r = Cap_filesystem.readdir ~path:"previews" in
  check_entries "readdir previews" (Ok expected) r;
  let name, fields = last_call () in
  check_eq "call name" "readdir" name;
  check_eq "path" "previews" (str_field fields "path");
  check_eq "directory" "DATA" (str_field fields "directory")

let readdir_refthumbs_entries_are_directories () =
  clear_readdir_override ();
  let expected = entries_of_fixture "__fixture_readdir_refthumbs_json" in
  (match expected with
  | [] -> fail "__fixture_readdir_refthumbs_json: fixture has no entries"
  | _ -> ());
  List.iter
    (fun (e : Cap_filesystem.entry) ->
      match e.kind with
      | Directory -> ()
      | File -> fail "refthumbs fixture entry %s: expected Directory" e.name)
    expected;
  let open Fut.Syntax in
  let+ r = Cap_filesystem.readdir ~path:"refthumbs" in
  check_entries "readdir refthumbs (one sub-directory per plant)" (Ok expected)
    r

let readdir_missing_directory_is_missing () =
  clear_readdir_override ();
  let open Fut.Syntax in
  let+ r = Cap_filesystem.readdir ~path:"nope" in
  match r with
  | Ok l -> fail "readdir nope: expected Error, got Ok %s" (entries_str l)
  | Error e -> (
      match Cap_filesystem.is_missing e with
      | true -> ()
      | false ->
          fail "readdir nope: is_missing should be true, got %s"
            (Cap_error.to_string e))

let readdir_other_rejection_is_not_missing () =
  clear_readdir_override ();
  set_readdir_error other_rejection;
  let open Fut.Syntax in
  let+ r = Cap_filesystem.readdir ~path:"previews" in
  match r with
  | Error (Cap_error.Rejected _ as e) -> (
      match Cap_filesystem.is_missing e with
      | false -> ()
      | true -> fail "readdir OS-PLUG-FILE-0005: is_missing should be false")
  | other ->
      fail "readdir OS-PLUG-FILE-0005: expected Error (Rejected _), got %s"
        (entries_result_str other)

let readdir_invalid_path_rejected_without_calling_the_plugin () =
  clear_readdir_override ();
  clear_last_call ();
  let open Fut.Syntax in
  let+ r = Cap_filesystem.readdir ~path:"../x" in
  (match r with
  | Error (Cap_error.Invalid_path _) -> ()
  | other ->
      fail "readdir ../x: expected Error (Invalid_path _), got %s"
        (entries_result_str other));
  check_eq "the plugin was not called" "null" (last_call_json ())

(* ---------- readdir: decode errors ---------- *)

let readdir_decode_errors () =
  let case json ~expected_path =
    clear_readdir_override ();
    set_readdir_json json;
    let open Fut.Syntax in
    let+ r = Cap_filesystem.readdir ~path:"previews" in
    match r with
    | Error (Cap_error.Unexpected p) -> check_eq json expected_path p
    | other ->
        fail "%s: expected Error (Unexpected %S), got %s" json expected_path
          (entries_result_str other)
  in
  let ok_item = {|{"name": "a", "type": "file", "size": 1}|} in
  let open Fut.Syntax in
  let* () = case {|{"files": "nope"}|} ~expected_path:"files" in
  let* () =
    case
      (Printf.sprintf {|{"files": [%s, {"type": "file", "size": 1}]}|} ok_item)
      ~expected_path:"files[1].name"
  in
  let* () =
    case {|{"files": [{"name": "a", "type": "link", "size": 1}]}|}
      ~expected_path:"files[0].type"
  in
  let* () =
    case
      (Printf.sprintf {|{"files": [%s, {"name": "b", "type": "file"}]}|} ok_item)
      ~expected_path:"files[1].size"
  in
  let* () =
    case {|{"files": [{"name": "a", "type": "file", "size": 1.5}]}|}
      ~expected_path:"files[0].size"
  in
  let* () =
    case {|{"files": [{"name": "a", "type": "file", "size": "1"}]}|}
      ~expected_path:"files[0].size"
  in
  case
    {|{"files": [{"name": "a", "type": "file"}, {"name": "b", "type": "x", "size": 1}]}|}
    ~expected_path:"files[0].size"

(* ---------- rmdir ---------- *)

let rmdir_sends_recursive () =
  clear_readdir_override ();
  clear_last_call ();
  let open Fut.Syntax in
  let+ r = Cap_filesystem.rmdir ~path:"refthumbs" ~recursive:true in
  (match r with
  | Ok () -> ()
  | Error e -> fail "rmdir: expected Ok, got Error %s" (Cap_error.to_string e));
  let name, fields = last_call () in
  check_eq "call name" "rmdir" name;
  check_eq "path" "refthumbs" (str_field fields "path");
  check_eq "directory" "DATA" (str_field fields "directory");
  match bool_field fields "recursive" with
  | Some true -> ()
  | Some false -> fail "rmdir: recursive sent as false"
  | None -> fail "rmdir: recursive not sent"

let rmdir_missing_is_missing () =
  clear_readdir_override ();
  let open Fut.Syntax in
  let+ r = Cap_filesystem.rmdir ~path:"nope" ~recursive:true in
  match r with
  | Error e when Cap_filesystem.is_missing e -> ()
  | Error e ->
      fail "rmdir nope: expected a missing rejection, got %s"
        (Cap_error.to_string e)
  | Ok () -> fail "rmdir nope: expected Error, got Ok"

(* ---------- Files.usage and delete_dir ---------- *)

let usage_result_str = function
  | Ok n -> Printf.sprintf "Ok %.0f" n
  | Error e -> "Error (" ^ Cap_error.to_string e ^ ")"

let file name size =
  Printf.sprintf {|{"name": %S, "type": "file", "size": %d}|} name size

let dir name =
  Printf.sprintf {|{"name": %S, "type": "directory", "size": 4096}|} name

let listing items =
  Printf.sprintf {|{"files": [%s]}|} (String.concat ", " items)

let usage_sums_files_recursively () =
  clear_readdir_override ();
  set_readdir_tree
    (Printf.sprintf {|{"top": %s, "top/sub": %s, "top/sub/deeper": %s}|}
       (listing [file "a" 10; dir "sub"; file "b" 5])
       (listing [file "c" 7; dir "deeper"; dir "gone"])
       (listing [file "d" 1]));
  let open Fut.Syntax in
  let+ r = Files.usage ~dir:"top" in
  check_eq "usage top (files only, a missing sub-directory counts 0)" "Ok 23"
    (usage_result_str r)

let usage_missing_dir_is_zero () =
  clear_readdir_override ();
  let open Fut.Syntax in
  let+ r = Files.usage ~dir:"nope" in
  check_eq "usage nope" "Ok 0" (usage_result_str r)

let usage_other_rejection_is_error () =
  clear_readdir_override ();
  set_readdir_tree
    (Printf.sprintf {|{"top": %s, "top/sub": {"reject": %s}}|}
       (listing [file "a" 10; dir "sub"])
       other_rejection);
  let open Fut.Syntax in
  let+ r = Files.usage ~dir:"top" in
  match r with
  | Error (Cap_error.Rejected {code = Some "OS-PLUG-FILE-0005"; _}) -> ()
  | other ->
      fail
        "usage top with a denied sub-directory: expected the rejection, got %s"
        (usage_result_str other)

let delete_dir_missing_is_ok () =
  clear_readdir_override ();
  let open Fut.Syntax in
  let+ r = Files.delete_dir ~dir:"nope" in
  match r with
  | Ok () -> ()
  | Error e ->
      fail "delete_dir nope: expected Ok, got %s" (Cap_error.to_string e)

let delete_dir_other_rejection_is_error () =
  clear_readdir_override ();
  set_rmdir_error other_rejection;
  let open Fut.Syntax in
  let+ r = Files.delete_dir ~dir:"refthumbs" in
  match r with
  | Error (Cap_error.Rejected {code = Some "OS-PLUG-FILE-0005"; _}) -> ()
  | Ok () -> fail "delete_dir with a denied rmdir: expected Error, got Ok"
  | Error e ->
      fail "delete_dir with a denied rmdir: expected the rejection, got %s"
        (Cap_error.to_string e)

let () =
  set_exit_code 1;
  let open Fut.Syntax in
  let all =
    let* () = readdir_previews_matches_fixture () in
    let* () = readdir_refthumbs_entries_are_directories () in
    let* () = readdir_missing_directory_is_missing () in
    let* () = readdir_other_rejection_is_not_missing () in
    let* () = readdir_invalid_path_rejected_without_calling_the_plugin () in
    let* () = readdir_decode_errors () in
    let* () = rmdir_sends_recursive () in
    let* () = rmdir_missing_is_missing () in
    let* () = usage_sums_files_recursively () in
    let* () = usage_missing_dir_is_zero () in
    let* () = usage_other_rejection_is_error () in
    let* () = delete_dir_missing_is_ok () in
    delete_dir_other_rejection_is_error ()
  in
  Fut.await all (fun () -> set_exit_code 0)
