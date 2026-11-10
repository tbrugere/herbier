let export_int name f =
  let hook =
    match Jv.is_none (Jv.get Jv.global "herbierDev") with
    | true ->
        let o = Jv.obj [||] in
        Jv.set Jv.global "herbierDev" o;
        o
    | false -> Jv.get Jv.global "herbierDev"
  in
  Jv.set hook name (Jv.callback ~arity:1 (fun _ -> Jv.of_int (f ())))
