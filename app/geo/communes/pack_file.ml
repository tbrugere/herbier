module Json = Herbier_net.Json

let fixed v = `Int (Float.to_int (Float.round (v *. 1e5)))

let ring_json (r : Pack.ring) =
  `List
    (Array.fold_right
       (fun (lon, lat) acc -> fixed lon :: fixed lat :: acc)
       r [])

let to_string (p : Pack.t) =
  Yojson.Safe.to_string
    (`Assoc
       [
         ("format", `Int 1);
         ("layer", `String Pack.layer);
         ("departement", `String (Code.to_string p.departement));
         ("tolerance_m", `Int (Float.to_int Pack.tolerance_m));
         ( "communes",
           `List
             (List.map
                (fun (c : Pack.commune) ->
                  `Assoc
                    [
                      ("insee", `String c.insee);
                      ("name", `String c.name);
                      ( "polygons",
                        `List
                          (List.map
                             (fun rings -> `List (List.map ring_json rings))
                             c.polygons) );
                    ])
                p.communes) );
       ])

(* Strict decoding of our own file: the first malformed field is the
   error. *)
let unexpected path expected = Error (Geocode.Unexpected {path; expected})

let all_indexed path f l =
  let open Result.Syntax in
  let+ rev =
    List.fold_left
      (fun acc x ->
        let* i, acc = acc in
        let+ y = f (Printf.sprintf "%s/%d" path i) x in
        (i + 1, y :: acc))
      (Ok (0, []))
      l
  in
  List.rev (snd rev)

let stored_ring path = function
  | `List values -> (
      let n = List.length values in
      match n mod 2 = 0 && n >= 6 with
      | false -> unexpected path "an even list of at least 6 integers"
      | true -> (
          match Pack.all (function `Int i -> Some i | _ -> None) values with
          | None -> unexpected path "integers"
          | Some ints ->
              let rec pairs acc = function
                | x :: y :: rest ->
                    pairs
                      ((Float.of_int x /. 1e5, Float.of_int y /. 1e5) :: acc)
                      rest
                | [] | [_] -> List.rev acc
              in
              Ok (Array.of_list (pairs [] ints))))
  | _ -> unexpected path "array"

let stored_polygon path = function
  | `List (_ :: _ as rings) -> all_indexed path stored_ring rings
  | _ -> unexpected path "a non-empty array"

let stored_string path field json =
  match Json.member field json with
  | Some (`String s) -> Ok s
  | _ -> unexpected (path ^ "/" ^ field) "string"

let stored_commune path json =
  let open Result.Syntax in
  let* insee = stored_string path "insee" json in
  let* name = stored_string path "name" json in
  let* polygons =
    match Json.member "polygons" json with
    | Some (`List (_ :: _ as polygons)) ->
        all_indexed (path ^ "/polygons") stored_polygon polygons
    | _ -> unexpected (path ^ "/polygons") "a non-empty array"
  in
  Ok ({insee; name; polygons} : Pack.commune)

let of_string s =
  let open Result.Syntax in
  let* json = Geocode.json_of_string s in
  let* () =
    match Json.member "format" json with
    | Some (`Int 1) -> Ok ()
    | _ -> unexpected "/format" "1"
  in
  let* departement =
    let* code = stored_string "" "departement" json in
    match Code.of_string code with
    | Some code -> Ok code
    | None -> unexpected "/departement" "a département code"
  in
  let* communes =
    match Json.member "communes" json with
    | Some (`List (_ :: _ as communes)) ->
        all_indexed "/communes" stored_commune communes
    | _ -> unexpected "/communes" "a non-empty array"
  in
  Ok ({departement; communes} : Pack.t)
