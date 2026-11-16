let matches q =
  match Jv.find Jv.global "matchMedia" with
  | None -> false
  | Some _ -> (
      match Jv.call Jv.global "matchMedia" [|Jv.of_string q|] with
      | list -> Jv.to_bool (Jv.get list "matches")
      | exception Jv.Error _ -> false)
