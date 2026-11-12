open Brr

let cls c = At.class' (Jstr.v c)

let cell months m =
  El.span
    ~at:[At.if' (List.mem m months) (cls "is-active"); cls "month-grid__cell"]
    [El.txt' (Ref_text.month_letter m)]

let v months =
  El.div
    ~at:[cls "month-grid"; At.v (Jstr.v "aria-hidden") (Jstr.v "true")]
    (List.map (cell months) (List.init 12 (fun i -> i + 1)))
