(** What is drawn under Android's system bars, and so which icons they need.
    Pure: the app knows its dark surfaces (4d Noter, 5e viewer, 6d Comparer, the
    offline strip); everything else is paper. *)

type surface =
  | Light
      (** paper: the tabs, fiches, forms, sheets, the identification layer *)
  | Dark
      (** [--dark]/[--ink]: 4d, 5e, 6d, 4d's own viewfinder while it takes a
          photo for 6c, the offline strip *)
[@@deriving eq, show]

type bar = Status | Navigation [@@deriving eq, show]

type t = {status : surface; navigation : surface} [@@deriving eq, show]
(** The surface under each bar. *)

val resolve : route:surface -> overlays:surface list -> offline_banner:bool -> t
(** [overlays] top first (as [Herbier_ui.Overlay] stacks them). The top surface
    is the head of [overlays], else [route]. [navigation] is the top surface;
    [status] is [Dark] while [offline_banner] (the strip sits in the status
    bar's band, above every screen and layer), else the top surface. Total. *)

val changes : previous:t option -> t -> (bar * surface) list
(** The bar styles to send to go from [previous] to [t]: both bars, [Status]
    first, when [previous] is [None]; else only the bars whose surface differs,
    [Status] first; [[]] when equal. Total. *)
