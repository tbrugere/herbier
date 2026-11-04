(** A photo of an observation: the device preview always exists; the original
    may live in Drive (architecture §5). *)

module Original_target : sig
  type t = App_only | Drive

  val all : t list
  (** Every constructor, in declaration order. *)

  val to_string : t -> string
  (** ["app_only"] | ["drive"]: the values of its Postgres lookup table. *)

  val of_string : string -> t option
  (** Exact inverse of [to_string]; [None] for any other string. *)

  val to_json : t -> Yojson.Safe.t
  (** The JSON string [to_string t]: the column value as PostgREST sends and
      receives it. *)

  val of_json : Yojson.Safe.t -> t option
  (** [of_string] of a JSON string; [None] for any other JSON value. *)
end

module Upload_state : sig
  type t = Pending | Uploaded | Failed | Original_missing

  val all : t list
  (** Every constructor, in declaration order. *)

  val to_string : t -> string
  (** ["pending"] | ["uploaded"] | ["failed"] | ["original_missing"]: the values
      of its Postgres lookup table. *)

  val of_string : string -> t option
  (** Exact inverse of [to_string]; [None] for any other string. *)

  val to_json : t -> Yojson.Safe.t
  (** The JSON string [to_string t]: the column value as PostgREST sends and
      receives it. *)

  val of_json : Yojson.Safe.t -> t option
  (** [of_string] of a JSON string; [None] for any other JSON value. *)
end

type id = Ids.Photo_id.t
(** The id of the photo: [Ids.Photo_id.t] under a local name. *)

type t = {
  id : id;
  observation_id : Ids.Observation_id.t;
  taken_at : Ptime.t;
  width : int;  (** Preview pixels. *)
  height : int;  (** Preview pixels. *)
  sha256 : string;
      (** Lowercase hex of the original file as captured, 64 chars, the value
          sent in the Drive [appProperties] (architecture §5); not validated
          here. *)
  preview_path : string;  (** Device path under [Directory.Data]. *)
  preview_bucket_key : string option;
      (** Supabase Storage key when mirrored. *)
  original_target : Original_target.t;
  drive_file_id : string option;
  upload_state : Upload_state.t;
  created_at : Ptime.t;
  updated_at : Ptime.t;
  deleted_at : Ptime.t option;  (** [Some] = soft-deleted. *)
}
