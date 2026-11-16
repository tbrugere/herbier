(** Pl@ntNet's identify API v2 (architecture §12): the identify request as a
    value, its answer and the flora list decoded, and the error classes. Without
    IO ({!Make} sends). The key rides only as the [api-key] query parameter: it
    is in [url] and nowhere else, and no string built here other than a URL
    contains it. Nothing here raises. *)

val api : string
(** ["https://my-api.plantnet.org/v2"]. *)

val automatic : string
(** ["all"]: the flora Pl@ntNet picks per request (« Automatique »). *)

val nb_results : int
(** 5. *)

(** {1 Requests} *)

val identify_url : key:string -> flora:string -> no_reject:bool -> string
(** [api ^ "/identify/" ^ Url.encode flora ^
     "?include-related-images=true&lang=fr&nb-results=5" ^ (if no_reject then
     "&no-reject=true" else "") ^ "&api-key=" ^ Url.encode key]. [flora] and
    [key] are used as given (see {!identify_request} for trimming and defaults).
    For key ["K"], flora ["all"], no no-reject:
    ["https://my-api.plantnet.org/v2/identify/all?include-related-images=true&lang=fr&nb-results=5&api-key=K"].
*)

val projects_url : key:string -> string
(** [api ^ "/projects?lang=fr&api-key=" ^ Url.encode key]. Never [lat] / [lon]
    (no position leaves the phone). *)

val asked_flora : string -> string
(** The flora a request asks for: [flora] trimmed; blank → {!automatic}. *)

type 'image request = {
  flora : string;
      (** the flora asked, after the blank → {!automatic} default *)
  url : string;  (** {!identify_url}: holds the key, never log it *)
  fields : (string * string) list;
      (** one [("organs", Organ.sent_to_string o)] per photo, in photo order *)
  files : 'image Transport.file list;
      (** one [{field = "images"; filename = "photo-<i>.jpg"; image}] per photo,
          [i] from 1, in photo order *)
}

