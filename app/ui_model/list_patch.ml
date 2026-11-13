type 'a edit = Remove of int | Insert of int * 'a | Update of int * 'a

let diff ~same ~equal old next =
  let present l x = List.exists (same x) l in
  (* Consing gives the removals from the last index down. *)
  let _, removals =
    List.fold_left
      (fun (i, acc) x ->
        match present next x with
        | true -> (i + 1, acc)
        | false -> (i + 1, Remove i :: acc))
      (0, []) old
  in
  let kept = List.filter (present next) old in
  (* Walk [next] against the kept items; [None] when an item is found out of
     order. *)
  let rec walk j kept next acc =
    match (kept, next) with
    | [], [] -> Some (List.rev acc)
    | k :: kept', n :: next' when same k n -> (
        match equal k n with
        | true -> walk (j + 1) kept' next' acc
        | false -> walk (j + 1) kept' next' (Update (j, n) :: acc))
    | _, n :: next' when not (present kept n) ->
        walk (j + 1) kept next' (Insert (j, n) :: acc)
    | _, _ -> None
  in
  match walk 0 kept next [] with
  | Some rest -> removals @ rest
  | None ->
      List.init (List.length old) (fun i -> Remove (List.length old - 1 - i))
      @ List.mapi (fun i x -> Insert (i, x)) next
