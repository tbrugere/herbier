let digits = "0123456789abcdef"

let hex bytes =
  String.init
    (2 * String.length bytes)
    (fun i ->
      let b = Char.code bytes.[i / 2] in
      digits.[match i mod 2 with 0 -> b lsr 4 | _ -> b land 15])
