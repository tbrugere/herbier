let byte s i = Char.code s.[i]
let exif_header = "Exif\000\000"

(* Segments before the scan data are [FF marker len_hi len_lo payload], the
   length counting its own two bytes; SOI (D8) has no length. *)
let has_exif s =
  let n = String.length s in
  let rec segment i =
    match i + 4 <= n && byte s i = 0xFF with
    | false -> false
    | true -> (
        match byte s (i + 1) with
        | 0xDA | 0xD9 -> false
        | marker ->
            let len = (byte s (i + 2) lsl 8) lor byte s (i + 3) in
            let payload = i + 4 in
            marker = 0xE1
            && payload + String.length exif_header <= n
            && String.equal
                 (String.sub s payload (String.length exif_header))
                 exif_header
            || (len >= 2 && segment (i + 2 + len)))
  in
  n >= 2 && byte s 0 = 0xFF && byte s 1 = 0xD8 && segment 2
