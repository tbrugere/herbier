let current_index () =
  match Jv.find_path Jv.global ["navigation"; "currentEntry"; "index"] with
  | Some v when Jstr.equal (Jv.typeof v) (Jstr.v "number") -> (
      let f = Jv.to_float v in
      match Float.is_integer f && f >= 0. with
      | true -> Some (Float.to_int f)
      | false -> None)
  | Some _ | None -> None
  | exception Jv.Error _ -> None
