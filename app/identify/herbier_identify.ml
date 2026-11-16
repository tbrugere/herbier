module Transport = Transport
module Organ = Organ
module Plantnet = Plantnet
module Proposal = Proposal

module type TRANSPORT = Transport.TRANSPORT

type 'a logged = 'a Make.logged = {result : 'a; line : string}
type identified = Make.identified = {answer : Plantnet.answer; uncertain : bool}

let equal_identified = Make.equal_identified
let identify_not_sent = Make.identify_not_sent
let projects_not_sent = Make.projects_not_sent

module Make = Make.Make
