(** The organ photos of 4f (architecture §6): which Pl@ntNet images a plant
    keeps in [ref_images], which thumbnails to download, which to show, and the
    thumbnail size. Pure; never raises. *)

module Reference := Herbier_domain.Reference

val host : string
(** ["bs.plantnet.org"]: the one host a thumbnail is downloaded from. *)

val downloadable : string -> bool
(** [true] iff the URL starts with ["https://" ^ host ^ "/"], has a non-empty
    path after that slash, and contains no whitespace, control character, ['"'],
    ['<'], ['>'] or backslash. [http://…], another host, a host suffix
    (["bs.plantnet.org.evil.com"]), userinfo (["https://x@bs.plantnet.org/…"])
    and a port are all [false]. Bytes [>= 0x80] (UTF-8 text) are accepted. *)

val wanted :
  Sources.Gbif.Image.t list -> (Reference.Organ.t * Sources.Gbif.Image.t) list
(** Per organ in [Reference.Organ.all] order, the first image of that organ
    whose [url] is {!downloadable}; organs without one are absent. Images with
    [organ = None] are ignored. [Projection] picks its [organ_photos] with it
    from the whole media page; [Projection.organ_photos_wanted] gives the result
    paired with the organs. *)

type plan = {
  put : Reference.Image.t list;
      (** Rows to write ([Herbier_store.Ref_images.put]): a wanted organ with no
          stored row, or whose stored row differs in [remote_url], [licence] or
          [attribution]. [source = Plantnet]; [thumb_path] is the stored one
          when [remote_url] is unchanged, else [None]. Organ order. *)
  remove : Reference.Image.t list;
      (** Stored [Plantnet] rows of the plant whose organ is not wanted (any
          [thumb_path]); their files are deleted. Organ order. *)
}

val plan :
  plant:Herbier_domain.Ids.Plant_id.t ->
  wanted:(Reference.Organ.t * Sources.Gbif.Image.t) list ->
  stored:Reference.Image.t list ->
  plan
(** Stored rows of another plant or another source are ignored (never removed).
    [wanted = []] removes every stored Plantnet row. A wanted organ whose stored
    row is equal on all three fields is in neither list. *)

val to_download : Reference.Image.t list -> Reference.Image.t list
(** Rows with [thumb_path = None], organ order. *)

val shown :
  wanted:(Reference.Organ.t * Sources.Gbif.Image.t) list ->
  stored:Reference.Image.t list ->
  (Reference.Image.t * string) list
(** What 4f shows: per wanted organ, in order, the stored [Plantnet] row of that
    organ whose [remote_url] equals the wanted image's [url] and whose
    [thumb_path] is [Some path], with [path]. A stored row whose URL is not the
    wanted one (a relink or a refresh changed the image, its new thumbnail not
    downloaded yet) is not shown; neither is a row without a thumbnail. *)

(** {1 A sync's report} *)

type 'failure outcome =
  | Present  (** Row and thumbnail already there: nothing done. *)
  | Updated
      (** Row rewritten with a new licence or attribution, its thumbnail kept:
          the credits shown change. *)
  | Downloaded  (** Thumbnail written and the row points at it. *)
  | Removed  (** The organ is no longer wanted: row (and file) deleted. *)
  | Failed of 'failure
      (** The thumbnail could not be had; the payload says why. *)

val changed : (Reference.Organ.t * _ outcome) list -> bool
(** Some [Updated], [Downloaded] or [Removed]: what 4f shows changed. *)

val report :
  wanted:(Reference.Organ.t * Sources.Gbif.Image.t) list ->
  plan:plan ->
  (Reference.Image.t * 'failure outcome) list ->
  (Reference.Organ.t * 'failure outcome) list
(** [report ~wanted ~plan downloads], in [Reference.Organ.all] order: an organ
    with a row in [plan.remove] is [Removed]; else its outcome in [downloads]
    (one per row of {!to_download}); else [Updated] when [plan.put] has its row;
    else [Present] when it is wanted; else it is left out. *)

(** {1 Thumbnail size} *)

val max_side : int
(** [300]: the thumbnail's shorter side, in pixels, at most (the short-side
    counterpart of [Photos.Preview_size], which bounds the long side). *)

val quality : float
(** [0.8]: JPEG quality of a thumbnail. *)

val fit : width:int -> height:int -> int * int
(** Scaled so the shorter side is at most {!max_side}, aspect ratio kept
    (rounded to nearest), never upscaled, never below 1 × 1. [width] or [height]
    [<= 0] gives [(1, 1)]. *)
