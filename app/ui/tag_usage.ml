module Collection_filter = Herbier_ui_model.Collection_filter
module Db = Herbier_store_io.Db
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
