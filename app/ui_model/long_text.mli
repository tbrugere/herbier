(** Which texts of 4f are shown collapsed: a long text shows about three lines
    and expands when tapped; a short one shows in full. Pure. *)

val threshold : int
(** 140 code points: about four lines of 4f's value column (about 200 px wide,
    about 32 characters a line on a 360 dp phone), so a text that would hide
    almost nothing is shown in full. An estimate made for a phone held upright:
    on a wider screen (landscape, tablet) a text just over it may fit in three
    lines and still get the fade, which a tap removes. *)

val collapsible : string -> bool
(** The trimmed text has more than {!threshold} code points
    ({!Herbier_refs.Wiki_text.code_points}) or contains a ['\n']. *)
