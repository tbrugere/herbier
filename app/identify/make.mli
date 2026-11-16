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
      - a non-2xx: ["identify: POST <flora> <n> photo(s) → <status>"];
      - transport failure: ["… → timeout"] or ["… → network failure"];
      - not sent: ["identify: POST <flora> <n> photo(s) not sent: no key"]
        (resp. [": no photo"], [<n> = 0]), with [<flora>]
        {!Plantnet.asked_flora}. *)

  val projects :
    key:string -> (Plantnet.project list, Plantnet.error) result logged T.io
  (** {!Plantnet.projects_request}: its [Error] (blank key → [No_key]) → that
      error, nothing sent. Else one [T.get ~url]: 2xx →
      {!Plantnet.decode_projects}; non-2xx →
      [Plantnet.error_of_answer ~route:Projects]; failure → as above. [line]:
      ["identify: GET projects → <status>"]
      (["→ <status>, malformed answer: <what>"], ["→ timeout"],
      ["→ network failure"], ["not sent: no key"]). *)
end
