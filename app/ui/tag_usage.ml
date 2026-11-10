module Db = Herbier_store.Db
module Tags = Herbier_store.Tags
module Tag = Herbier_domain.Tag

type t = {tag : Tag.t; plants : Herbier_domain.Ids.Plant_id.t list}

let load db =
  let open Fut.Result_syntax in
  let* tags = Db.all db Tags.list in
  let+ links = Db.all db Tags.links in
  List.map
    (fun (tag : Tag.t) ->
      {tag; plants = List.concat (Collection_filter.tagged links [tag.id])})
    tags
