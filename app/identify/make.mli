(** The identification, over any {!Transport.TRANSPORT}: builds the request,
    sends it, decodes the answer, classifies the errors, applies the uncertain
    rule, and gives the console line. Never retries, never sends more than one
    request per call, never stores anything. *)

type 'a logged = {result : 'a; line : string}
(** A call's outcome and its console line. The line never holds the key, the
    URL, nor the transport's failure text. *)

type identified = {answer : Plantnet.answer; uncertain : bool}
(** [uncertain] = [Proposal.uncertain answer.proposals]. *)

val equal_identified : identified -> identified -> bool

val identify_not_sent : flora:string -> 'a list -> string -> string
(** [identify_not_sent ~flora photos reason] is an identify call's line when
    nothing is sent: ["identify: POST <flora> <n> photo(s) not sent: <reason>"],
    [<flora>] {!Plantnet.asked_flora}, [<n>] the photos given, at most
    {!Organ.max_photos}. Make's own refusals use it, and so does a caller with a
    gate of its own (the network, a preview it cannot read). *)

val projects_not_sent : string -> string
(** ["identify: GET projects not sent: <reason>"], likewise. *)

module Make (T : Transport.TRANSPORT) : sig
  val identify :
    key:string ->
    flora:string ->
    ?no_reject:bool ->
    (T.image * Organ.sent) list ->
    (identified, Plantnet.error) result logged T.io
  (** {!Plantnet.identify_request} ([no_reject] defaults to [false]); its
      [Error] → that error, no request ([T.post_form] not called). Else one
      [T.post_form ~url ~fields ~files]: [Ok {status = 200..299; body}] →
      {!Plantnet.decode_answer} then [uncertain]; [Ok] non-2xx →
      [Plantnet.error_of_answer ~route:Identify]; [Error f] →
      {!Plantnet.error_of_failure}.

      [line], with [<flora>] the request's flora and [<n>] the photos given, at
      most {!Organ.max_photos} (for a request that is sent, the ones sent):
      - sent and decoded:
        ["identify: POST <flora> <n> photo(s) → <status>, <remaining> left
         today"], without [", … left today"] when [remaining = None];
      - a 2xx that does not decode:
        ["identify: POST <flora> <n> photo(s) → <status>, malformed answer:
         <what>"];
      - a non-2xx: ["identify: POST <flora> <n> photo(s) → <status>, <class>"],
        [<class>] {!Plantnet.error_to_string} of its error (e.g.
        ["→ 403, key not exposed for the app"]): the console tells apart the
        causes the user sees as one generic error;
      - transport failure: ["… → timeout"] or ["… → network failure"];
      - not sent: {!identify_not_sent} with ["no key"] (resp. ["no photo"],
        [<n> = 0]). *)

  val projects :
    key:string -> (Plantnet.project list, Plantnet.error) result logged T.io
  (** {!Plantnet.projects_request}: its [Error] (blank key → [No_key]) → that
      error, nothing sent. Else one [T.get ~url]: 2xx →
      {!Plantnet.decode_projects}; non-2xx →
      [Plantnet.error_of_answer ~route:Projects]; failure → as above. [line]:
      ["identify: GET projects → <status>"] for a 2xx (["→ <status>, <class>"]
      for a non-2xx, ["→ <status>, malformed answer: <what>"], ["→ timeout"],
      ["→ network failure"]), not sent: {!projects_not_sent} ["no key"]. *)
end
