module Plant = Herbier_domain.Plant
module Plant_id = Herbier_domain.Ids.Plant_id

let same (a : Plant.t) (b : Plant.t) = Plant_id.equal a.id b.id

let equal (a : Plant.t) (b : Plant.t) =
  same a b && Ptime.equal a.updated_at b.updated_at
