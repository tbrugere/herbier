let offset_s t = Herbier_bindings.Js_date.offset_at_s (Ptime.to_float_s t)
let date t = Fr_date.local_date ~tz_offset_s:(offset_s t) t
