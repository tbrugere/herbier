// The keep-alive job (architecture §4, keep-alive): run by
// @capacitor/background-runner in its own JS engine, by WorkManager with
// the app closed, and by the app through dispatchEvent. No imports, no
// WebView, no OCaml; each event runs in a fresh context, so all state is in
// CapacitorKV (SharedPreferences named after the runner's label). Its
// contract with the app is app/sync/keepalive/{wire,report}.mli. Never
// logs or reports a token.
//
// KV keys, all text: backend {v, supabase_url, apikey, ping, refresh,
// logout} (JSON), session (Session.to_string's format), queue {v, requests}
// (JSON), inflight (the Date.now() at which a request of the queue was
// sent, while it has not answered), log (JSON runs, newest first).
//
// A WorkManager run and the app's dispatches run in two engines on two
// threads over the same SharedPreferences, with no lock: every write that
// follows an await re-reads the key it depends on first.

const LOG_MAX = 20;
// Refreshed when its access token expires within this many seconds: the
// app's own margin, Session.refresh_margin.
const REFRESH_MARGIN_S = 90;
// reclaim waits this long at most for a request of the queue in flight.
const RECLAIM_WAIT_MS = 10 * 1000;
const RECLAIM_POLL_MS = 200;
// An inflight mark older than this is a run that died mid-request
// (WorkManager stops a worker after 10 minutes).
const INFLIGHT_MAX_MS = 10 * 60 * 1000;

const message = (e) => (e && e.message ? String(e.message) : String(e));

function kvGet(key) {
  const r = CapacitorKV.get(key);
  return r && typeof r.value === 'string' ? r.value : null;
}

function parseOrNull(text) {
  if (text === null) return null;
  try {
    return JSON.parse(text);
  } catch (e) {
    return null;
  }
}

const kvJson = (key) => parseOrNull(kvGet(key));

const isObject = (v) => typeof v === 'object' && v !== null && !Array.isArray(v);
const isString = (v) => typeof v === 'string';

function validRequest(r) {
  return (
    isObject(r) &&
    isString(r.method) &&
    isString(r.url) &&
    isObject(r.headers) &&
    Object.values(r.headers).every(isString) &&
    (r.body === null || isString(r.body))
  );
}

// Every request of the backend goes to the backend itself.
const under = (b, r) => validRequest(r) && r.url.startsWith(b.supabase_url + '/');

function validBackend(b) {
  return (
    isObject(b) && b.v === 1 && isString(b.supabase_url) && isString(b.apikey) &&
    under(b, b.ping) && under(b, b.refresh) && under(b, b.logout)
  );
}

function validSession(s) {
  return (
    isObject(s) && s.v === 1 && isString(s.access_token) &&
    isString(s.refresh_token) && Number.isInteger(s.expires_at) &&
    isString(s.user_id) && (s.email === null || isString(s.email))
  );
}

function validQueue(q) {
  return isObject(q) && q.v === 1 && Array.isArray(q.requests) &&
    q.requests.every(validRequest);
}

// The details of an event: the JSON text in its "json" field.
function detailsJson(args) {
  if (!isObject(args) || !isString(args.json)) throw new Error('no json');
  return JSON.parse(args.json);
}

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

// When a request of the queue was sent and has not answered yet; null when
// none is in flight (or the mark is too old to be one).
function inflightSince() {
  const at = Number(kvGet('inflight'));
  if (!Number.isFinite(at) || at <= 0) return null;
  return Date.now() - at < INFLIGHT_MAX_MS ? at : null;
}

// Every handler calls resolve or reject exactly once, on every path.
function handle(event, body) {
  addEventListener(event, (resolve, reject, args) => {
    let result;
    try {
      result = body(args);
    } catch (e) {
      reject(new Error(event + ': ' + message(e)));
      return;
    }
    Promise.resolve(result).then(
      (v) => (v === undefined ? resolve() : resolve(v)),
      (e) => reject(new Error(event + ': ' + message(e))),
    );
  });
}

handle('setSession', (args) => {
  const doc = detailsJson(args);
  if (!isObject(doc) || !validBackend(doc.backend) || !validSession(doc.session))
    throw new Error('bad session document');
  CapacitorKV.remove('queue');
  CapacitorKV.set('backend', JSON.stringify(doc.backend));
  CapacitorKV.set('session', JSON.stringify(doc.session));
});

