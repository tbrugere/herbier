(** 4m's « Serveur en pause » (architecture §4: a 540 is shown in Settings with
    a link to the dashboard). Pure. *)

val paused : Herbier_sync_core.Cycle.Report.t option -> bool
(** The engine's last cycle stopped on a paused project ([Report.stop] is
    [Some Paused]). [None] (no cycle yet), a completed cycle or another stop →
    [false]. *)

val paused_title : string
(** « Serveur en pause » *)

val paused_detail : string
(** « Les modifications attendent sur le téléphone ; elles partiront quand le
    serveur sera réactivé. » *)

val dashboard_url : supabase_url:string -> string option
(** [https://<ref>.supabase.co] (an optional trailing ['/'], [<ref>] non-empty,
    lowercase ASCII letters and digits only) →
    [Some "https://supabase.com/dashboard/project/<ref>"]; anything else (the
    local stack, [""], another host, a path, [http]) → [None]. *)

val dashboard_label : string
(** « Ouvrir le tableau de bord ↗ » *)
