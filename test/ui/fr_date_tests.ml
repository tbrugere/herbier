module Fr_date = Herbier_ui_model.Fr_date

let utc = Fixtures.utc

let fr_date =
  let str = Alcotest.string in
  [
    Alcotest.test_case "day header" `Quick (fun () ->
        let header = Fr_date.day_header ~this_year:2026 in
        Alcotest.check str "fri" "Ven. 12 juin" (header (2026, 6, 12));
        Alcotest.check str "accent" "Sam. 15 août" (header (2026, 8, 15));
        Alcotest.check str "another year" "Lun. 1 mars 2027"
          (header (2027, 3, 1));
        Alcotest.check str "no such date: no weekday" "30 février"
          (header (2026, 2, 30));
        Alcotest.check str "long, this year too" "Ven. 12 juin 2026"
          (Fr_date.long_day (2026, 6, 12));
        Alcotest.check str "day and time, local" "Sam. 13 juin 2026 · 00:30"
          (Fr_date.day_time ~tz_offset_s:7200 (utc 2026 6 12 22 30)));
    Alcotest.test_case "year at the New Year" `Quick (fun () ->
        let t = utc 2026 12 31 23 30 in
        Alcotest.(check int) "utc" 2026 (Fr_date.year ~tz_offset_s:0 t);
        Alcotest.(check int) "paris" 2027 (Fr_date.year ~tz_offset_s:3600 t));
    Alcotest.test_case "local date, negative offset" `Quick (fun () ->
        Alcotest.(check (triple int int int))
          "new york" (2026, 6, 11)
          (Fr_date.local_date ~tz_offset_s:(-14400) (utc 2026 6 12 2 0)));
    Alcotest.test_case "day month and full date" `Quick (fun () ->
        Alcotest.(check string)
          "1 mars" "1 mars"
          (Fr_date.day_month (2027, 3, 1));
        Alcotest.(check string)
          "full" "12 juin 2026"
          (Fr_date.full_date (2026, 6, 12)));
    Alcotest.test_case "local date crosses midnight" `Quick (fun () ->
        let t = utc 2026 6 11 22 30 in
        Alcotest.(check (triple int int int))
          "utc" (2026, 6, 11)
          (Fr_date.local_date ~tz_offset_s:0 t);
        Alcotest.(check (triple int int int))
          "paris summer" (2026, 6, 12)
          (Fr_date.local_date ~tz_offset_s:7200 t));
    Alcotest.test_case "time" `Quick (fun () ->
        Alcotest.check str "padded" "09:05"
          (Fr_date.time ~tz_offset_s:3600 (utc 2026 1 3 8 5)));
  ]

(* Fr_date.ago: whole days between the instant and [now] (floor). *)

let ago_now = utc 2026 11 12 0 0

let ago =
  let case what expected instant =
    Alcotest.test_case what `Quick (fun () ->
        Alcotest.(check string) what expected (Fr_date.ago ~now:ago_now instant))
  in
  [
    case "0 s: aujourd'hui" "aujourd'hui" ago_now;
    case "23 h: aujourd'hui" "aujourd'hui" (utc 2026 11 11 1 0);
    case "1 day" "il y a 1 j" (utc 2026 11 11 0 0);
    case "13 days: still in days" "il y a 13 j" (utc 2026 10 30 0 0);
    case "14 days: weeks start" "il y a 2 sem." (utc 2026 10 29 0 0);
    case "59 days: still weeks" "il y a 8 sem." (utc 2026 9 14 0 0);
    case "60 days: months start" "il y a 2 mois" (utc 2026 9 13 0 0);
    case "364 days: still months" "il y a 12 mois" (utc 2025 11 13 0 0);
    case "365 days: years start, singular" "il y a 1 an" (utc 2025 11 12 0 0);
    case "800 days: plural ans" "il y a 2 ans" (utc 2024 9 3 0 0);
    case "an instant after now" "aujourd'hui" (utc 2026 11 12 1 0);
    case "days after now" "aujourd'hui" (utc 2026 11 15 0 0);
  ]
