let location () = Jv.get (Brr.Window.to_jv Brr.G.window) "location"

let replace uri =
  ignore (Jv.call (location ()) "replace" [|Jv.of_jstr (Brr.Uri.to_jstr uri)|])

let origin () = Jv.to_string (Jv.get (location ()) "origin")
