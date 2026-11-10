let url = Jv.get Jv.global "URL"

let create blob =
  Jv.to_jstr (Jv.call url "createObjectURL" [|Brr.Blob.to_jv blob|])

let revoke u = ignore (Jv.call url "revokeObjectURL" [|Jv.of_jstr u|])
