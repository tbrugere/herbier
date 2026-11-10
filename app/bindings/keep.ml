let prop = "__herbierKeep"

let on el v =
  let el = Brr.El.to_jv el in
  let kept =
    match Jv.is_none (Jv.get el prop) with
    | true ->
        let a = Jv.Jarray.create 0 in
        Jv.set el prop a;
        a
    | false -> Jv.get el prop
  in
  ignore (Jv.call kept "push" [|Jv.repr v|])
