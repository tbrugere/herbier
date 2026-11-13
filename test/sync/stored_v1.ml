(* Session values as the app writes them to Preferences (format v1), shared by
   test_sync.ml and jsoo/smoke.ml: the encoder must keep these bytes, and
   values already stored must still be read. *)

let with_email =
  {|{"v":1,"access_token":"AT-token","refresh_token":"RT-token","expires_at":1800000000,"user_id":"user-1","email":"person@example.com"}|}

let without_email =
  {|{"v":1,"access_token":"AT-token","refresh_token":"RT-token","expires_at":1800000000,"user_id":"user-1","email":null}|}

(* 2100-01-01T00:00:00Z: past 2038, past a 32-bit int. *)
let in_2100 =
  {|{"v":1,"access_token":"AT-token","refresh_token":"RT-token","expires_at":4102444800,"user_id":"user-1","email":"person@example.com"}|}
