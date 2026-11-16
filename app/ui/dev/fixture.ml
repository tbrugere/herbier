let state () =
  State.create ~network:{online = true}
    ~account:
      {
        auth = Herbier_sync.Auth.Signed_out;
        storage = Herbier_domain.Photo.Original_target.App_only;
        drive = Herbier_sync_core.Auth.Drive_account.Unchosen;
        wifi_only = false;
      }
    ~place_sources:Herbier_geo.Place_name.none

let auth () = Herbier_sync.Auth.create ()
