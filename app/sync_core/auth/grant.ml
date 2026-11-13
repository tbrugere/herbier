type error = Network of string | Rejected of Gotrue.error

let error_to_string = function
  | Network m -> "network: " ^ m
  | Rejected e -> Gotrue.error_to_string e

type refreshed =
  | Fresh of Session.t
  | Revoked of Gotrue.error
  | Failed of error

let refreshed = function
  | Ok fresh -> Fresh fresh
  | Error (Rejected e) when Gotrue.revokes_session e -> Revoked e
  | Error e -> Failed e