handle('takeSession', () => {
  const session = kvJson('session');
  CapacitorKV.remove('session');
  CapacitorKV.remove('queue');
  return {
    json: JSON.stringify({ v: 1, session: validSession(session) ? session : null }),
  };
});

handle('handOff', (args) => {
  const queue = detailsJson(args);
  if (!validQueue(queue)) throw new Error('bad queue document');
  CapacitorKV.set('queue', JSON.stringify(queue));
});

// The queue is gone once this answers, and so is any request of it in
// flight, unless in_flight says it still was after RECLAIM_WAIT_MS: a run
// marks inflight before it checks the queue, so one that has not marked yet
// will find the queue gone.
handle('reclaim', async () => {
  CapacitorKV.remove('queue');
  const until = Date.now() + RECLAIM_WAIT_MS;
  while (inflightSince() !== null && Date.now() < until) await sleep(RECLAIM_POLL_MS);
  CapacitorKV.remove('queue');
  return { json: JSON.stringify({ v: 1, in_flight: inflightSince() !== null }) };
});

handle('report', () => {
  const session = kvJson('session');
  const queue = kvJson('queue');
  const log = kvJson('log');
  return {
    json: JSON.stringify({
      v: 1,
      session_expires_at: validSession(session) ? session.expires_at : null,
      queued: validQueue(queue) ? queue.requests.length : 0,
      runs: Array.isArray(log) ? log : [],
    }),
  };
});

const appActive = () => CapacitorApp.getState().isActive === true;

function withBearer(request, token) {
  const headers = Object.assign({}, request.headers);
  headers.authorization = 'Bearer ' + token;
  const init = { method: request.method, headers };
  if (request.body !== null) init.body = request.body;
  return init;
}

// backend.refresh is Gotrue.refresh_grant; the answer is read as
// Gotrue.decode_session, and a GoTrue 4xx with a code other than 408 and
// 429 is Gotrue.revokes_session.
async function refresh(backend, session) {
  const sentS = Math.floor(Date.now() / 1000);
  const template = backend.refresh;
  let response;
  try {
    response = await fetch(template.url, {
      method: template.method,
      headers: Object.assign({}, template.headers),
      body: JSON.stringify({ refresh_token: session.refresh_token }),
    });
  } catch (e) {
    return { outcome: 'refresh_failed', why: 'network: ' + message(e) };
  }
  const status = response.status;
  let body;
  try {
    body = JSON.parse(await response.text());
  } catch (e) {
    body = null;
  }
  if (status >= 200 && status <= 299) {
    const user = isObject(body) ? body.user : null;
    if (
      !isObject(body) || !isString(body.access_token) ||
      !isString(body.refresh_token) || !Number.isInteger(body.expires_in) ||
      body.expires_in <= 0 || !isObject(user) || !isString(user.id)
    )
      return { outcome: 'refresh_failed', why: 'malformed answer' };
    return {
      outcome: 'refreshed',
      session: {
        v: 1,
        access_token: body.access_token,
        refresh_token: body.refresh_token,
        expires_at: sentS + body.expires_in,
        user_id: user.id,
        email: isString(user.email) && user.email !== '' ? user.email : null,
      },
    };
  }
  const coded = isObject(body) && (isString(body.error_code) || isString(body.error));
  if (coded && status >= 400 && status <= 499 && status !== 408 && status !== 429)
    return { outcome: 'revoked', status };
  return { outcome: 'refresh_failed', why: 'HTTP ' + status };
}

// Best effort: a session nobody keeps is revoked on the server.
async function logout(backend, token) {
  try {
    await fetch(backend.logout.url, withBearer(backend.logout, token));
  } catch (e) {
    console.warn('keepalive: logout: network: ' + message(e));
  }
}

// One request of the queue, unless the queue is no longer the one read at
// the start (the app takes it back before it pushes) or the app is active.
// The inflight mark is set before those checks: see reclaim.
async function pushOne(backend, request, token, text, queue) {
  CapacitorKV.set('inflight', String(Date.now()));
  try {
    if (kvGet('queue') !== text) return 'taken back';
    if (appActive()) return 'app active';
    if (!request.url.startsWith(backend.supabase_url + '/rest/v1/')) return 'foreign url';
    let response;
    try {
      response = await fetch(request.url, withBearer(request, token));
    } catch (e) {
      return 'network: ' + message(e);
    }
    if (response.status < 200 || response.status > 299) return 'HTTP ' + response.status;
    queue.pushed += 1;
    return null;
  } finally {
    CapacitorKV.remove('inflight');
  }
}

