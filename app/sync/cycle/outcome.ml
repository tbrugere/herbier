type stop =
  | Signed_out
  | Auth of string
  | Offline of string
  | Paused
  | Unauthorized
  | Transient of int
  | Rejected of int
  | Bad_response of string
  | Store of string
[@@deriving eq, show]

let to_string = function
  | Signed_out -> "signed out"
  | Auth m -> "auth: " ^ m
  | Offline m -> "offline: " ^ m
  | Paused -> "paused"
  | Unauthorized -> "HTTP 401"
  | Transient s | Rejected s -> Printf.sprintf "HTTP %d" s
  | Bad_response m -> "bad response: " ^ m
  | Store m -> "store: " ^ m

let retries = function
  | Signed_out -> false
  | Auth _ | Offline _ | Paused | Unauthorized | Transient _ | Rejected _
  | Bad_response _ | Store _ ->
      true

let persistent = function
  | Rejected _ | Bad_response _ | Store _ -> true
  | Signed_out | Auth _ | Offline _ | Paused | Unauthorized | Transient _ ->
      false
