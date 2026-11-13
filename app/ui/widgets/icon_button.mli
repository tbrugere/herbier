(** A round icon button of a header or a map ([Retour], [Fermer],
    [Ma position]). *)

val el : ?classes:string list -> label:string -> Icon.t -> Brr.El.t
(** {!Html.button} with [label], classes [icon-button] then [classes], holding
    the icon. *)
