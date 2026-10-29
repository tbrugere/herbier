module type S = sig
  type t

  val fresh : unit -> t
  val of_string : string -> t option
  val to_string : t -> string
  val equal : t -> t -> bool
  val compare : t -> t -> int
  val pp : Format.formatter -> t -> unit
end

(* The canonical lowercase spelling is stored: it is what the store and the
   REST API exchange, so [to_string] is free, and string order is the
   order of the UUID bytes. *)
module Uuid : S = struct
  type t = string

  (* Milliseconds since the POSIX epoch, without going through floats. *)
  let now_ms () =
    let d, ps = Ptime.Span.to_d_ps (Ptime.to_span (Ptime_clock.now ())) in
    Int64.(add (mul (of_int d) 86_400_000L) (div ps 1_000_000_000L))

  (* Seeded on first use only, so loading the module has no effect. The
     monotonic generator counts within a millisecond and gives up after 4096
     ids in the same one; the fallback keeps the timestamp and draws the
     counter bits at random instead. *)
  let generators =
    lazy
      (let state = Random.State.make_self_init () in
       ( Uuidm.v7_monotonic_gen ~now_ms state,
         Uuidm.v7_non_monotonic_gen ~now_ms state ))

  let fresh () =
    let monotonic, non_monotonic = Lazy.force generators in
    match monotonic () with
    | Some u -> Uuidm.to_string u
    | None -> Uuidm.to_string (non_monotonic ())

  (* Uuidm.of_string accepts trailing characters, hence the length check. *)
  let of_string s =
    match String.length s with
    | 36 -> Option.map Uuidm.to_string (Uuidm.of_string s)
    | _ -> None

  let to_string t = t
  let equal = String.equal
  let compare = String.compare
  let pp = Format.pp_print_string
end

module Plant_id : S = Uuid
module Observation_id : S = Uuid
module Photo_id : S = Uuid
module Tag_id : S = Uuid
module Plant_tag_id : S = Uuid
module Plant_ref_id : S = Uuid
module Reference_id : S = Uuid
