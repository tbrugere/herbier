(** This build's backend and Google values, fixed at build time (app/sync/dune,
    from HERBIER_SUPABASE_URL, HERBIER_SUPABASE_PUBLISHABLE_KEY,
    HERBIER_GOOGLE_WEB_CLIENT_ID, HERBIER_GOOGLE_CLOUD_PROJECT_NUMBER). [""]
    means unset. None of them is a secret: each is readable by anyone who has
    the APK. *)

val supabase_url : string
val publishable_key : string
val google_web_client_id : string

val google_cloud_project_number : string
(** The Google Cloud project number: Google Picker's app id
    ([PickerBuilder.setAppId]), which makes a picked folder part of the app's
    drive.file grant. No default. *)
