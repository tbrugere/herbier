(** Dev-only page [#dev/keepalive]: the keep-alive job's report
    ({!Herbier_sync.Keepalive.report}: session present and its expiry, queued
    requests, the last runs one per line with
    {!Herbier_sync.Keepalive.Report.run_to_string}) and the build's label and
    interval. A failure prints {!Herbier_sync.Keepalive.error_to_string}, which
    names the event. Buttons: « Actualiser »; « Session du job » (the pasted
    output of scripts/local-session.sh, decoded with
    {!Herbier_sync.Auth.Gotrue.decode_session}, then [Keepalive.set_session]: an
    emulator has no Google account, and the job needs a session of its own,
    distinct from the one #dev/sync imports); « Oublier la session »
    ([drop_session]); « Confier la file » ([hand_off]); « Reprendre la file »
    ([reclaim]); « Lancer maintenant » ([run_now]). Prints [done] once first
    drawn. Never prints a token. *)

val el : (App.t, string) result -> Brr.El.t
