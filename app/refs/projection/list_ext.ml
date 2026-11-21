let dedup items =
  List.rev
    (List.fold_left
       (fun acc x ->
         match List.exists (String.equal x) acc with
         | true -> acc
         | false -> x :: acc)
       [] items)
