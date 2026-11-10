let plugin = "camera"

type media = {web_path : string; uri : string option}

(* MediaTypeSelection.Photo, an enum member vendor.js does not export. *)
let photo_only = Jv.of_int 0

let options ~limit =
  Jv.obj
    [|
      ("mediaType", photo_only);
      ("allowMultipleSelection", Jv.true');
      ("limit", Jv.of_int limit);
      ("includeMetadata", Jv.false');
      (* The gallery path ignores these three; set so that a plugin version
         that honours them still returns the original bytes. *)
      ("editable", Jv.of_string "no");
      ("correctOrientation", Jv.false');
      ("quality", Jv.of_int 100);
    |]

let media item =
  match Cap_call.string_field item "webPath" with
  | Ok web_path ->
      let uri = Result.to_option (Cap_call.string_field item "uri") in
      Ok {web_path; uri}
  | Error _ -> Error (Cap_error.Unexpected "results.webPath")

let results r =
  match Cap_call.field r "results" with
  | Ok items when Jv.is_array items ->
      Jv.to_list Fun.id items
      |> List.fold_left
           (fun acc item ->
             Result.bind acc (fun l ->
                 Result.map (fun m -> m :: l) (media item)))
           (Ok [])
      |> Result.map List.rev
  | Ok _ | Error _ -> Error (Cap_error.Unexpected "results")

let choose_photos ~limit =
  Cap_call.call plugin "chooseFromGallery" [|options ~limit|] ~ok:results
