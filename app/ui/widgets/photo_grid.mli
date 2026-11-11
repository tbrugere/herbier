(** « Mes photos » (4f): a grid of square previews, each striped while its file
    loads. Badges: [ochre] « ↑ » top right while the original is not yet in
    Drive ({!Herbier_domain.Photo.awaiting_drive}); « local » bottom left when
    the photo lives only in Herbier. *)

module Photo := Herbier_domain.Photo

type t = {el : Brr.El.t; tap : Photo.t React.event; bindings : Rb.binding list}

val tile : ?cls:string -> Photo.t -> Brr.El.t
(** One preview with its badges, not interactive (4h mosaic). *)

val v : Photo.t list -> t
(** The grid; [tap] fires with the tapped tile's photo. Each tile is a button
    labelled with its position and what its badges show. *)
