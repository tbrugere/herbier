module Link = Herbier_domain.Link

let header = function
  | Link.Gbif _ -> "lien GBIF reconnu"
  | Link.Plantnet _ | Link.Plantnet_observation _ -> "lien Pl@ntNet reconnu"
  | Link.Plantuse _ -> "lien Pl@ntUse reconnu"
  | Link.Wikipedia _ -> "lien Wikipédia reconnu"
  | Link.Inpn _ -> "lien INPN reconnu"
  | Link.Tela _ -> "lien Tela Botanica reconnu"
  | Link.Powo _ -> "lien POWO reconnu"
  | Link.Inat _ -> "lien iNaturalist reconnu"
  | Link.Text _ -> "partage reçu"

let query = function
  | Link.Plantnet n | Link.Plantuse n -> n
  | Link.Wikipedia {title; _} -> title
  | Link.Text s -> String.trim s
  | Link.Gbif _ | Link.Plantnet_observation _ | Link.Inpn _ | Link.Tela _
  | Link.Powo _ | Link.Inat _ ->
      ""
