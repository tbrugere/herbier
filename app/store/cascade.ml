let observation ~at ~photos id =
  List.map (fun p -> Photos.soft_delete p ~at) photos
  @ [Observations.soft_delete id ~at]

let plant ~at ~photos ~observations ~tags id =
  List.concat
    [
      List.map (fun p -> Photos.soft_delete p ~at) photos;
      List.map (fun o -> Observations.soft_delete o ~at) observations;
      List.map (fun tag -> Tags.untag ~plant:id ~tag ~at) tags;
      [Plants.soft_delete id ~at];
    ]
