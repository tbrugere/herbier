let non_blank s = match String.trim s with "" -> None | t -> Some t

let same_email a b =
  String.equal
    (String.lowercase_ascii (String.trim a))
    (String.lowercase_ascii (String.trim b))
