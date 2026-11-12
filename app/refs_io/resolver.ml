let resolve link = Http.run (Herbier_refs.Resolve.resolve link)

let resolve_text text =
  let link = Herbier_domain.Link.classify text in
  Fut.map (fun outcome -> (link, outcome)) (resolve link)
