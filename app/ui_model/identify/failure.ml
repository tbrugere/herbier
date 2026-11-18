module Plantnet = Herbier_identify.Plantnet

type error =
  | Not_sent_offline
  | Preview_unreadable
  | Plantnet of Plantnet.error
[@@deriving eq]

type t =
  | No_plant of {can_force : bool}
  | Not_answered
  | Offline
  | Used_up
  | Key_refused
  | No_key
  | Unreadable
[@@deriving eq, show]

let of_error ~no_reject = function
  | Plantnet No_plant -> No_plant {can_force = not no_reject}
  | Plantnet
      ( Unreachable (_ : Plantnet.unreachable)
      | Key_not_exposed
      | Refused_request (_ : int)
      | Malformed (_ : string)
      | No_photo ) ->
      Not_answered
  | Plantnet Quota_used_up -> Used_up
  | Plantnet Key_refused -> Key_refused
  | Plantnet No_key -> No_key
  | Not_sent_offline -> Offline
  | Preview_unreadable -> Unreadable

let retry = function
  | Not_answered | Offline -> true
  | No_plant _ | Used_up | Key_refused | No_key | Unreadable -> false

let reask = function
  | No_plant _ | Not_answered | Offline -> true
  | Used_up | Key_refused | No_key | Unreadable -> false

let of_gate : Identify_settings.gate -> (Identify_settings.Key.t, error) result
    = function
  | Ready k -> Ok k
  | Offline | Waiting -> Error Not_sent_offline
  | No_key -> Error (Plantnet No_key)
