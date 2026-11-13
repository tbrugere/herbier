let message e = Jstr.to_string (Jv.Error.message e)

let bytes_of a =
  let b = Brr.Tarray.to_bigarray1 a in
  String.init (Bigarray.Array1.dim b) (fun i ->
      Char.chr (Bigarray.Array1.get b i))

let random_bytes n =
  let a = Brr.Tarray.create Brr.Tarray.Uint8 n in
  match Brr_webcrypto.Crypto.(set_random_values crypto a) with
  | () -> Ok (bytes_of a)
  | exception Jv.Error e -> Error (message e)

let sha256 text =
  let subtle = Brr_webcrypto.Crypto.(subtle crypto) in
  let algo = Brr_webcrypto.Crypto_algo.(v sha_256) in
  match
    Brr_webcrypto.Subtle_crypto.digest subtle algo
      (Brr.Tarray.of_jstr (Jstr.v text))
  with
  | fut ->
      Fut.map
        (function
          | Ok digest ->
              Ok (bytes_of (Brr.Tarray.of_buffer Brr.Tarray.Uint8 digest))
          | Error e -> Error (message e))
        fut
  | exception Jv.Error e -> Fut.return (Error (message e))
