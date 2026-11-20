(** The few design tokens OCaml needs, read from the CSS custom properties of
    [web/sass/_tokens.sass] (the only place they are defined) with
    [getComputedStyle] on the root element ({!Herbier_bindings.Css_var}). Call
    {!load} once at startup, after [app.css] has loaded, and pass the result
    along.

    Values are the CSS text of the compiled [_tokens.sass], [var(...)]
    references resolved but not normalised by the browser (["#1d1a14"],
    ["rgba(79, 107, 58, 0.25)"]); MapLibre accepts them as they are. *)

type map = Herbier_geo.Style.colours = {
  point : string;  (** an observation: [--map-point] *)
  point_border : string;  (** the ring around every point *)
  selected : string;  (** the selected cluster *)
  selected_halo : string;  (** the halo around it *)
  to_identify : string;  (** an "À identifier" observation *)
  accuracy_fill : string;  (** the GPS accuracy circle *)
  accuracy_line : string;  (** its border *)
  origin : string;  (** 5b's origin ghost *)
}
(** Map colours (handoff 4b, 4h): the record {!Herbier_geo.Style} declares,
    filled here from the CSS tokens. *)

type t = {map : map}
(** The custom properties OCaml reads once at startup. *)

type error =
  | Missing_tokens of string list
      (** The custom properties that are missing or empty: [app.css] is not
          loaded or [_tokens.sass] lost a token. *)

val load : unit -> (t, error) result
