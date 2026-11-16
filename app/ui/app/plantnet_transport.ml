module Transport = Herbier_identify.Transport
module Timed_fetch = Herbier_bindings.Timed_fetch

type image = Brr.Blob.t
type 'a io = 'a Fut.t

let timeout_ms = 30_000
let return = Fut.return
let bind = Fut.bind

(* Constant texts: a JS error's message may name the URL, whose query string
   holds the key (Make drops the text anyway). *)
let failure : Timed_fetch.error -> Transport.failure = function
  | Timeout -> Timeout
  | Failed (_ : string) -> Network "fetch failed"

let answer = function
  | Ok ({status; body; _} : Timed_fetch.response) -> Ok {Transport.status; body}
  | Error e -> Error (failure e)

let part ({field; filename; image} : image Transport.file) =
  {Timed_fetch.field; filename; blob = image}

let post_form ~url ~fields ~files =
  Fut.map answer
    (Timed_fetch.request_form ~timeout_ms ~url ~fields (List.map part files))

let get ~url =
  Fut.map answer (Timed_fetch.request ~meth:`GET ~url ~headers:[] ~body:None)
