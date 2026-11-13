(* 10 × 2^5 = 320 > 300: from the sixth attempt on the cap applies, which
   keeps the shift small. *)
let delay ~attempt =
  match attempt with
  | n when n <= 1 -> Ptime.Span.of_int_s 10
  | n when n >= 6 -> Ptime.Span.of_int_s 300
  | n -> Ptime.Span.of_int_s (10 lsl (n - 1))
