type t = Searching | Fix of Herbier_domain.Observation.position | No_fix

let position = function Fix p -> Some p | Searching | No_fix -> None
