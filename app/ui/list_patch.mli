(** The edits that turn one list into another, for patching an [RList] so that
    only the elements that changed are re-rendered. Pure: no ReactiveData here,
    the caller applies the edits to its handle. *)

type 'a edit =
  | Remove of int  (** remove the element at this index *)
  | Insert of int * 'a  (** insert so that the element ends at this index *)
  | Update of int * 'a  (** replace the element at this index *)

val diff :
  same:('a -> 'a -> bool) ->
  equal:('a -> 'a -> bool) ->
  'a list ->
  'a list ->
  'a edit list
(** [diff ~same ~equal old next] are edits that, applied in order to [old], give
    [next]. [same] tells whether two elements are the same item (equal ids);
    [equal] whether an item is unchanged.

    When the items common to both lists are in the same relative order (both
    sorted by the same key, the case of every store list), the edits are minimal
    for that: one [Remove] per item that left, from the last index down, then,
    in ascending index, one [Insert] per item that arrived and one [Update] per
    item still there whose value changed; an unchanged item gets no edit. When
    that order differs, the edits remove everything and insert [next]. *)
