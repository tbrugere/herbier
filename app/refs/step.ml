type response = Body of Yojson.Safe.t | Absent | Failed of string
type 'a t = Done of 'a | Get of Request.t * (response -> 'a t)

let return x = Done x
let get request = Get (request, fun response -> Done response)

let rec bind t f =
  match t with
  | Done x -> f x
  | Get (request, k) -> Get (request, fun response -> bind (k response) f)

let map f t = bind t (fun x -> Done (f x))

let rec recover f = function
  | Done _ as t -> t
  | Get (request, k) ->
      Get
        ( request,
          fun response ->
            match k response with
            | next -> recover f next
            | exception e -> Done (f (Printexc.to_string e)) )

module Syntax = struct
  let ( let* ) = bind
  let ( let+ ) t f = map f t
end

let rec run answer = function
  | Done x -> x
  | Get (request, k) -> run answer (k (answer request))

let requests answer t =
  let rec go acc = function
    | Done _ -> List.rev acc
    | Get (request, k) -> go (request :: acc) (k (answer request))
  in
  go [] t
