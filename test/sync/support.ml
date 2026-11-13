(* Helpers of every suite in test/sync: a recorded fixture's text, substring
   search for the "never contains the token" checks, and the schema catalog
   read through postgrest-codegen's decoder. *)

let fixture name =
  In_channel.with_open_bin
    (Filename.concat "../fixtures" name)
    In_channel.input_all

let contains ~needle haystack =
  let n = String.length needle and h = String.length haystack in
  let rec at i =
    i <= h - n && (String.equal (String.sub haystack i n) needle || at (i + 1))
  in
  n = 0 || at 0

module Catalog = struct
  include Postgrest_codegen.Catalog

  let catalog_path = "../../supabase/schema/catalog.json"

  let read () : t =
    match
      of_string (In_channel.with_open_bin catalog_path In_channel.input_all)
    with
    | Ok tables -> tables
    | Error e ->
        Alcotest.failf "catalog.json: %s" (Postgrest_codegen.Error.to_string e)

  let server_only (c : column) =
    match Postgrest_codegen.Metadata.of_comment c.comment with
    | Some flags -> List.mem_assoc "server_only" flags
    | None -> false

  (* The names a pull or push carries for [t]: every column except the
     server-only ones (owner_id, observations.loc). *)
  let synced_columns (t : table) : string list =
    List.filter_map
      (fun (c : column) ->
        match server_only c with true -> None | false -> Some c.name)
      t.columns

  let find name tables =
    match
      List.find_opt (fun (t : table) -> String.equal t.name name) tables
    with
    | Some t -> t
    | None -> Alcotest.failf "no %s table in the catalog" name
end
