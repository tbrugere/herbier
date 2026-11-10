(** Binding to [@capacitor/camera] ([globalThis.herbier.camera]): the gallery
    pick of the photo pipeline (architecture §5). [chooseFromGallery] needs the
    plugin's 8.1.0 or later. *)

type media = {
  web_path : string;
      (** A URL the WebView can [fetch] or show ([webPath]); the original file's
          bytes. *)
  uri : string option;
      (** The plugin's [uri]: on Android a plain filesystem path of the copy
          (["/data/user/0/…/x.jpg"], not a [file://] URI, although the plugin's
          TypeScript calls it a URI); absent on the web. *)
}

val choose_photos : limit:int -> (media list, Cap_error.t) result Fut.t
(** [chooseFromGallery] for photos only, several at once, at most [limit] (a
    non-positive [limit] is no limit; Android 13+ only, the plugin ignores it
    before). On Android the plugin returns a copy of the picked file, the
    original bytes. The system photo picker removes the GPS tags of the copy
    whatever the app holds, so a picked photo may come without a position. A
    cancelled pick is [Error (Rejected _)] as the plugin reports it. A result
    without a [results] array is [Error (Unexpected "results")]; an item without
    a string [webPath] is [Error (Unexpected "results.webPath")]. *)
