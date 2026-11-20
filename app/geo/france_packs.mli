(** « Toute la France » (architecture §8): every département's « IGN hors-ligne
    » pack, one after another, through the caller's per-département download
    (same WFS request, simplification, file and [commune_packs] row). This
    module only decides: what to download (the plan: skip what is present,
    estimate the size) and in which order, when to retry, to skip, to stop, and
    when a cancel takes effect. Pure; the run is a functor over the IO and the
    caller's operations ({!Make}), so test/geo drives it with a fake download.
    Nothing here raises. *)

module Code := Communes.Code

(** {1 Estimate} *)

val measured_on : string
(** The date {!France_sizes} was measured, ["YYYY-MM-DD"]. *)

val fallback_bytes : int
(** The median of {!France_sizes.table}'s sizes (lower median for an even
    count): the estimate of a code the table lacks. [> 0]. *)

val estimated_bytes : Code.t -> int
(** The stored size of that département's pack in {!France_sizes.table}; a code
    absent from it (a valid code such as ["975"]) → {!fallback_bytes}. *)

val transfer_bytes : Code.t -> int
(** What the WFS sends for that département, gzip, from
    {!France_sizes.transfer}; a code absent from it → {!fallback_bytes} scaled
    by the whole tables' transfer / stored ratio. *)

(** {1 Plan} *)

type plan = private {
  departements : Communes.departement list;
      (** the run's scope: the WFS list (after [only]), order kept *)
  todo : Communes.departement list;
      (** [departements] whose code is not downloaded, order kept *)
  present : int;  (** [List.length departements - List.length todo] *)
  total : int;  (** [List.length departements] *)
  estimate_bytes : int;  (** sum of {!estimated_bytes} over [todo] *)
  transfer_bytes : int;  (** sum of {!transfer_bytes} over [todo] *)
}

val equal_plan : plan -> plan -> bool

val plan :
  ?only:Code.t list ->
  downloaded:Code.t list ->
  Communes.departement list ->
  plan
(** [only] (default: everything) keeps the départements whose code is in it
    (codes of [only] not in the list are ignored; the list's order wins over
    [only]'s). [downloaded]: the codes of the usable packs (a pack whose file
    did not load is not present: the run downloads it again, replacing its row);
    codes outside the scope count for nothing. Calling [plan] again on a plan's
    [departements] with a longer [downloaded] is how a run resumes. *)

(** {1 Run} *)

type failure =
  | Transient  (** the same request may succeed later: retry after a wait *)
  | Skip  (** this département fails, the others may not: go on *)
  | Stop  (** nothing more should be sent now: end the run *)

(** Why one département's download failed, as far as {!failure_of_cause} needs
    to know. *)
type cause =
  | Network  (** no answer: offline, DNS, connection lost *)
  | Timeout
  | Status of int  (** an HTTP status outside 200–299 *)
  | Not_json  (** a body that is no JSON at all *)
  | Bad_payload  (** JSON, but not the expected answer *)
  | Refused  (** the client did not send it *)
  | Local  (** offline before sending, busy, or the file or row not written *)

val failure_of_cause : cause -> failure
(** - [Network], [Timeout], a {!Geocode.transient_status} (429, 5xx) and
      [Not_json] (the Géoplateforme sometimes answers 200 with a page that is
      not the WFS answer; asked again it succeeds, architecture §8) →
      [Transient];
    - [Status] 401 or 403 (the service refuses this client: every département
      would fail the same way), [Refused] and [Local] → [Stop];
    - another [Status] and [Bad_payload] → [Skip]. *)

val backoff_ms : int list
(** [[5_000; 20_000; 60_000]]: the wait before each retry of a [Transient]
    failure; after the last one, the run stops with that failure. *)

type 'e progress = {
  plan : plan;
  downloaded : int;  (** départements downloaded by this run *)
  bytes : int;  (** sum of the stored sizes the downloads returned *)
  failed : (Communes.departement * 'e) list;  (** skipped, in order *)
}

val position : 'e progress -> int
(** [plan.present + downloaded]: the [n] of « n / total », the départements
    present (a skipped one is not counted). *)

type 'e step =
  | Downloading of 'e progress * Communes.departement
      (** reported before each request of that département, retries included *)
  | Retrying of {
      progress : 'e progress;
      departement : Communes.departement;
      attempt : int;  (** 1-based: the retry about to wait *)
      attempts : int;  (** [List.length backoff_ms] *)
      wait_ms : int;
      error : 'e;
    }  (** reported before the wait *)

type 'e outcome =
  | Complete of 'e progress
      (** every [todo] tried; [failed] may be non-empty *)
  | Cancelled of 'e progress
  | Stopped of 'e progress * 'e
      (** a [Stop] failure, or a [Transient] one after every retry; the
          département it happened on is in neither [downloaded] nor [failed] *)

(** The IO and the caller's operations, over the caller's context [ctx]. *)
module type ENV = sig
  type 'a io

  val return : 'a -> 'a io
  val bind : 'a io -> ('a -> 'b io) -> 'b io

  type ctx
  type error

  val download : ctx -> Communes.departement -> (int, error) result io
  (** One département through the per-département path; [Ok] the stored size in
      bytes. *)

  val classify : error -> failure

  val sleep : ctx -> ms:int -> unit io
  (** May end early when a cancel is asked. *)

  val cancelled : ctx -> bool
  val report : ctx -> error step -> unit
end

module Make (E : ENV) : sig
  val run : E.ctx -> plan -> E.error outcome E.io
  (** For each département of [plan.todo], in order:
      + [cancelled] → [Cancelled] (nothing more sent);
      + [report (Downloading (progress, d))], then [download d];
      + [Ok size] → [downloaded + 1], [bytes + size]; next département (a cancel
        asked during the download takes effect at the next check: the finished
        département is kept and counted, so a cancel during the last one ends
        [Complete]);
      + [Error e], [classify e = Skip] → [(d, e)] appended to [failed]; next;
      + [Stop] → [Stopped (progress, e)] at once, no sleep;
      + [Transient] with a wait left in {!backoff_ms} (the [k]-th retry of a
        département waits its [k]-th entry; every département starts with all of
        them) → [report (Retrying …)], [sleep ~ms:wait], then [cancelled] →
        [Cancelled] (d neither downloaded nor failed), else the same département
        again (step 2); no wait left → [Stopped].

      After the last département → [Complete]. An empty [todo] → [Complete] with
      no report, no download, no sleep. [download] is never called while another
      is running, and never for a code outside [plan.todo]. No exception is
      caught: [E]'s functions must not raise. *)
end
