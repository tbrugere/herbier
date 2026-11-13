module Source = Herbier_domain.Reference.Source

type 'a t = {value : 'a; sources : Source.t list}

let v sources value = {value; sources}
