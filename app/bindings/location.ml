let replace uri =
  let location = Jv.get (Brr.Window.to_jv Brr.G.window) "location" in
  ignore (Jv.call location "replace" [|Jv.of_jstr (Brr.Uri.to_jstr uri)|])
