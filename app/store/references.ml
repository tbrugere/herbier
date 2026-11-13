module Reference = Herbier_domain.Reference
module Plant_id = Herbier_domain.Ids.Plant_id
module Reference_id = Herbier_domain.Ids.Reference_id
module Plant_ref_id = Herbier_domain.Ids.Plant_ref_id
module R = Tables.Reference
module Pr = Tables.Plant_refs
module Row = Postgrest.Row

let row =
  let open Row.Syntax in
  let+ id = Row.col R.id
  and+ plant_id = Row.col R.plant_id
  and+ source = Row.col R.source
  and+ fetched_at = Row.col R.fetched_at
  and+ payload = Row.col R.payload
  and+ status = Row.col R.status
  and+ created_at = Row.col R.created_at
  and+ updated_at = Row.col R.updated_at
  and+ deleted_at = Row.col R.deleted_at in
  {
    Reference.id;
    plant_id;
    source;
    fetched_at;
    payload;
    status;
    created_at;
    updated_at;
    deleted_at;
  }

let json = [Codec.json R.payload]

let plant_ref_row =
  let open Row.Syntax in
  let+ id = Row.col Pr.id
  and+ plant_id = Row.col Pr.plant_id
  and+ source = Row.col Pr.source
  and+ external_id = Row.col Pr.external_id
  and+ url = Row.col Pr.url
  and+ created_at = Row.col Pr.created_at
  and+ updated_at = Row.col Pr.updated_at
  and+ deleted_at = Row.col Pr.deleted_at in
  {
    Reference.Plant_ref.id;
    plant_id;
    source;
    external_id;
    url;
    created_at;
    updated_at;
    deleted_at;
  }

let input (r : Reference.t) : (R.t, [`Full]) Postgrest.Input.t =
  Postgrest.Input.
    {
      fields =
        [
          Mandatory (R.id, Value r.id);
          Mandatory (R.plant_id, Value r.plant_id);
          Mandatory (R.source, Value r.source);
          Mandatory (R.fetched_at, Value r.fetched_at);
          Mandatory (R.payload, Value r.payload);
          Mandatory (R.status, Value r.status);
          Mandatory (R.created_at, Value r.created_at);
          Mandatory (R.updated_at, Value r.updated_at);
          Optional (R.deleted_at, Value r.deleted_at);
        ];
    }

let plant_ref_input (p : Reference.Plant_ref.t) :
    (Pr.t, [`Full]) Postgrest.Input.t =
  Postgrest.Input.
    {
      fields =
        [
          Mandatory (Pr.id, Value p.id);
          Mandatory (Pr.plant_id, Value p.plant_id);
          Mandatory (Pr.source, Value p.source);
          Mandatory (Pr.external_id, Value p.external_id);
          Mandatory (Pr.url, Value p.url);
          Mandatory (Pr.created_at, Value p.created_at);
          Mandatory (Pr.updated_at, Value p.updated_at);
          Optional (Pr.deleted_at, Value p.deleted_at);
        ];
    }

let query sql params = Stmt.query ~json row sql params

let of_plant plant =
  query
    "select * from reference where plant_id = ? and deleted_at is null order \
     by source"
    [Codec.param R.plant_id plant]

let live_by_key =
  "select * from reference where plant_id = ? and source = ? and deleted_at is \
   null"

let any_by_key = "select * from reference where plant_id = ? and source = ?"

let get plant source =
  query live_by_key [Codec.param R.plant_id plant; Codec.param R.source source]

(* Read back by the natural key, the unique constraint the write conflicts
   on; the id is derived from it (architecture §4), so both name one row. *)
let reference_edit ~plant ~source stmt =
  Outbox.edit ~table:R.table
    ~reread:
      (query any_by_key
         [Codec.param R.plant_id plant; Codec.param R.source source])
    ~row_id:(fun (r : Reference.t) -> Reference_id.to_string r.id)
    ~input stmt

