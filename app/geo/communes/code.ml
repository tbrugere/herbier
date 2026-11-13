type t = string

let is_digit = function '0' .. '9' -> true | _ -> false

(* Mainland codes skip 20 (split into 2A and 2B in 1976); overseas ones
   are 971 to 976. *)
let valid code =
  match code with
  | "2A" | "2B" -> true
  | _ when String.length code = 2 && String.for_all is_digit code ->
      let n = int_of_string code in
      1 <= n && n <= 95 && n <> 20
  | _ when String.length code = 3 -> (
      match (String.sub code 0 2, code.[2]) with
      | "97", '1' .. '6' -> true
      | _ -> false)
  | _ -> false

let of_string code = match valid code with true -> Some code | false -> None
let to_string code = code
let equal = String.equal
let compare = String.compare
