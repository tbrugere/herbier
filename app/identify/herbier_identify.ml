module Transport = Transport
module Organ = Organ
module Plantnet = Plantnet
module Proposal = Proposal

module type TRANSPORT = Transport.TRANSPORT

type 'a logged = 'a Make.logged = {result : 'a; line : string}
type identified = Make.identified = {answer : Plantnet.answer; uncertain : bool}

let equal_identified = Make.equal_identified

module Make = Make.Make
