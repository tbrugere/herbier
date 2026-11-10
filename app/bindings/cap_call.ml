let has_type ty v = String.equal (Jstr.to_string (Jv.typeof v)) ty

(* String(v) can itself throw (an object without a prototype has no
   toString); it runs inside a promise callback, where a raise would leave
   the future undetermined. *)
let string_of_value v =
  match Jv.apply (Jv.get Jv.global "String") [|v|] with
  | s -> Jv.to_string s
  | exception Jv.Error _ -> "unprintable JavaScript value"

let plugin name =
  Jv.find_path Jv.global ["herbier"; name]
  |> Option.to_result ~none:(Cap_error.Unavailable name)

let string_prop v name =
  match Jv.find v name with
  | Some s when has_type "string" s -> Some (Jv.to_string s)
  | Some _ | None -> None

let rejected v =
  match Jstr.to_string (Jv.typeof v) with
  | "string" -> Cap_error.Rejected {code = None; message = Jv.to_string v}
  | "object" when Jv.is_some v ->
      let message =
        match string_prop v "message" with
        | Some m -> m
        | None -> string_of_value v
      in
      Cap_error.Rejected {code = string_prop v "code"; message}
  | _ -> Cap_error.Rejected {code = None; message = string_of_value v}

(* Promise.resolve also accepts a method that returns a plain value; the
   exception handlers cover a missing method and a plugin throwing before it
   returns a promise. jsoo turns a thrown Error into [Jv.Error] but any other
   thrown value (a string, a plain object) into [Failure (String(value))]. *)
let on o meth args ~ok =
  match Jv.Promise.resolve (Jv.call o meth args) with
  | p -> Fut.map Result.join (Fut.of_promise' ~ok ~error:rejected p)
  | exception Jv.Error e -> Fut.return (Error (rejected (Jv.of_error e)))
  | exception Failure message ->
      Fut.return (Error (Cap_error.Rejected {code = None; message}))

let call name meth args ~ok =
  match plugin name with
  | Ok p -> on p meth args ~ok
  | Error e -> Fut.return (Error e)

let unit_ok (_ : Jv.t) = Ok ()

let field v path =
  Option.bind (Jv.to_option Fun.id v) (fun v ->
      Jv.find_path v (String.split_on_char '.' path))
  |> Option.to_result ~none:(Cap_error.Unexpected path)

let typed_field ty conv v path =
  Result.bind (field v path) (fun x ->
      match has_type ty x with
      | true -> conv x |> Option.to_result ~none:(Cap_error.Unexpected path)
      | false -> Error (Cap_error.Unexpected path))

let to_int x =
  let f = Jv.to_float x in
  match
    Float.is_integer f && f >= Float.of_int min_int && f <= Float.of_int max_int
  with
  | true -> Some (Float.to_int f)
  | false -> None

let string_field = typed_field "string" (fun x -> Some (Jv.to_string x))
let int_field = typed_field "number" to_int

let finite x =
  let f = Jv.to_float x in
  match Float.is_finite f with true -> Some f | false -> None

let float_field = typed_field "number" finite
let bool_field = typed_field "boolean" (fun x -> Some (Jv.to_bool x))
