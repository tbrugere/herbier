(** The bytes behind a [webPath], the URL the WebView serves a plugin's file at
    ({!Cap_camera.media}). *)

val blob : string -> (Brr.Blob.t, string) result Fut.t
(** [blob web_path] is [fetch(web_path)]'s body as a [Blob]. A failed request is
    [Error] with its message; a response that is not [ok] is
    [Error "HTTP <status> <statusText>"], so the body of an error page never
    reaches a reader as if it were the file. *)
