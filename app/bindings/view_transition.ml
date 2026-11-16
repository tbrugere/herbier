type t = [`Finished | `Skipped] Fut.t

let document () = Brr.Document.to_jv Brr.G.document

let supported () =
  match Jv.find (document ()) "startViewTransition" with
  | Some f -> Jv.instanceof f ~cons:(Jv.get Jv.global "Function")
  | None -> false

let settled promise = Fut.of_promise ~ok:(fun _ -> ()) promise

(* The name of the rejection an update that raised hands the browser: already
   logged by [callback], so [start] does not warn about it again. *)
let update_raised = Jstr.v "UpdateRaised"

let callback update =
  Jv.callback ~arity:1 (fun _ ->
      match update () with
      | fut ->
          Fut.to_promise ~ok:(fun () -> Jv.undefined) (Fut.map Result.ok fut)
      | exception e ->
          let message = Printexc.to_string e in
          Brr.Console.(error [str "view transition: update"; str message]);
          Jv.Promise.reject
            (Jv.of_error (Jv.Error.v ~name:update_raised (Jstr.v message))))

(* A newer transition skips this one with an AbortError: an ordinary end. *)
let warn_unless_ordinary e =
  let name = Jv.Error.name e in
  match
    Jstr.equal name (Jstr.v "AbortError") || Jstr.equal name update_raised
  with
  | true -> ()
  | false ->
      Brr.Console.(
        warn [str "view transition skipped"; name; Jv.Error.message e])

(* A skipped transition rejects [ready] (and the others when the update
   failed): every promise gets a handler at once. *)
let start update =
  match supported () with
  | false -> None
  | true ->
      let jv =
        Jv.call (document ()) "startViewTransition" [|callback update|]
      in
      let ready = settled (Jv.get jv "ready")
      and over = settled (Jv.get jv "finished") in
      ignore (settled (Jv.get jv "updateCallbackDone"));
      let open Fut.Syntax in
      Some
        (let+ r = ready and+ _ = over in
         match r with
         | Ok () -> `Finished
         | Error e ->
             warn_unless_ordinary e;
             `Skipped)

let finished t = t
