(* A Herbier_identify.TRANSPORT with ['a io = 'a]: answers every request from
   [A.respond] and keeps every call made, in order. *)

module Transport = Herbier_identify.Transport
module Fixture = Herbier_test_support.Fixture

type call =
  | Post of {
      url : string;
      fields : (string * string) list;
      files : string Transport.file list;
    }
  | Get of {url : string}

module type ANSWERS = sig
  val respond : call -> (Transport.answer, Transport.failure) result
end

module Make (A : ANSWERS) : sig
  include
    Herbier_identify.TRANSPORT with type 'a io = 'a and type image = string

  val calls : unit -> call list
  (** Every call made so far, in order. *)
end = struct
  type 'a io = 'a

  let return x = x
  let bind x f = f x

  type image = string

  let calls_rev : call list ref = ref []
  let calls () = List.rev !calls_rev

  let post_form ~url ~fields ~files =
    let call = Post {url; fields; files} in
    calls_rev := call :: !calls_rev;
    A.respond call

  let get ~url =
    let call = Get {url} in
    calls_rev := call :: !calls_rev;
    A.respond call
end

(* ---------- helpers for [A.respond] ---------- *)

let fixture name : (Transport.answer, Transport.failure) result =
  Ok
    {
      Transport.status = int_of_string (Test_fixtures.status_of name);
      body = Fixture.read name;
    }

let status n : (Transport.answer, Transport.failure) result =
  Ok {Transport.status = n; body = ""}

(* An [ANSWERS.respond] that only accepts [url], answering every call made to
   it with [answer]; any other URL fails the test, so a test that installs
   this pins the exact URL [Make] sent. *)
let expect_url url answer call =
  let got = match call with Post {url; _} -> url | Get {url} -> url in
  match String.equal got url with
  | true -> answer
  | false ->
      Alcotest.failf "fake_transport: unexpected URL %s (expected %s)" got url
