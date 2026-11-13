type decision = Insert | Replace | Unchanged | Keep_local
[@@deriving eq, show {with_path = false}]

let decide ~equal ~pending ~local remote =
  match (local, pending) with
  | None, (true | false) -> Insert
  | Some _, true -> Keep_local
  | Some local, false -> (
      match equal local remote with true -> Unchanged | false -> Replace)
