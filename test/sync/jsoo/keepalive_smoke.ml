(* Smoke run of Keepalive.Report.decode compiled by js_of_ocaml, under
   node, on the report test/runner's node test wrote: its oldest run's clock
   (Unix ms, past 2^31) must read back as 2026-11-12T09:50:00Z. Silent on
   success; prints the failure to stderr and exits 1. *)

module Report = Herbier_sync_core.Keepalive.Report

let fail m =
  prerr_endline ("keepalive jsoo smoke: " ^ m);
  exit 1

let () =
  let text = In_channel.with_open_bin Sys.argv.(1) In_channel.input_all in
  match Report.decode text with
  | Error e -> fail ("Report.decode: " ^ e)
  | Ok r -> (
      match List.rev r.runs with
      | [] -> fail "no run"
      | oldest :: _ -> (
          match Ptime.to_rfc3339 ~tz_offset_s:0 oldest.at with
          | "2026-11-12T09:50:00Z" -> ()
          | other -> fail ("oldest run at " ^ other)))
