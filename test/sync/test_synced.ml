(* Synced's table list and its pull order against the schema catalog. *)

module Synced = Herbier_sync_core.Synced
module Catalog = Support.Catalog

(* ---------- Synced.all, name, of_name ---------- *)

let names = List.map (fun (Synced.Any t) -> Synced.name t) Synced.all

let synced_all_has_seven_distinct_tables () =
  Alcotest.(check int) "Synced.all has 7 elements" 7 (List.length names);
  Alcotest.(check int)
    "no duplicate name" 7
    (List.length (List.sort_uniq String.compare names))

let of_name_inverts_name () =
  List.iter
    (fun (Synced.Any t) ->
      match Synced.of_name (Synced.name t) with
      | Some (Synced.Any t') ->
          Alcotest.(check string)
            (Synced.name t ^ ": of_name (name t) names the same table")
            (Synced.name t) (Synced.name t')
      | None -> Alcotest.failf "of_name %S gave None" (Synced.name t))
    Synced.all;
  Alcotest.(check bool)
    "of_name \"outbox\" is None" true
    (Option.is_none (Synced.of_name "outbox"));
  Alcotest.(check bool)
    "of_name \"Plants\" is None (exact strings only)" true
    (Option.is_none (Synced.of_name "Plants"))

(* ---------- pull order against the catalog ---------- *)

let index_of name =
  let rec go i = function
    | [] -> None
    | x :: rest -> (
        match String.equal x name with
        | true -> Some i
        | false -> go (i + 1) rest)
  in
  go 0 names

(* Collects the foreign keys it checks and compares them with the expected
   list, so that a catalog whose fk_table stopped matching table names fails
   instead of checking nothing. *)
let pull_order_respects_foreign_keys () =
  let tables = Catalog.read () in
  let checked, cover_photo_seen =
    List.fold_left
      (fun acc (t : Catalog.table) ->
        match index_of t.name with
        | None -> acc (* not a synced table: a lookup table *)
        | Some table_index ->
            List.fold_left
              (fun (checked, cover) (c : Catalog.column) ->
                match c.foreign_key with
                | None -> (checked, cover)
                | Some _
                  when String.equal t.name "plants"
                       && String.equal c.name "cover_photo_id" ->
                    (* the documented exception: no local foreign key *)
                    (checked, true)
                | Some fk_table -> (
                    match index_of fk_table with
                    | None -> (checked, cover) (* a lookup table *)
                    | Some fk_index ->
                        Alcotest.(check bool)
                          (Printf.sprintf
                             "%s.%s -> %s comes earlier in Synced.all" t.name
                             c.name fk_table)
                          true (fk_index < table_index);
                        ((t.name, c.name, fk_table) :: checked, cover)))
              acc t.columns)
      ([], false) tables
  in
  Alcotest.(check (list (triple string string string)))
    "the synced foreign keys checked"
    (List.sort compare
       [
         ("observations", "plant_id", "plants");
         ("photos", "observation_id", "observations");
         ("plant_refs", "plant_id", "plants");
         ("plant_tags", "plant_id", "plants");
         ("plant_tags", "tag_id", "tags");
         ("reference", "plant_id", "plants");
       ])
    (List.sort compare checked);
  Alcotest.(check bool)
    "plants.cover_photo_id is in the catalog as a foreign key" true
    cover_photo_seen

let tests =
  [
    ( "Synced.all: 7 distinct tables",
      `Quick,
      synced_all_has_seven_distinct_tables );
    ( "Synced.of_name inverts Synced.name on exact strings only",
      `Quick,
      of_name_inverts_name );
    ( "pull order: every synced foreign key points earlier in Synced.all \
       (plants.cover_photo_id excepted)",
      `Quick,
      pull_order_respects_foreign_keys );
  ]
