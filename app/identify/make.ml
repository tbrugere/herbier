type 'a logged = {result : 'a; line : string}
type identified = {answer : Plantnet.answer; uncertain : bool} [@@deriving eq]

let is_success status = status >= 200 && status <= 299

(* The line names the outcome by status or failure kind only: the URL holds
   the key, and the transport's text is not trusted to leave it out. *)
let outcome_of_failure : Transport.failure -> string = function
  | Timeout -> "timeout"
  | Network _ -> "network failure"

(* A 2xx that does not decode: its status and the reason, a fixed text
   (Malformed only). *)
let undecoded status e =
  Printf.sprintf "%d, %s" status (Plantnet.error_to_string e)

module Make (T : Transport.TRANSPORT) = struct
  module Syntax = struct
    let ( let+ ) io f = T.bind io (fun x -> T.return (f x))
  end

  let identify ~key ~flora ?(no_reject = false) photos =
    match Plantnet.identify_request ~key ~flora ~no_reject photos with
    | Error e ->
        T.return
          {
            result = Error e;
            line =
              Printf.sprintf "identify: POST %s %d photo(s) not sent: %s"
                (Plantnet.asked_flora flora)
                (min (List.length photos) Organ.max_photos)
                (Plantnet.error_to_string e);
          }
    | Ok (request : T.image Plantnet.request) -> (
        let open Syntax in
        let head =
          Printf.sprintf "identify: POST %s %d photo(s) → " request.flora
            (List.length request.files)
        in
        let+ reply =
          T.post_form ~url:request.url ~fields:request.fields
            ~files:request.files
        in
        match reply with
        | Error failure ->
            {
              result = Error (Plantnet.error_of_failure failure);
              line = head ^ outcome_of_failure failure;
            }
        | Ok {status; body} when is_success status -> (
            match Plantnet.decode_answer body with
            | Ok answer ->
                let left =
                  match answer.remaining with
                  | Some n -> Printf.sprintf ", %d left today" n
                  | None -> ""
                in
                {
                  result =
                    Ok {answer; uncertain = Proposal.uncertain answer.proposals};
                  line = Printf.sprintf "%s%d%s" head status left;
                }
            | Error e -> {result = Error e; line = head ^ undecoded status e})
        | Ok {status; body} ->
            {
              result =
                Error (Plantnet.error_of_answer ~route:Identify ~status ~body);
              line = head ^ Int.to_string status;
            })

  let projects ~key =
    let head = "identify: GET projects " in
    match Plantnet.projects_request ~key with
    | Error e ->
        T.return
          {
            result = Error e;
            line = head ^ "not sent: " ^ Plantnet.error_to_string e;
          }
    | Ok url -> (
        let open Syntax in
        let+ reply = T.get ~url in
        match reply with
        | Error failure ->
            {
              result = Error (Plantnet.error_of_failure failure);
              line = head ^ "→ " ^ outcome_of_failure failure;
            }
        | Ok {status; body} when is_success status -> (
            match Plantnet.decode_projects body with
            | Ok projects ->
                {
                  result = Ok projects;
                  line = head ^ "→ " ^ Int.to_string status;
                }
            | Error e ->
                {result = Error e; line = head ^ "→ " ^ undecoded status e})
        | Ok {status; body} ->
            {
              result =
                Error (Plantnet.error_of_answer ~route:Projects ~status ~body);
              line = head ^ "→ " ^ Int.to_string status;
            })
end
