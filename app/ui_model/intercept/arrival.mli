(** What arrived: a shared text or an opened URL, trimmed and capped
    ([Intercept.cap], [of_url], [of_share]). *)

val cap : int
val of_url : string -> string option
val of_share : title:string -> texts:string list -> string option
