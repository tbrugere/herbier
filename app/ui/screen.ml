type t = {el : Brr.El.t; bindings : Rb.binding list; ready : unit Fut.t}

let now = Fut.return ()

let once () =
  let fut, set = Fut.create () in
  (* style: a once-guard, [Fut.create]'s setter throws on a second call. *)
  let set_already = ref false in
  let once () =
    match !set_already with
    | true -> ()
    | false ->
        set_already := true;
        set ()
  in
  (fut, once)
