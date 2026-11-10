let get el name =
  let style = Jv.call Jv.global "getComputedStyle" [|Brr.El.to_jv el|] in
  Jv.to_string (Jv.call style "getPropertyValue" [|Jv.of_string name|])
  |> String.trim

let is_custom = String.starts_with ~prefix:"--"

let rule_names rule =
  match Jv.find rule "selectorText" with
  | Some sel when Jv.to_string sel = ":root" ->
      Jv.to_list Jv.to_string (Jv.get rule "style") |> List.filter is_custom
  | _ -> []

(* A cross-origin sheet throws on [cssRules]; it declares no token of ours. *)
let sheet_names sheet =
  match Jv.to_list Fun.id (Jv.get sheet "cssRules") with
  | rules -> List.concat_map rule_names rules
  | exception Jv.Error _ -> []

let root_names () =
  Jv.get (Brr.Document.to_jv Brr.G.document) "styleSheets"
  |> Jv.to_list Fun.id
  |> List.concat_map sheet_names
