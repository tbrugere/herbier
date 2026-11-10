(** Dev-only page for the design tokens: a swatch for every colour custom
    property of [_tokens.sass], a sample of every type role of the handoff, the
    bundled icons, and what {!Theme.load} returns. Reached with the URL fragment
    [#dev/theme]. *)

val el : unit -> Brr.El.t
