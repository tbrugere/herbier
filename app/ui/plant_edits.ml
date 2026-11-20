module Plant_form = Herbier_ui_model.Plant_form
module Plants = Herbier_store.Plants
module Tags = Herbier_store.Tags
module Tag = Herbier_domain.Tag
module Tag_id = Herbier_domain.Ids.Tag_id

let of_change ~at ~plant (c : Plant_form.change) =
  let created =
    List.map (fun name -> Tag.v ~id:(Tag_id.fresh ()) ~at name) c.create_tags
  in
  ( created,
    List.concat
      [
        (match c.plant with
        | Some p -> [Plants.upsert {p with updated_at = at}]
        | None -> []);
        List.map Tags.upsert created;
        List.map
          (fun tag -> Tags.tag ~plant ~tag ~at)
          (c.link @ List.map (fun (t : Tag.t) -> t.id) created);
        List.map (fun tag -> Tags.untag ~plant ~tag ~at) c.unlink;
      ] )
