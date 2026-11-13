type t = Creating | Ready of Herbier_geo_io.Map.t | Failed | Released

let alive = function Released -> false | Creating | Ready _ | Failed -> true

let release slot =
  match !slot with
  | Ready m ->
      slot := Released;
      Herbier_geo_io.Map.remove m
  | Creating | Failed | Released -> slot := Released
