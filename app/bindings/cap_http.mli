(** Binding to Capacitor's core [CapacitorHttp] ([globalThis.herbier.http]):
    native HTTP, so a response is read whatever its CORS headers (the Pl@ntNet
    image host sends none). Only its plugin methods are called: the fetch patch
    stays off ([plugins.CapacitorHttp.enabled = false] in capacitor.config.ts).

    Device-only in practice: in a desktop browser the web implementation of
    [CapacitorHttp] uses [fetch], so a host without CORS headers is a [Rejected]
    error there. *)

type response =
  | Body of string  (** A 2xx status: the body, base64-encoded. *)
  | Status of int
      (** Any other status (a 3xx included: redirects are not followed). The
          error body is not read: the plugin hands it back as text, or parsed
          when its Content-Type is JSON. *)

val get_bytes :
  url:string -> timeout_ms:int -> (response, Cap_error.t) result Fut.t
(** [CapacitorHttp.get({url, responseType: "blob", connectTimeout: timeout_ms,
     readTimeout: timeout_ms, disableRedirects: true})]. A rejection (network,
    DNS, timeout) is [Error (Rejected _)]; [status] missing or not an integer →
    [Error (Unexpected "status")]; a 2xx whose [data] is not a string (a body
    the plugin parsed as JSON) → [Error (Unexpected "data")]; no plugin →
    [Error (Unavailable "http")]. *)
