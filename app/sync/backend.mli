(** Where this build signs in, fixed at build time (app/sync/dune, from
    HERBIER_SUPABASE_URL, HERBIER_SUPABASE_PUBLISHABLE_KEY,
    HERBIER_GOOGLE_WEB_CLIENT_ID). [""] means unset. *)

val supabase_url : string
val publishable_key : string
val google_web_client_id : string
