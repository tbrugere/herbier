let offset_at_s t =
  let date = Jv.new' (Jv.get Jv.global "Date") [|Jv.of_float (t *. 1000.)|] in
  -60 * Jv.to_int (Jv.call date "getTimezoneOffset" [||])

let local_offset_s ~year ~month ~day ~hour ~minute ~second =
  let date =
    Jv.new' (Jv.get Jv.global "Date")
      (Array.map Jv.of_int [|year; month - 1; day; hour; minute; second|])
  in
  -60 * Jv.to_int (Jv.call date "getTimezoneOffset" [||])
