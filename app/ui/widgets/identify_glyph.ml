open Brr

(* Brr's El.v makes HTML elements only: SVG ones need createElementNS. *)
let svg name attrs children =
  let el =
    El.of_jv
      (Jv.call
         (Document.to_jv G.document)
         "createElementNS"
         [|Jv.of_string "http://www.w3.org/2000/svg"; Jv.of_string name|])
  in
  List.iter (fun (k, v) -> El.set_at (Jstr.v k) (Some (Jstr.v v)) el) attrs;
  El.append_children el children;
  el

let frame =
  "M4 9V5a1 1 0 0 1 1-1h4M15 4h4a1 1 0 0 1 1 1v4M20 15v4a1 1 0 0 1-1 1h-4M9 \
   20H5a1 1 0 0 1-1-1v-4"

(* The leaf, then the outline of the handoff's vein (M9.7 14.3L13.6 10.4,
   stroke 1.4, round caps): even-odd filling cuts the vein out. *)
let leaf =
  "M8 16C8 11.6 11.6 8 16 8C16 12.4 12.4 16 8 16ZM10.195 14.795L14.095 \
   10.895A0.7 0.7 0 0 0 13.105 9.905L9.205 13.805A0.7 0.7 0 0 0 10.195 14.795Z"

let el ?(size = 24) () =
  let size = string_of_int size in
  svg "svg"
    [
      ("viewBox", "0 0 24 24");
      ("width", size);
      ("height", size);
      ("fill", "none");
      ("aria-hidden", "true");
      ("focusable", "false");
      ("class", "identify-glyph");
    ]
    [
      svg "path"
        [("d", frame); ("stroke", "currentColor"); ("stroke-width", "2")]
        [];
      svg "path"
        [("d", leaf); ("fill", "currentColor"); ("fill-rule", "evenodd")]
        [];
    ]
