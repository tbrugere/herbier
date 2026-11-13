(* Herbier's catalog (supabase/schema/catalog.json) against the domain. The
   values of each lookup table are the to_string of [all] for the module
   the table's `ocaml=` metadata names, so a value changed on only one side
   fails here: postgrest-codegen reads the metadata but not the values, and
   test_enums.ml pins to_string. The catalog gives the seven synced tables,
   and a column renamed in it changes what postgrest-codegen generates
   (app/store/dune diffs that with the committed tables.ml). *)

module Codegen = Postgrest_codegen
module Photo = Herbier_domain.Photo
module Reference = Herbier_domain.Reference
module Text = Herbier_test_support.Text

(* Every module a lookup table names. Reference.Organ has no lookup table:
   organs are device-only. *)
let domain_values =
  [
    ( "Photo.Original_target",
      List.map Photo.Original_target.to_string Photo.Original_target.all );
    ( "Photo.Upload_state",
      List.map Photo.Upload_state.to_string Photo.Upload_state.all );
    ( "Reference.Source",
      List.map Reference.Source.to_string Reference.Source.all );
    ( "Reference.Status",
      List.map Reference.Status.to_string Reference.Status.all );
  ]

let catalog_text () =
  In_channel.with_open_bin "../../supabase/schema/catalog.json"
    In_channel.input_all

let catalog () =
  match Codegen.Catalog.of_string (catalog_text ()) with
  | Ok catalog -> catalog
  | Error e -> Alcotest.fail (Codegen.Error.to_string e)

let model () =
  match
    Codegen.Model.of_catalog ~module_prefix:["Herbier_domain"] (catalog ())
  with
  | Ok model -> model
  | Error e -> Alcotest.fail (Codegen.Error.to_string e)

(* Lookup table -> the module its metadata names. *)
let lookup_modules () =
  List.filter_map
    (fun (c : Codegen.Model.codec) ->
      match (c.source, c.path) with
      | Lookup table, "Herbier_domain" :: path ->
          Some (table, String.concat "." path)
      | Lookup _, _ | Id, _ -> None)
    (model ()).codecs

let sorted = List.sort String.compare

let tests =
  let open Alcotest in
  [
    test_case "every lookup table names a module listed here" `Quick (fun () ->
        let modules = lookup_modules () in
        check bool "some lookup tables" true (modules <> []);
        check (list string) "modules"
          (sorted (List.map fst domain_values))
          (sorted (List.map snd modules)));
    test_case "lookup values are the OCaml values" `Quick (fun () ->
        let catalog = catalog () in
        List.iter
          (fun (table, m) ->
            check
              (option (list string))
              table
              (Option.map sorted (List.assoc_opt m domain_values))
              (List.find_map
                 (fun (t : Codegen.Catalog.table) ->
                   match String.equal t.name table with
                   | true -> Option.map sorted t.values
                   | false -> None)
                 catalog))
          (lookup_modules ()));
    test_case "seven synced tables" `Quick (fun () ->
        check (list string) "tables"
          [
            "observations";
            "photos";
            "plant_refs";
            "plant_tags";
            "plants";
            "reference";
            "tags";
          ]
          (List.map (fun (t : Codegen.Model.table) -> t.name) (model ()).tables));
    test_case "a column renamed in the catalog changes the generated file"
      `Quick (fun () ->
        let catalog = catalog () in
        let rename (c : Codegen.Catalog.column) =
          match c.name with
          | "display_name" -> {c with name = "display_label"}
          | _ -> c
        in
        let rename_in (t : Codegen.Catalog.table) =
          match t.name with
          | "plants" -> {t with columns = List.map rename t.columns}
          | _ -> t
        in
        let generate catalog =
          match
            Codegen.Model.of_catalog ~module_prefix:["Herbier_domain"] catalog
          with
          | Ok model -> Codegen.Emit.to_string model
          | Error e -> Alcotest.fail (Codegen.Error.to_string e)
        in
        let original = generate catalog in
        let renamed = generate (List.map rename_in catalog) in
        check bool "display_name before" true
          (Text.contains ~sub:"let display_name :" original);
        check bool "display_name after" false
          (Text.contains ~sub:"let display_name :" renamed);
        check bool "display_label after" true
          (Text.contains ~sub:"let display_label :" renamed));
  ]
