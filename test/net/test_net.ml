(* Herbier_net against the helpers it replaced, copied below verbatim from
   refs/decode.ml, refs/request.ml, geo/geocode.ml, geo/features.ml,
   photos/exif.ml, sync_core/auth/nonce.ml, sync_core/auth/gotrue.ml and
   refs/organ_photos.ml: the same answer on every input here, error messages included. *)

module Hex = Herbier_net.Hex
module Json = Herbier_net.Json
module Url = Herbier_net.Url

module Old = struct
  (* refs/decode.ml and geo/geocode.ml, without the Not_json wrapper both
     put around the message. *)
  let json_of_string s =
    match Yojson.Safe.from_string s with
    | json -> Ok json
    | exception Yojson.Json_error msg -> Error msg
    | exception e -> Error (Printexc.to_string e)

  (* refs/decode.ml and geo/geocode.ml. *)
  let member name = function
    | `Assoc fields -> (
        match List.assoc_opt name fields with
        | None | Some `Null -> None
        | Some v -> Some v)
    | _ -> None

  (* refs/decode.ml. *)
  let is_digits s =
    s <> "" && String.for_all (function '0' .. '9' -> true | _ -> false) s

  (* refs/request.ml and geo/geocode.ml. *)
  let unreserved = function
    | 'A' .. 'Z' | 'a' .. 'z' | '0' .. '9' | '-' | '.' | '_' | '~' -> true
    | _ -> false

  let encode s =
    let buf = Buffer.create (String.length s * 3) in
    String.iter
      (fun c ->
        match unreserved c with
        | true -> Buffer.add_char buf c
        | false -> Buffer.add_string buf (Printf.sprintf "%%%02X" (Char.code c)))
      s;
    Buffer.contents buf

  (* geo/geocode.ml and geo/features.ml. *)
  let number = function
    | `Int i -> Some (Float.of_int i)
    | `Float f when Float.is_finite f -> Some f
    | _ -> None

  (* photos/exif.ml: its member keeps null. *)
  module Exif = struct
    let member name = function
      | `Assoc fields -> List.assoc_opt name fields
      | _ -> None

    let string_member name json =
      match member name json with Some (`String s) -> Some s | _ -> None

    let number_member name json =
      match member name json with
      | Some (`Float f) when Float.is_finite f -> Some f
      | Some (`Int i) -> Some (Float.of_int i)
      | _ -> None

    let digits s =
      match
        s <> "" && String.for_all (function '0' .. '9' -> true | _ -> false) s
      with
      | true -> int_of_string_opt s
      | false -> None
  end

  (* sync_core/auth/nonce.ml. *)
  let digits = "0123456789abcdef"

  let hex bytes =
    String.init
      (2 * String.length bytes)
      (fun i ->
        let b = Char.code bytes.[i / 2] in
        digits.[match i mod 2 with 0 -> b lsr 4 | _ -> b land 15])

  (* refs/organ_photos.ml's downloadable. *)
  let prefix = "https://bs.plantnet.org/"

  let safe_char = function
    | '\x00' .. ' ' | '\x7f' | '"' | '<' | '>' | '\\' -> false
    | _ -> true

  let downloadable url =
    String.starts_with ~prefix url
    && String.length url > String.length prefix
    && String.for_all safe_char url

  (* sync_core/auth/gotrue.ml. *)
  let rec strip_slashes s =
    match String.ends_with ~suffix:"/" s with
    | true -> strip_slashes (String.sub s 0 (String.length s - 1))
    | false -> s
end

(* compare, not Yojson.Safe.equal, so that a nan field equals itself. *)
let yojson =
  Alcotest.testable
    (fun f j -> Format.pp_print_string f (Yojson.Safe.show j))
    (fun a b -> Int.equal (compare a b) 0)

(* Float.equal and the same sign: -0. differs from 0., nan equals nan. *)
let float_opt =
  Alcotest.option
    (Alcotest.testable Format.pp_print_float (fun a b ->
         Float.equal a b && Bool.equal (Float.sign_bit a) (Float.sign_bit b)))

let texts =
  [
    {|{"a":1}|};
    {|[1, 2.5, "x", null, true]|};
    "";
    "   ";
    "{";
    {|{"a":}|};
    {|{"a":1} trailing|};
    "nul";
    "\"unterminated";
    {|{"big":12345678901234567890}|};
    "1e400";
  ]

let parse () =
  List.iter
    (fun text ->
      Alcotest.(check (result yojson string))
        (Printf.sprintf "parse %S" text)
        (Old.json_of_string text) (Json.parse text))
    texts

let values : Yojson.Safe.t list =
  [
    `Assoc [("a", `Int 1); ("n", `Null); ("s", `String "x"); ("f", `Float 2.5)];
    `Assoc [("a", `Float Float.nan); ("s", `Null)];
    `Assoc [("a", `Float Float.infinity); ("f", `Intlit "123")];
    `Assoc [("a", `String "1")];
    `Assoc [];
    `List [`Assoc [("a", `Int 1)]];
    `Null;
    `String "a";
  ]

let names = ["a"; "n"; "s"; "f"; "absent"]

let each_field f =
  List.iter (fun json -> List.iter (fun name -> f name json) names) values

let member () =
  each_field (fun name json ->
      Alcotest.(check (option yojson))
        (Printf.sprintf "member %S %s" name (Yojson.Safe.show json))
        (Old.member name json) (Json.member name json))

let exif_members () =
  each_field (fun name json ->
      let shown = Printf.sprintf "%S %s" name (Yojson.Safe.show json) in
      Alcotest.(check (option string))
        ("string_member " ^ shown)
        (Old.Exif.string_member name json)
        (Json.string_member name json);
      Alcotest.check float_opt ("number_member " ^ shown)
        (Old.Exif.number_member name json)
        (Option.bind (Json.member name json) Json.number))

let number () =
  List.iter
    (fun (v : Yojson.Safe.t) ->
      Alcotest.check float_opt
        ("number " ^ Yojson.Safe.show v)
        (Old.number v) (Json.number v))
    [
      `Int 0;
      `Int (-7);
      `Float 2.5;
      `Float (-0.);
      `Float Float.nan;
      `Float Float.infinity;
      `Float Float.neg_infinity;
      `String "1";
      `Null;
      `Intlit "99999999999999999999";
      `Bool true;
    ]

let digits () =
  List.iter
    (fun s ->
      Alcotest.(check bool)
        (Printf.sprintf "is_digits %S" s)
        (Old.is_digits s) (Json.is_digits s);
      Alcotest.(check (option int))
        (Printf.sprintf "exif digits %S" s)
        (Old.Exif.digits s)
        (match Json.is_digits s with
        | true -> int_of_string_opt s
        | false -> None))
    [
      "";
      "0";
      "007";
      "123";
      "12a";
      " 1";
      "1 ";
      "-1";
      "+1";
      "1_000";
      "0x1f";
      "\xd9\xa1";
      "99999999999999999999999";
    ]

let encode () =
  List.iter
    (fun code ->
      let s = String.make 1 (Char.chr code) in
      Alcotest.(check string)
        (Printf.sprintf "encode byte %d" code)
        (Old.encode s) (Url.encode s))
    (List.init 256 Fun.id);
  List.iter
    (fun s ->
      Alcotest.(check string)
        (Printf.sprintf "encode %S" s)
        (Old.encode s) (Url.encode s))
    [""; "Digitalis purpurea"; "a/b?c=d&e"; "é ç"; "~-._"; "100%"]

let strip () =
  List.iter
    (fun s ->
      Alcotest.(check string)
        (Printf.sprintf "strip %S" s)
        (Old.strip_slashes s)
        (Url.strip_trailing_slashes s))
    [
      "";
      "/";
      "//";
      "a";
      "a/";
      "a//";
      "https://x.test";
      "https://x.test///";
      "/a/b/";
    ]

let under () =
  List.iter
    (fun (url, expected) ->
      Alcotest.(check bool)
        (Printf.sprintf "under %S (as downloadable)" url)
        (Old.downloadable url)
        (Url.under ~prefix:Old.prefix url);
      Alcotest.(check bool)
        (Printf.sprintf "under %S" url)
        expected
        (Url.under ~prefix:Old.prefix url))
    [
      ("https://bs.plantnet.org/image/s/abc", true);
      ("https://bs.plantnet.org/\xc3\xa9", true);
      ("https://bs.plantnet.org/", false);
      ("", false);
      ("http://bs.plantnet.org/a", false);
      ("https://bs.plantnet.org.evil.com/a", false);
      ("https://x@bs.plantnet.org/a", false);
      ("https://bs.plantnet.org:443/a", false);
      ("https://bs.plantnet.org/a b", false);
      ("https://bs.plantnet.org/a\tb", false);
      ("https://bs.plantnet.org/a\nb", false);
      ("https://bs.plantnet.org/a\x00b", false);
      ("https://bs.plantnet.org/a\x7fb", false);
      ("https://bs.plantnet.org/a\"b", false);
      ("https://bs.plantnet.org/a<b", false);
      ("https://bs.plantnet.org/a>b", false);
      ("https://bs.plantnet.org/a\\b", false);
    ]

let hex () =
  List.iter
    (fun bytes ->
      Alcotest.(check string)
        (Printf.sprintf "encode %S" bytes)
        (Old.hex bytes) (Hex.encode bytes))
    [
      "";
      "\x00\x0f\xffA";
      String.init 32 Char.chr;
      String.init 32 (fun i -> Char.chr (224 + i));
      String.init 256 Char.chr;
    ];
  Alcotest.(check string) "lowercase" "000fff41" (Hex.encode "\x00\x0f\xffA")

let () =
  Alcotest.run "net"
    [
      ( "Json",
        [
          ("parse: same value or message as the decoders' copies", `Quick, parse);
          ("member: null and absent are None, as refs and geo", `Quick, member);
          ( "string_member and number: exif's string and number fields",
            `Quick,
            exif_members );
          ("number: Int or finite Float", `Quick, number);
          ("is_digits: refs' rule, and exif's digits over it", `Quick, digits);
        ] );
      ( "Url",
        [
          ("encode: every byte as refs and geo encoded it", `Quick, encode);
          ("strip_trailing_slashes: gotrue's strip_slashes", `Quick, strip);
          ( "under: organ_photos' downloadable, every refused character",
            `Quick,
            under );
        ] );
      ("Hex", [("encode: the nonce's lowercase hex", `Quick, hex)]);
    ]
