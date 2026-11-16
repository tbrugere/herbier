let plural n one many =
  Printf.sprintf "%d %s" n (match n <= 1 with true -> one | false -> many)

let size n =
  let ko = Float.round (n /. 1000.) in
  match () with
  | () when n <= 0. -> "0 o"
  | () when n < 1000. -> Printf.sprintf "%.0f o" (Float.trunc n)
  | () when ko < 1000. -> Printf.sprintf "%.0f ko" ko
  | () ->
      let tenths = Float.round (n /. 100_000.) in
      Printf.sprintf "%.0f,%.0f Mo"
        (Float.trunc (tenths /. 10.))
        (Float.rem tenths 10.)
