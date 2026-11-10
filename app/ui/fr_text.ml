let plural n one many =
  Printf.sprintf "%d %s" n (match n <= 1 with true -> one | false -> many)
