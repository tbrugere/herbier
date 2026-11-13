(** What the keep-alive job (web/runner/keepalive.js) reports: its session, its
    queue and its last runs, as its [report] event answers them. Pure: no Brr,
    Fut, Jv or bindings (test/sync copies it). *)

type ping = Ping_status of int | Ping_failed of string | Ping_not_run

type session_outcome =
  | No_session  (** nothing handed, or dropped after a revoke *)
  | Fresh  (** the access token was still valid *)
  | Refreshed
  | Revoked of int  (** GoTrue 4xx with a code: the job dropped its session *)
  | Refresh_failed of string
      (** network, 408, 429, 5xx, uncoded 4xx, malformed 2xx: kept *)
  | Replaced
      (** the app set or took the session while the job refreshed it: the
          refreshed one was logged out, the app's kept *)

type trigger = Job | Dispatch

val trigger_to_string : trigger -> string
(** ["job"] / ["dispatch"], as the job writes it. *)

type queue =
  | Not_run  (** the run stopped before the queue (no usable session) *)
  | Skipped_app_active  (** the app was active at the start *)
  | Pushed of {count : int; stop : string option}
      (** [count]: 2xx answers, in order; [stop]: why it stopped before the end
          (["HTTP 409"], ["network: …"], ["taken back"] when the queue in the KV
          changed meanwhile (a reclaim, hand-off, set or take of the app),
          ["app active"] when the app came back meanwhile, ["foreign url"] for a
          request outside the backend's [/rest/v1/]), [None] when it ran to the
          end (the job then forgets the queue) or there was none *)

type run = {
  at : Ptime.t;  (** the job's clock when the run started *)
  trigger : trigger;
  app_active : bool;  (** [CapacitorApp.getState().isActive] at the start *)
  session : session_outcome;
  queue : queue;
  error : string option;
      (** why the run could not go on: an unreadable [session] or [backend] in
          the KV, or an exception the job caught *)
  ping : ping;
}

type t = {
  session_expires_at : Ptime.t option;
      (** of the job's session; [None]: it holds none *)
  queued : int;
  runs : run list;  (** newest first, at most 20 (the job keeps 20) *)
}

val decode : string -> (t, string) result
(** [report]'s answer (the JSON text the job resolves with):
    [{"v":1,"session_expires_at":<int s|null>,"queued":n,"runs":[…]}], each run
    [{"at":<ms>,"trigger":"job"|"dispatch","app_active":bool,
     "session":"none"|"fresh"|"refreshed"|"revoked"|"refresh_failed"|"replaced",
     "revoked_status":<int, for "revoked">,"refresh_error":<string, for
     "refresh_failed">,"queue":null|"skipped"|{"pushed":n,"stop":<string|null>},
     "error":<string|null>,"ping":<int status|string why|null>}]. Unknown fields
    ignored. Errors: {!Json_read}'s, ["bad or missing <field>"],
    ["runs is not an array"], ["unknown session outcome"], and a run that does
    not decode as ["run <index>: <why>"]. Never raises. *)

val run_to_string : run -> string
(** One line for #dev/keepalive and the console, no token, as the job prints it:
    ["2026-11-12T10:00:00Z job refreshed pushed 3 ping 200"]. *)
