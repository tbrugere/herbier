type t = {
  south : float; [@equal Float.equal]
  west : float; [@equal Float.equal]
  north : float; [@equal Float.equal]
  east : float; [@equal Float.equal]
}
[@@deriving eq]

let of_point ({lat; lon} : Places.point) =
  {south = lat; west = lon; north = lat; east = lon}

let extend {south; west; north; east} ({lat; lon} : Places.point) =
  {
    south = Float.min south lat;
    west = Float.min west lon;
    north = Float.max north lat;
    east = Float.max east lon;
  }

let of_points = function
  | [] -> None
  | p :: rest -> Some (List.fold_left extend (of_point p) rest)

let contains ?(dlat = 0.) ?(dlon = 0.) b ({lat; lon} : Places.point) =
  b.west -. dlon <= lon
  && lon <= b.east +. dlon
  && b.south -. dlat <= lat
  && lat <= b.north +. dlat
