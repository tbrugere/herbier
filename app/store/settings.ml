module Col = Postgrest.Col
module Original_target = Herbier_domain.Photo.Original_target

type _ key =
  | Storage_target : Original_target.t key
  | Wifi_only : bool key
  | Place_source_ign_offline : bool key
  | Place_source_ign_online : bool key
  | Place_source_photon_online : bool key
  | Location_notice_seen : bool key

let name : type a. a key -> string = function
  | Storage_target -> "storage_target"
  | Wifi_only -> "wifi_only"
  | Place_source_ign_offline -> "place_source_ign_offline"
  | Place_source_ign_online -> "place_source_ign_online"
  | Place_source_photon_online -> "place_source_photon_online"
  | Location_notice_seen -> "location_notice_seen"

(* A local-only table: its columns live next to its queries (layout §2), not
   in Tables. *)
type settings

let key_column : (settings, string, [`Mandatory]) Col.t =
  {ty = Not_Null Str; name = "key"}

let bool_text : bool Col.custom =
  Codec.text ~name:"bool" ~to_string:string_of_bool ~of_string:(function
    | "true" -> Some true
    | "false" -> Some false
    | _ -> None)

let codec : type a. a key -> a Col.custom = function
  | Storage_target -> Tables.photo_original_target
  | Wifi_only -> bool_text
  | Place_source_ign_offline -> bool_text
  | Place_source_ign_online -> bool_text
  | Place_source_photon_online -> bool_text
  | Location_notice_seen -> bool_text

let value_column key : (settings, _, [`Mandatory]) Col.t =
  {ty = Not_Null (Custom (codec key)); name = "value"}

let get key =
  Stmt.query ~json:[]
    (Postgrest.Row.col (value_column key))
    "select value from settings where key = ?"
    [Codec.param key_column (name key)]

let set key v =
  {
    Stmt.sql =
      "insert into settings (key, value) values (?, ?) on conflict (key) do \
       update set value = excluded.value";
    params =
      [Codec.param key_column (name key); Codec.param (value_column key) v];
  }
