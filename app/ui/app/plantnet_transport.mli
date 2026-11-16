(** The app's one Pl@ntNet transport (architecture §12, layout §2): Brr's
    futures over the timed fetch, the previews given as blobs. Holds no key,
    reads no file, logs nothing, and never puts a JS error's text or the URL in
    a failure. *)

type image = Brr.Blob.t
(** A preview's bytes (JPEG); {!Identification} reads a stored one before. *)

val timeout_ms : int
(** 30 000: an identify POST's timeout (five previews on mobile data). *)

(** [post_form] is one {!Herbier_bindings.Timed_fetch.request_form}, aborted
    after {!timeout_ms}. [get] is {!Herbier_bindings.Timed_fetch.request}'s GET
    (its default 15 s). Both: an answer, any status → [Ok]; the abort timer →
    [Error Timeout]; a rejected fetch → [Error (Network "fetch failed")], a
    constant (the JS text is never forwarded). No retry; never raises; the
    future always resolves. *)
include
  Herbier_identify.TRANSPORT with type 'a io = 'a Fut.t and type image := image
