let local_offset_s ~year ~month ~day ~hour ~minute ~second =
  let date =
    Jv.new' (Jv.get Jv.global "Date")
      (Array.map Jv.of_int [|year; month - 1; day; hour; minute; second|])
  in
  -60 * Jv.to_int (Jv.call date "getTimezoneOffset" [||])
