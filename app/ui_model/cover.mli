(** Which photo stands for a plant (4a cards, the 4f hero, the 5a cover picker).
    Pure. *)

module Photo := Herbier_domain.Photo
module Photo_id := Herbier_domain.Ids.Photo_id
module Plant_id := Herbier_domain.Ids.Plant_id
module Observation := Herbier_domain.Observation

val ordered : Photo_id.t option -> Photo.t list -> Photo.t list
(** [ordered cover photos] is the plant's [photos] (as the store gives them,
    newest first) with [cover] (its [cover_photo_id]) first when it is among
    them, else [photos] unchanged: a cover pointing at a deleted or not yet
    pulled photo falls back to the newest. The 4f hero pages in this order. *)

val choose : Photo_id.t option -> Photo.t list -> Photo.t option
(** The head of {!ordered}: the chosen cover, else the newest photo. *)

val by_plant : Observation.t list -> Photo.t list -> Plant_id.t -> Photo.t list
(** [by_plant observations photos] indexes [photos] by the plant of their
    observation, keeping their order; photos of an unlinked or unknown
    observation belong to no plant. Built in one pass over each list; a lookup
    is a table lookup. *)
