module Source = Herbier_domain.Reference.Source
module Status = Herbier_domain.Reference.Status
module Plantuse = Sources.Plantuse

let row status page : Fanout.row =
  {source = Source.Plantuse; status; payload = Payload.plantuse ~page}

let program (input : Regional.input) =
  let titles = Option.fold ~none:[] ~some:Plantuse.titles input.name in
  match Plantuse.page ~titles with
  | None -> (
      match input.settled with
      | true -> Step.return [row Status.Missing None]
      | false -> Step.return [row Status.Failed None])
  | Some request -> (
      let open Step.Syntax in
      let+ response = Step.get request in
      match response with
      | Step.Absent | Step.Failed _ -> [row Status.Failed None]
      | Step.Body json -> (
          match Plantuse.answer_of_json json with
          | Error _ -> [row Status.Failed None]
          | Ok answer -> (
              match Plantuse.find ~name:input.name answer with
              | Some _ -> [row Status.Complete (Some json)]
              | None -> [row Status.Missing (Some json)])))
