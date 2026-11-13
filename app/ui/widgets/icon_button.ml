let el ?(classes = []) ~label icon =
  Html.button ~label ("icon-button" :: classes) [Icon.el icon]
