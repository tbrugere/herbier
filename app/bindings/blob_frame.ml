let wrap ~prefix ~suffix blob =
  Brr.Blob.of_jv
    (Jv.new' (Jv.get Jv.global "Blob")
       [|
         Jv.of_array Fun.id
           [|Jv.of_string prefix; Brr.Blob.to_jv blob; Jv.of_string suffix|];
       |])
