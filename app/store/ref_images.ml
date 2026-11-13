module Reference = Herbier_domain.Reference
module Image = Reference.Image
module Organ = Reference.Organ
module Plant_id = Herbier_domain.Ids.Plant_id
module Col = Postgrest.Col
module Row = Postgrest.Row

(* A local-only table: its columns live next to its queries (layout §2), not
   in Tables. *)
type ref_images

let table : ref_images Col.table = Col.table "ref_images"

let organ_text : Organ.t Col.custom =
  Codec.text ~name:"reference_organs" ~to_string:Organ.to_string
    ~of_string:Organ.of_string

let plant_id : (ref_images, Plant_id.t, [`Mandatory]) Col.t =
  {ty = Not_Null (Custom Tables.ids_plant_id); name = "plant_id"}

let source : (ref_images, Reference.Source.t, [`Mandatory]) Col.t =
  {ty = Not_Null (Custom Tables.reference_source); name = "source"}

let organ : (ref_images, Organ.t, [`Mandatory]) Col.t =
  {ty = Not_Null (Custom organ_text); name = "organ"}

let remote_url : (ref_images, string, [`Mandatory]) Col.t =
  {ty = Not_Null Str; name = "remote_url"}

let licence : (ref_images, string, [`Mandatory]) Col.t =
  {ty = Not_Null Str; name = "licence"}

let attribution : (ref_images, string, [`Mandatory]) Col.t =
  {ty = Not_Null Str; name = "attribution"}

let thumb_path : (ref_images, string option, [`Optional]) Col.t =
  {ty = Nullable Str; name = "thumb_path"}

let row =
  let open Row.Syntax in
  let+ plant_id = Row.col plant_id
  and+ source = Row.col source
  and+ organ = Row.col organ
  and+ remote_url = Row.col remote_url
  and+ licence = Row.col licence
  and+ attribution = Row.col attribution
  and+ thumb_path = Row.col thumb_path in
  {Image.plant_id; source; organ; remote_url; licence; attribution; thumb_path}

(* Organ.all order, not the labels' alphabetical one. *)
let organ_rank =
  "case organ "
  ^ String.concat " "
      (List.mapi
         (fun i o -> Printf.sprintf "when '%s' then %d" (Organ.to_string o) i)
         Organ.all)
  ^ " end"

let of_plant plant =
  Stmt.query ~json:[] row
    ("select plant_id, source, organ, remote_url, licence, attribution, \
      thumb_path from ref_images where plant_id = ? order by source, "
    ^ organ_rank)
    [Codec.param plant_id plant]

let put (i : Image.t) =
  Stmt.upsert
    ~conflict:[plant_id.name; source.name; organ.name]
    ~table
    Postgrest.Input.
      {
        fields =
          [
            Mandatory (plant_id, Value i.plant_id);
            Mandatory (source, Value i.source);
            Mandatory (organ, Value i.organ);
            Mandatory (remote_url, Value i.remote_url);
            Mandatory (licence, Value i.licence);
            Mandatory (attribution, Value i.attribution);
            Optional (thumb_path, Value i.thumb_path);
          ];
      }

let set_thumb ~plant ~source:s ~organ:o ~remote_url:url ~path =
  {
    Stmt.sql =
      "update ref_images set thumb_path = ? where plant_id = ? and source = ? \
       and organ = ? and remote_url = ?";
    params =
      [
        Codec.param thumb_path (Some path);
        Codec.param plant_id plant;
        Codec.param source s;
        Codec.param organ o;
        Codec.param remote_url url;
      ];
  }

let remove ~plant ~source:s ~organ:o =
  {
    Stmt.sql =
      "delete from ref_images where plant_id = ? and source = ? and organ = ?";
    params =
      [Codec.param plant_id plant; Codec.param source s; Codec.param organ o];
  }
