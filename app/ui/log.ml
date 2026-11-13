let error ?scope what detail =
  let what = match scope with Some s -> s ^ ": " ^ what | None -> what in
  Brr.Console.(error [str what; str detail])

let db ?scope what e = error ?scope what (Herbier_store_io.Db.error_to_string e)

let cap ?scope what e =
  error ?scope what (Herbier_bindings.Cap_error.to_string e)
