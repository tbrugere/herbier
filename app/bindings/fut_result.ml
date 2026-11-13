let map_error f fut = Fut.map (Result.map_error f) fut

let traverse f items =
  List.fold_left
    (fun acc x ->
      Fut.bind acc (function
        | Error e -> Fut.return (Error e)
        | Ok done_ -> Fut.map (Result.map (fun r -> r :: done_)) (f x)))
    (Fut.ok []) items
  |> Fut.map (Result.map List.rev)
