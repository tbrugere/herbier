type t = string

let is_digit = function '0' .. '9' -> true | _ -> false

let of_string s =
  let n = String.length s in
  match n >= 2 && n <= 13 && s.[0] = 'Q' && s.[1] <> '0' with
  | false -> None
  | true -> (
      match String.for_all is_digit (String.sub s 1 (n - 1)) with
      | true -> Some s
      | false -> None)

let to_string t = t
let equal = String.equal
let pp ppf t = Format.pp_print_string ppf t
