(** 5a « + Coller un lien »: pasted text → the plant's id at one source. Pure.
*)

type t =
  | Species of int
      (** A GBIF species link: the species itself, changed with « Changer › »,
          not stored as a plain ref. *)
  | Plant_ref of {
      source : Herbier_domain.Reference.Source.t;
      external_id : string;
      url : string;
    }
  | Not_a_reference  (** A Pl@ntUse page or a Pl@ntNet observation. *)
  | Unrecognised  (** [Link.classify] gave [Text _]. *)

val equal : t -> t -> bool

val of_text : string -> t
(** [Link.classify text], then:
    - [Gbif k] → [Species k];
    - [Plantnet name] → [Plantnet], [name], [Source_url.plantnet name];
    - [Wikipedia {lang; title}] → [Wikipedia], [lang ^ ":" ^ title],
      [Source_url.wikipedia ~lang title];
    - [Inpn cd] → [Taxref], [cd], [Source_url.taxref cd];
    - [Tela nn] → [Tela], [nn], [Source_url.tela nn];
    - [Powo id] → [Powo], [id], [Source_url.powo id];
    - [Inat id] → [Inat], [id], [Source_url.inat id];
    - [Plantuse _], [Plantnet_observation _] → [Not_a_reference];
    - [Text _] → [Unrecognised].

    [Source_url] is [Herbier_refs.Source_url]. The stored URL is canonical
    (without the pasted query or fragment) and [Link.classify url] gives back
    the link the text classified as. *)

val removable : Herbier_domain.Reference.Plant_ref.t -> bool
(** Every source but [Gbif] (the species link is changed, not removed). *)

val label : Herbier_domain.Reference.Plant_ref.t -> string
(** [Ref_text.source_name source ^ " · " ^ external_id], e.g.
    ["GBIF · 5414995"], ["Wikipédia · fr:Digitale pourpre"]. *)