type error =
  | No_key  (** blank key: nothing sent *)
  | No_photo  (** no photo: nothing sent *)
  | No_plant  (** identify 404 ("Species not found") *)
  | Key_refused  (** 401 ("Bad token") *)
  | Key_not_exposed
      (** 403 whose body's [message] is ["CORS error: Origin not allowed"]: the
          key is not exposed for https://localhost; fixed on my.plantnet.org *)
  | Quota_used_up  (** 429: the day's 500 are spent until 00:00 UTC *)
  | Refused_request of int
      (** 400, 413, 414, 415, any other 4xx (a 403 with another body, a 404 on
          the flora list), and any non-2xx below 400: this request as is will
          not pass *)
  | Unreachable of unreachable
  | Malformed of string
      (** a 2xx whose body does not decode; names what is missing *)

(** Its own type rather than {!Transport.failure}: it adds [Server], and
    [Network] does not keep the transport's text, which is not trusted to leave
    the URL (hence the key) out. *)
and unreachable =
  | Timeout  (** the transport's timeout *)
  | Network  (** the request failed (offline, DNS, refused, a JS error) *)
  | Server of int  (** 5xx *)

val equal_error : error -> error -> bool

val pp_error : Format.formatter -> error -> unit
(** Prints {!error_to_string} (tests' printer). *)

val error_to_string : error -> string
(** One line, never the key or a URL: ["no key"], ["no photo"], ["no plant"],
    ["key refused"], ["key not exposed for the app"], ["quota used up"],
    ["refused request (HTTP 413)"], ["unreachable: timeout"],
    ["unreachable: network failure"], ["unreachable: HTTP 503"],
    ["malformed answer: <what>"]. *)

val identify_request :
  key:string ->
  flora:string ->
  no_reject:bool ->
  ('image * Organ.sent) list ->
  ('image request, error) result
(** The request for these photos, in order. [key] trimmed
    ({!Herbier_domain.Text.non_blank}); blank → [Error No_key] (checked first).
    [flora] → {!asked_flora}. [[]] → [Error No_photo]. Only the first
    {!Organ.max_photos} photos are sent (a sixth is dropped, never an error).
    The gallery or file name of a photo is never used: files are always
    ["photo-<i>.jpg"]. *)

val projects_request : key:string -> (string, error) result
(** The flora list's URL, {!projects_url} with [key] trimmed; blank →
    [Error No_key]. *)

(** {1 Answers} *)

type image = {
  organ : Organ.t option;  (** [None]: ["other"] or an organ not offered *)
  author : string;
  licence : string;  (** as sent, e.g. ["cc-by-sa"] *)
  citation : string option;
  small : string;  (** [url.s], the thumbnail *)
  medium : string;  (** [url.m], the enlarged image *)
}
(** A related image. Kept only when [url.s] and [url.m] are both on
    {!image_host} ({!on_image_host}) and [author] and [license] are non-blank
    strings (trimmed): an image that cannot be credited is not shown. [o] and
    [date] are ignored. *)

val equal_image : image -> image -> bool

val image_host : string
(** ["bs.plantnet.org"]. *)

val on_image_host : string -> bool
(** {!Herbier_net.Url.under} ["https://bs.plantnet.org/"]. *)

type proposal = {
  score : float;  (** as sent, 0 to 1 *)
  name : string;  (** [species.scientificNameWithoutAuthor], trimmed *)
  author : string;
      (** [species.scientificNameAuthorship], trimmed; [""] when absent *)
  scientific_name : string;
      (** [species.scientificName] (trimmed) when a non-blank string, else
          [name] and [author] joined by a space ([name] alone when
          [author = ""]) *)
  family : string option;
      (** [species.family.scientificNameWithoutAuthor], trimmed, non-blank *)
  common_names : string list;
      (** [species.commonNames]: strings, trimmed, blanks dropped, order kept *)
  gbif : int option;
      (** [gbif.id] as a string of digits or a JSON integer, > 0; [gbif] null or
          absent, [id] absent, or anything else (["abc"], [-3], a float, digits
          that overflow [int]) → [None] *)
  images : image list;  (** Pl@ntNet's order, those kept by the rule above *)
}

val equal_proposal : proposal -> proposal -> bool

type answer = {
  proposals : proposal list;
      (** [results], Pl@ntNet's order, never re-sorted; a result without a
          numeric [score] or a non-blank [scientificNameWithoutAuthor] is
          dropped (style 8.4) *)
  detected : Organ.t option list;
      (** One per photo sent, in photo order: element [i] is photo [i + 1]. Each
          id of [query.images] (Pl@ntNet's id for each photo, in the order sent)
          is matched with the [predictedOrgans] element whose [image] is that
          id; no such element, no string [organ], or an organ not offered →
          [None] at its place. Without [query.images], [predictedOrgans] is
          taken in its own order (the photos' order in every recorded answer,
          but not documented by Pl@ntNet); [predictedOrgans] absent too → [[]]
      *)
  flora : string option;  (** [preferedReferential], non-blank *)
  remaining : int option;
      (** [remainingIdentificationRequests] when an integer *)
}

val equal_answer : answer -> answer -> bool

val decode_answer : string -> (answer, error) result
(** A 2xx identify body. Not JSON → [Error (Malformed "not JSON")]; [results]
    absent or not a list, or a non-empty [results] whose every entry is dropped
    → [Error (Malformed "results")] (Pl@ntNet answers 404, not 200, when it
    finds no species). [results = []] is [Ok] with no proposal. *)

type project = {id : string; title : string}
(** A flora of [GET /v2/projects]: [id] and its French [title]. *)

val equal_project : project -> project -> bool

val decode_projects : string -> (project list, error) result
(** A 2xx projects body: a JSON list, order kept; an entry without non-blank
    string [id] and [title] is dropped. Not JSON → [Malformed "not JSON"]; not a
    list → [Malformed "projects"]. [all] is not listed by Pl@ntNet and not added
    here. *)

(** {1 Errors} *)

type route = Identify | Projects

val error_of_answer : route:route -> status:int -> body:string -> error
(** A non-2xx answer classified, in this order: 401 → [Key_refused]; 403 whose
    body parses as JSON with [message] (trimmed) equal to
    ["CORS error: Origin not allowed"] → [Key_not_exposed]; 404 on [Identify] →
    [No_plant]; 429 → [Quota_used_up]; 500–599 → [Unreachable (Server status)];
    anything else (400, 403 otherwise, 404 on [Projects], 413, 414, 415, other
    4xx, 1xx, 3xx) → [Refused_request status]. Meant for non-2xx only (a 2xx
    gives [Refused_request status]). The body is never kept: the classes are
    what the app acts on, and an error body that may echo the request is kept
    out of the error text and the console line. *)

val error_of_failure : Transport.failure -> error
(** [Timeout] → [Unreachable Timeout]; [Network _] → [Unreachable Network] (the
    text dropped). *)
