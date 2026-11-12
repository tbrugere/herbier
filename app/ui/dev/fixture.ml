let state () =
  State.create
    ~network:{online = true; pending_uploads = 0}
    ~account:
      {
        google_signed_in = false;
        storage = Herbier_domain.Photo.Original_target.App_only;
        wifi_only = false;
      }
    ~place_sources:Herbier_geo.Place_name.none
