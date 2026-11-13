type t = Rejected of int | Invalid of string | Other of string
[@@deriving eq, show]

let invalid_prefix = "invalid entry: "

let to_string = function
  | Rejected status -> Printf.sprintf "HTTP %d" status
  | Invalid why -> invalid_prefix ^ why
  | Other text -> text

let of_string text =
  match String.starts_with ~prefix:invalid_prefix text with
  | true ->
      let n = String.length invalid_prefix in
      Invalid (String.sub text n (String.length text - n))
  | false -> (
      match Scanf.sscanf_opt text "HTTP %d%!" Fun.id with
      | Some status -> Rejected status
      | None -> Other text)
