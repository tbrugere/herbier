let threshold = 140

let collapsible text =
  let text = String.trim text in
  String.contains text '\n'
  || Herbier_refs.Wiki_text.code_points text > threshold
