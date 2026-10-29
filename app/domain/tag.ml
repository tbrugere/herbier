type id = Ids.Tag_id.t

type t = {
  id : id;
  name : string;
  created_at : Ptime.t;
  updated_at : Ptime.t;
  deleted_at : Ptime.t option;
}

module Plant_tag = struct
  type id = Ids.Plant_tag_id.t

  type t = {
    id : id;
    plant_id : Ids.Plant_id.t;
    tag_id : Ids.Tag_id.t;
    created_at : Ptime.t;
    updated_at : Ptime.t;
    deleted_at : Ptime.t option;
  }
end
