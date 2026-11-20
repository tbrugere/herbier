type id = Ids.Tag_id.t [@@deriving eq, show]

type t = {
  id : id;
  name : string;
  created_at : Ptime.t;
  updated_at : Ptime.t;
  deleted_at : Ptime.t option;
}
[@@deriving eq, show]

let v ~id ~at name =
  {id; name; created_at = at; updated_at = at; deleted_at = None}

module Plant_tag = struct
  type id = Ids.Plant_tag_id.t [@@deriving eq, show]

  type t = {
    id : id;
    plant_id : Ids.Plant_id.t;
    tag_id : Ids.Tag_id.t;
    created_at : Ptime.t;
    updated_at : Ptime.t;
    deleted_at : Ptime.t option;
  }
  [@@deriving eq, show]
end
