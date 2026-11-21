module Reference = Herbier_domain.Reference
module Organ_photos = Herbier_refs.Organ_photos

type slide = {
  organ : Reference.Organ.t;
  thumb_path : string;
  full_url : string;
  label : string;
  credit : string;
  alt : string;
}
[@@deriving eq, show]

let plantnet = Ref_text.source_name Reference.Source.Plantnet

let credit (i : Reference.Image.t) =
  String.concat " · "
    (List.filter
       (fun s -> s <> "")
       [String.trim i.attribution; String.trim i.licence; plantnet])

let slide ((i : Reference.Image.t), thumb_path) =
  let label = Ref_text.organ_label i.organ in
  {
    organ = i.organ;
    thumb_path;
    full_url = i.remote_url;
    label;
    credit = credit i;
    alt = Printf.sprintf "Photo %s : %s" plantnet label;
  }

let slides p ~stored =
  List.map slide
    (Organ_photos.shown
       ~wanted:(Herbier_refs.Projection.organ_photos_wanted p)
       ~stored)

let start slides organ =
  List.find_index (fun s -> Reference.Organ.equal s.organ organ) slides
  |> Option.value ~default:0
