let to_blob canvas ~type' ~quality =
  let fut, set = Fut.create () in
  let callback =
    Jv.callback ~arity:1 (fun blob ->
        set
          (match Jv.to_option Brr.Blob.of_jv blob with
          | Some b -> Ok b
          | None -> Error (Cap_error.Unexpected "blob")))
  in
  match
    Jv.call
      (Brr_canvas.Canvas.to_jv canvas)
      "toBlob"
      [|callback; Jv.of_string type'; Jv.of_float quality|]
  with
  | (_ : Jv.t) -> fut
  | exception Jv.Error e ->
      Fut.return (Error (Cap_call.rejected (Jv.of_error e)))
  (* jsoo raises [Failure] for a thrown value that is not an Error. *)
  | exception Failure message ->
      Fut.return (Error (Cap_error.Rejected {code = None; message}))
