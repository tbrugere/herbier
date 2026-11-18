open Brr

let append log text = El.append_children log [El.div [El.txt' text]]
let button label = El.button ~at:[At.type' (Jstr.v "button")] [El.txt' label]

let on_click el f =
  ignore (Ev.listen Ev.click (fun _ -> f ()) (El.as_target el) : Ev.listener)

let heading log text = El.append_children log [El.h2 [El.txt' text]]

let set_disabled el disabled =
  El.set_at At.Name.disabled
    (match disabled with true -> Some Jstr.empty | false -> None)
    el

let step log label ~detail ~error fut =
  Fut.map
    (fun r ->
      (match r with
      | Ok v -> (
          match detail v with
          | None -> append log (label ^ ": ok")
          | Some d -> append log (label ^ ": ok · " ^ d))
      | Error e -> append log (label ^ ": " ^ error e));
      r)
    fut

let action label f =
  let b = El.button [El.txt' label] in
  on_click b f;
  b

let test_jpeg ?(color = "#2e7d32") () =
  let module C2d = Brr_canvas.C2d in
  let module Canvas_jpeg = Herbier_bindings.Canvas_jpeg in
  let canvas = Brr_canvas.Canvas.create ~w:64 ~h:64 [] in
  let ctx = C2d.get_context canvas in
  C2d.set_fill_style ctx (C2d.color (Jstr.v color));
  C2d.fill_rect ctx ~x:0. ~y:0. ~w:64. ~h:64.;
  C2d.set_fill_style ctx (C2d.color (Jstr.v "#c62828"));
  C2d.fill_rect ctx ~x:0. ~y:24. ~w:64. ~h:16.;
  Fut.map
    (Result.map_error (function
      | Canvas_jpeg.Encode e ->
          "encode: " ^ Herbier_bindings.Cap_error.to_string e
      | Canvas_jpeg.Not_jpeg t -> "not a JPEG: " ^ t))
    (Canvas_jpeg.encode ~quality:0.9 canvas)

let contains ~sub s =
  Option.is_some (Jstr.find_sub ~sub:(Jstr.v sub) (Jstr.v s))
