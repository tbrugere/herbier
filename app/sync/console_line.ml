type scope = Auth | Sync | Keepalive

let prefix = function
  | Auth -> "auth: "
  | Sync -> "sync: "
  | Keepalive -> "keepalive: "

let log scope m = Brr.Console.(log [str (prefix scope ^ m)])
let warn scope m = Brr.Console.(warn [str (prefix scope ^ m)])
let error scope m = Brr.Console.(error [str (prefix scope ^ m)])