let put ~plant ~source ~fetched_at ~payload ~status ~at =
  reference_edit ~plant ~source
    {
      Stmt.sql =
        "insert into reference (id, plant_id, source, fetched_at, payload, \
         status, created_at, updated_at, deleted_at) values (?, ?, ?, ?, ?, ?, \
         ?, ?, null) on conflict (plant_id, source) do update set fetched_at = \
         excluded.fetched_at, payload = excluded.payload, status = \
         excluded.status, updated_at = excluded.updated_at, deleted_at = null";
      params =
        [
          Codec.param R.id (Reference.id_of_key ~plant ~source);
          Codec.param R.plant_id plant;
          Codec.param R.source source;
          Codec.param R.fetched_at fetched_at;
          Codec.param R.payload payload;
          Codec.param R.status status;
          Codec.param R.created_at at;
          Codec.param R.updated_at at;
        ];
    }

let remove ~plant ~source ~at =
  reference_edit ~plant ~source
    {
      Stmt.sql =
        "update reference set deleted_at = ?, updated_at = ? where plant_id = \
         ? and source = ? and deleted_at is null";
      params =
        [
          Codec.param R.deleted_at (Some at);
          Codec.param R.updated_at at;
          Codec.param R.plant_id plant;
          Codec.param R.source source;
        ];
    }

let upsert_row r =
  Outbox.bare
    (Stmt.upsert
       ~conflict:[R.plant_id.name; R.source.name]
       ~keep:[R.id.name; R.created_at.name]
       ~table:R.table (input r))

let upsert_plant_ref p =
  Outbox.bare
    (Stmt.upsert
       ~conflict:[Pr.plant_id.name; Pr.source.name]
       ~keep:[Pr.id.name; Pr.created_at.name]
       ~table:Pr.table (plant_ref_input p))

let plant_refs plant =
  Stmt.query ~json:[] plant_ref_row
    "select * from plant_refs where plant_id = ? and deleted_at is null order \
     by source"
    [Codec.param Pr.plant_id plant]

let plant_ref_edit ~plant ~source stmt =
  Outbox.edit ~table:Pr.table
    ~reread:
      (Stmt.query ~json:[] plant_ref_row
         "select * from plant_refs where plant_id = ? and source = ?"
         [Codec.param Pr.plant_id plant; Codec.param Pr.source source])
    ~row_id:(fun (p : Reference.Plant_ref.t) -> Plant_ref_id.to_string p.id)
    ~input:plant_ref_input stmt

(* The where clause of the update leaves a live, unchanged link alone, so
   linking twice appends no entry. *)
let link ~plant ~source ~external_id ~url ~at =
  plant_ref_edit ~plant ~source
    {
      Stmt.sql =
        "insert into plant_refs (id, plant_id, source, external_id, url, \
         created_at, updated_at, deleted_at) values (?, ?, ?, ?, ?, ?, ?, \
         null) on conflict (plant_id, source) do update set external_id = \
         excluded.external_id, url = excluded.url, updated_at = \
         excluded.updated_at, deleted_at = null where plant_refs.deleted_at is \
         not null or plant_refs.external_id is not excluded.external_id or \
         plant_refs.url is not excluded.url";
      params =
        [
          Codec.param Pr.id (Reference.Plant_ref.id_of_key ~plant ~source);
          Codec.param Pr.plant_id plant;
          Codec.param Pr.source source;
          Codec.param Pr.external_id external_id;
          Codec.param Pr.url url;
          Codec.param Pr.created_at at;
          Codec.param Pr.updated_at at;
        ];
    }

let unlink ~plant ~source ~at =
  plant_ref_edit ~plant ~source
    {
      Stmt.sql =
        "update plant_refs set deleted_at = ?, updated_at = ? where plant_id = \
         ? and source = ? and deleted_at is null";
      params =
        [
          Codec.param Pr.deleted_at (Some at);
          Codec.param Pr.updated_at at;
          Codec.param Pr.plant_id plant;
          Codec.param Pr.source source;
        ];
    }
