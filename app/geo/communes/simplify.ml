module Places = Herbier_domain.Places

let metres_per_degree = Float.pi *. Places.earth_radius_m /. 180.

(* Distance in metres from (px, py) to the segment (ax, ay)-(bx, by), all in
   a local metric projection. *)
let segment_distance (px, py) (ax, ay) (bx, by) =
  let dx = bx -. ax and dy = by -. ay in
  let len2 = (dx *. dx) +. (dy *. dy) in
  let t =
    match len2 > 0. with
    | false -> 0.
    | true ->
        Float.max 0.
          (Float.min 1. ((((px -. ax) *. dx) +. ((py -. ay) *. dy)) /. len2))
  in
  let x = ax +. (t *. dx) -. px and y = ay +. (t *. dy) -. py in
  Float.sqrt ((x *. x) +. (y *. y))

let simplify ~tolerance_m (ring : Pack.ring) =
  let n = Array.length ring in
  match n < 4 with
  | true -> ring
  | false -> (
      let lon0, lat0 = ring.(0) in
      let c = Float.cos (lat0 *. Float.pi /. 180.) in
      let xy =
        Array.map
          (fun (lon, lat) ->
            ( (lon -. lon0) *. c *. metres_per_degree,
              (lat -. lat0) *. metres_per_degree ))
          ring
      in
      (* Index i of the closed ring, n standing for 0 again. *)
      let at i = xy.(i mod n) in
      let far =
        let rec go i (best, best_i) =
          match i >= n with
          | true -> best_i
          | false ->
              let x, y = xy.(i) in
              let d = (x *. x) +. (y *. y) in
              go (i + 1)
                (match d > best with true -> (d, i) | false -> (best, best_i))
        in
        go 1 (-1., 0)
      in
      (* style: a keep array local to this call, filled by the recursion. *)
      let keep = Array.make n false in
      let rec dp first last =
        match last - first < 2 with
        | true -> ()
        | false -> (
            let a = at first and b = at last in
            let rec farthest i (best, best_i) =
              match i >= last with
              | true -> (best, best_i)
              | false ->
                  let d = segment_distance (at i) a b in
                  farthest (i + 1)
                    (match d > best with
                    | true -> (d, i)
                    | false -> (best, best_i))
            in
            let d, i = farthest (first + 1) (-1., first) in
            match d > tolerance_m with
            | false -> ()
            | true ->
                keep.(i mod n) <- true;
                dp first i;
                dp i last)
      in
      keep.(0) <- true;
      keep.(far) <- true;
      dp 0 far;
      dp far n;
      let out =
        Array.of_list
          (List.rev
             (snd
                (Array.fold_left
                   (fun (i, acc) v ->
                     match keep.(i) with
                     | true -> (i + 1, v :: acc)
                     | false -> (i + 1, acc))
                   (0, []) ring)))
      in
      match Array.length out < 3 with true -> ring | false -> out)
