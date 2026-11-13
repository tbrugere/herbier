module Make (H : Net.Rest.HTTP) (L : Local.S with module IO = H.IO) = struct
  let return = H.IO.return

  module Syntax = struct
    let ( let* ) = H.IO.bind

    let ( let*? ) io f =
      H.IO.bind io (function Error e -> return (Error e) | Ok v -> f v)
  end

  let fold f init l =
    let open Syntax in
    let rec go acc = function
      | [] -> return (Ok acc)
      | x :: rest ->
          let*? acc = f acc x in
          go acc rest
    in
    go init l

  let store_error e = Outcome.Store (L.error_to_string e)

  let store io =
    let open Syntax in
    let* result = io in
    return (Result.map_error store_error result)

  let stop_of_error : Net.Rest.Make(H).error -> Outcome.stop = function
    | Offline e -> Offline (H.error_to_string e)
    | Paused -> Paused
    | Unauthorized -> Unauthorized
    | Transient s -> Transient s
    | Rejected s -> Rejected s
    | Bad_response b -> Bad_response (Net.Rest.bad_response_to_string b)
end
