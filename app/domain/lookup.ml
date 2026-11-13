module type Values = sig
  type t

  val all : t list
  val to_string : t -> string
end

module Make (V : Values) = struct
  let of_string s =
    List.find_opt (fun v -> String.equal (V.to_string v) s) V.all

  let to_json t = `String (V.to_string t)
  let of_json = function `String s -> of_string s | _ -> None
end