// The handed requests in order, each with the bearer; stops at the first
// failure. A queue pushed to the end is forgotten, unless a new one was
// handed meanwhile.
async function pushQueue(backend, token, run) {
  const queue = { pushed: 0, stop: null };
  run.queue = queue;
  const text = kvGet('queue');
  const parsed = parseOrNull(text);
  if (!validQueue(parsed)) return;
  for (const request of parsed.requests) {
    const stop = await pushOne(backend, request, token, text, queue);
    if (stop !== null) {
      queue.stop = stop;
      return;
    }
  }
  if (kvGet('queue') === text) CapacitorKV.remove('queue');
}

async function ping(backend, token) {
  try {
    const response = await fetch(backend.ping.url, withBearer(backend.ping, token));
    return response.status;
  } catch (e) {
    return 'network: ' + message(e);
  }
}

// Keepalive.Report.run_to_string's line.
function line(run) {
  const session = {
    none: 'none',
    fresh: 'fresh',
    refreshed: 'refreshed',
    replaced: 'replaced',
    revoked: 'revoked ' + run.revoked_status,
    refresh_failed: 'refresh failed (' + run.refresh_error + ')',
  }[run.session];
  const at = new Date(run.at).toISOString().replace(/\.\d{3}Z$/, 'Z');
  const parts = [at, run.trigger, session];
  if (run.queue === 'skipped') parts.push('queue skipped');
  else if (run.queue !== null) {
    parts.push('pushed ' + run.queue.pushed);
    if (run.queue.stop !== null) parts.push('stop (' + run.queue.stop + ')');
  }
  if (run.error !== null) parts.push('error (' + run.error + ')');
  parts.push(
    run.ping === null
      ? 'no ping'
      : typeof run.ping === 'number'
        ? 'ping ' + run.ping
        : 'ping failed (' + run.ping + ')',
  );
  return parts.join(' ');
}

function record(run) {
  try {
    const log = kvJson('log');
    const runs = [run].concat(Array.isArray(log) ? log : []).slice(0, LOG_MAX);
    CapacitorKV.set('log', JSON.stringify(runs));
  } catch (e) {
    console.error('keepalive: run not recorded: ' + message(e));
  }
  console.log('keepalive: ' + line(run));
}

async function steps(run) {
  run.app_active = appActive();
  const sessionText = kvGet('session');
  if (sessionText === null) return;
  let session = parseOrNull(sessionText);
  const backend = kvJson('backend');
  if (!validSession(session)) {
    run.error = 'bad session in KV';
    return;
  }
  if (!validBackend(backend)) {
    run.error = 'bad backend in KV';
    return;
  }
  if (session.expires_at - Math.floor(Date.now() / 1000) <= REFRESH_MARGIN_S) {
    const r = await refresh(backend, session);
    if (kvGet('session') !== sessionText) {
      // The app set or took the session meanwhile: its write stands.
      run.session = 'replaced';
      if (r.outcome === 'refreshed') await logout(backend, r.session.access_token);
      return;
    }
    switch (r.outcome) {
      case 'refreshed':
        // Stored before use: the old refresh token is spent.
        run.session = 'refreshed';
        CapacitorKV.set('session', JSON.stringify(r.session));
        session = r.session;
        break;
      case 'revoked':
        CapacitorKV.remove('session');
        CapacitorKV.remove('queue');
        run.session = 'revoked';
        run.revoked_status = r.status;
        return;
      default:
        run.session = 'refresh_failed';
        run.refresh_error = r.why;
        return;
    }
  } else {
    run.session = 'fresh';
  }
  if (run.app_active) run.queue = 'skipped';
  else await pushQueue(backend, session.access_token, run);
  run.ping = await ping(backend, session.access_token);
}

// One run; it always resolves (a failed WorkManager worker is not retried
// sooner anyway), an unexpected exception logged as the run's error.
async function runOnce(trigger) {
  const run = {
    at: Date.now(),
    trigger,
    app_active: false,
    session: 'none',
    queue: null,
    error: null,
    ping: null,
  };
  try {
    await steps(run);
  } catch (e) {
    run.error = message(e);
  }
  record(run);
}

addEventListener('keepAlive', (resolve) => {
  runOnce('job').then(() => resolve(), () => resolve());
});

addEventListener('runNow', (resolve) => {
  runOnce('dispatch').then(() => resolve(), () => resolve());
});
