module Col = Postgrest.Col
module Original_target = Herbier_domain.Photo.Original_target

type _ key =
  | Storage_target : Original_target.t key
  | Wifi_only : bool key
  | Place_source_ign_offline : bool key
  | Place_source_ign_online : bool key
  | Place_source_photon_online : bool key
  | Location_notice_seen : bool key
  | Drive_health_checked_at : Ptime.t key
  | Last_upload_at : Ptime.t key
  | Drive_health_cursor : Herbier_domain.Ids.Photo_id.t key
  | Drive_root_folder : string key

let name : type a. a key -> string = function
  | Storage_target -> "storage_target"
  | Wifi_only -> "wifi_only"
  | Place_source_ign_offline -> "place_source_ign_offline"
  | Place_source_ign_online -> "place_source_ign_online"
  | Place_source_photon_online -> "place_source_photon_online"
  | Location_notice_seen -> "location_notice_seen"
  | Drive_health_checked_at -> "drive_health_checked_at"
  | Last_upload_at -> "last_upload_at"
  | Drive_health_cursor -> "drive_health_cursor"
  | Drive_root_folder -> "drive_root_folder"

(* A local-only table: its columns live next to its queries (layout §2), not
   in Tables. *)
type settings

let table : settings Col.table = Col.table "settings"

let key_column : (settings, string, [`Mandatory]) Col.t =
  {ty = Not_Null Str; name = "key"}

let bool_text : bool Col.custom =
  Codec.text ~name:"bool" ~to_string:string_of_bool ~of_string:(function
    | "true" -> Some true
    | "false" -> Some false
    | _ -> None)

let timestamp_text : Ptime.t Col.custom =
  Codec.text ~name:"timestamp" ~to_string:Codec.timestamp ~of_string:(fun s ->
      match Ptime.of_rfc3339 s with
      | Ok (t, (_ : int option), (_ : int)) -> Some t
      | Error _ -> None)

let photo_id_text : Herbier_domain.Ids.Photo_id.t Col.custom =
  Codec.text ~name:"photo_id" ~to_string:Herbier_domain.Ids.Photo_id.to_string
    ~of_string:Herbier_domain.Ids.Photo_id.of_string

let drive_id_text : string Col.custom =
  Codec.text ~name:"drive_id" ~to_string:Fun.id
    ~of_string:Herbier_domain.Text.non_blank

let codec : type a. a key -> a Col.custom = function
  | Storage_target -> Tables.photo_original_target
  | Wifi_only -> bool_text
  | Place_source_ign_offline -> bool_text
  | Place_source_ign_online -> bool_text
  | Place_source_photon_online -> bool_text
  | Location_notice_seen -> bool_text
  | Drive_health_checked_at -> timestamp_text
  | Last_upload_at -> timestamp_text
  | Drive_health_cursor -> photo_id_text
  | Drive_root_folder -> drive_id_text

let value_column key : (settings, _, [`Mandatory]) Col.t =
  {ty = Not_Null (Custom (codec key)); name = "value"}

let get key =
  Stmt.query ~json:[]
    (Postgrest.Row.col (value_column key))
    "select value from settings where key = ?"
    [Codec.param key_column (name key)]

let set key v =
  Stmt.upsert ~conflict:[key_column.name] ~table
    Postgrest.Input.
      {
        fields =
          [
            Mandatory (key_column, Value (name key));
            Mandatory (value_column key, Value v);
          ];
      }

let unset key =
  {
    Stmt.sql = "delete from settings where key = ?";
    params = [Codec.param key_column (name key)];
  }
