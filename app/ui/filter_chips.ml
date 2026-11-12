module Tag = Herbier_domain.Tag
module Tag_id = Herbier_domain.Ids.Tag_id
module W = Widgets

type chip = Year of int | To_identify of int | Tag of Tag.t

let chips ~year_of (f : State.filters) observations tags =
  let years = Journal_filter.year_chips ~year_of ~year:f.year observations in
  let to_identify =
    match
      Journal_filter.to_identify_chip ~to_identify_only:f.to_identify_only
        observations
    with
    | None -> []
    | Some n -> [To_identify n]
  in
  List.concat
    [
      List.map (fun y -> Year y) years;
      to_identify;
      List.map (fun t -> Tag t) tags;
    ]

let el state chip =
  let filters = State.filters state in
  let update f = State.set_filters state (f (React.S.value filters)) in
  let active pred = React.S.map pred filters in
  let c, toggle =
    match chip with
    | Year y ->
        ( W.Chip.filter ~label:(string_of_int y)
            ~active:
              (active (fun (f : State.filters) ->
                   Option.equal Int.equal f.year (Some y)))
            (),
          fun (f : State.filters) ->
            {
              f with
              year =
                (match f.year with
                | Some z when Int.equal z y -> None
                | Some _ | None -> Some y);
            } )
    | To_identify n ->
        ( W.Chip.filter ~tone:W.Chip.Ochre
            ~label:(Printf.sprintf "À identifier · %d" n)
            ~active:(active (fun (f : State.filters) -> f.to_identify_only))
            (),
          fun (f : State.filters) ->
            {f with to_identify_only = not f.to_identify_only} )
    | Tag (t : Tag.t) ->
        ( W.Chip.filter ~label:t.name
            ~active:
              (active (fun (f : State.filters) ->
                   List.exists (Tag_id.equal t.id) f.tags))
            (),
          fun (f : State.filters) ->
            {f with tags = Collection_filter.toggle_tag t.id f.tags} )
  in
  (c.el, Rb.act c.click (fun () -> update toggle) :: c.bindings)
