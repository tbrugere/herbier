let hook () =
  match Jv.is_none (Jv.get Jv.global "herbierDev") with
  | true ->
      let o = Jv.obj [||] in
      Jv.set Jv.global "herbierDev" o;
      o
  | false -> Jv.get Jv.global "herbierDev"

let export_int name f =
  Jv.set (hook ()) name (Jv.callback ~arity:1 (fun _ -> Jv.of_int (f ())))

let export_strings name f =
  Jv.set (hook ()) name
    (Jv.callback ~arity:1 (fun _ -> Jv.of_list Jv.of_string (f ())))

let heap_used () =
  Jv.find_path Jv.global ["performance"; "memory"; "usedJSHeapSize"]
  |> Option.map Jv.to_float

let collect_garbage () =
  match Jv.find Jv.global "gc" with
  | Some gc when Jv.instanceof gc ~cons:(Jv.get Jv.global "Function") ->
      ignore (Jv.apply gc [||]);
      true
  | Some _ | None -> false
