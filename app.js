'use strict';
/* ===========================================================================
   collectibles — flea-market triage for comics
   ---------------------------------------------------------------------------
   NO FEATURES YET. This file is infrastructure PORTED from HealthTracker
   (healthtracker@dcf3d78), copied rather than shared (D1):
     • storage adapter: localStorage -> memory, truthful badge (HT-D1)
     • export / destructive restore with a pre-restore backup (HT-D3, HT-D5)
     • credentials outside the state object, merge-only writes (HT-D45, HT-D49)
     • ONE egress function for every network call, provider table (D1)
     • the capture chain: camera-or-library, bounded decode, EXIF pin,
       blank-canvas floor, per-call budgets (HT-D47, HT-D48, HT-D58)
     • validate -> retry once -> fall back WITH the raw reply (HT-D64)
     • the capture trace (HT-D65, HT-D66)
     • the outcome modal: one modal, three states (HT-D51)

   `HT-Dnn` cites HealthTracker's log, copied as INHERITED-DECISIONS.md. Those
   entries are why the code below is shaped as it is. Read the entry before
   simplifying anything that carries one.
   =========================================================================== */

// ---- keys & schema --------------------------------------------------------
// D1: EVERY storage key is prefixed. Two GitHub Pages project sites under one
// user domain share an origin, and so share localStorage with HealthTracker.
const STORE_KEY      = 'collectibles-state';               // HT-D1: version-stable key
const PRERESTORE_KEY = 'collectibles-state-prerestore';    // HT-D3: pre-restore backup
const CRED_PREFIX    = 'collectibles-cred-';               // D1: + role; never in state
const STATE_KIND     = 'collectibles';
const SCHEMA_VERSION = 1;

// ---- small helpers --------------------------------------------------------
// Escaper covers & < > " '.
const esc = (s) => String(s == null ? '' : s).replace(/[&<>"']/g, (c) => (
  { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]
));
const num = (v) => { const n = Number(v); return Number.isFinite(n) ? n : 0; };

// Pasted JSON may arrive from a chat app: normalize smart quotes / non-breaking
// spaces before JSON.parse so a clean-looking paste isn't rejected as "Bad JSON".
const cleanJSON = (s) => String(s == null ? '' : s)
  .replace(new RegExp('[' + String.fromCharCode(0x201C, 0x201D, 0x201E, 0x201F, 0x2033, 0x2036) + ']', 'g'), '"')
  .replace(new RegExp('[' + String.fromCharCode(0x2018, 0x2019, 0x201A, 0x201B, 0x2032, 0x2035) + ']', 'g'), "'")
  .replace(new RegExp('[' + String.fromCharCode(0xA0, 0x2007, 0x202F) + ']', 'g'), ' ')
  .trim();

// ---- ONE clock (HT-D50) ---------------------------------------------------
// setClock is a TEST SEAM and is never called by shipped code. Every date and
// duration reads through nowMs(), so a gate that fixes the clock fixes all of
// it -- HealthTracker had 21 call sites on a second clock before this.
let _clockFn = null;
function nowMs() { return _clockFn ? _clockFn() : Date.now(); }
function setClock(fn) { _clockFn = (typeof fn === 'function') ? fn : null; }
function nowDate() { return new Date(nowMs()); }
function localDate(d) {
  d = d || nowDate();
  return d.getFullYear() + '-' +
    String(d.getMonth() + 1).padStart(2, '0') + '-' +
    String(d.getDate()).padStart(2, '0');
}
function todayKey() { return localDate(nowDate()); }
// HH:MM:SS, local. What a result line is stamped with, so that two taps with
// the same outcome still read as two answers (C1's save, 2026-09-16).
function clockTime(d) {
  d = d || nowDate();
  return [d.getHours(), d.getMinutes(), d.getSeconds()]
    .map(function (n) { return String(n).padStart(2, '0'); }).join(':');
}

// ---- storage adapter: localStorage -> memory (HT-D1, HT-D3) ---------------
const Store = (() => {
  let tier = 'unknown';     // 'local' | 'memory'
  let lastWriteOk = true;   // false only after a real write failure on 'local'
  let forceFail = false;    // test seam -- see CT.Store.forceWriteFailure()

  function probe() {
    try { localStorage.setItem('__ct_probe__', '1'); localStorage.removeItem('__ct_probe__'); return true; }
    catch (e) { return false; }
  }
  function readRaw(key) {
    if (tier === 'memory') return null;
    try { return localStorage.getItem(key); } catch (e) { return null; }
  }
  function writeRaw(key, value) {
    if (forceFail) return false;
    try { localStorage.setItem(key, value); return true; } catch (e) { return false; }
  }

  return {
    init() { lastWriteOk = true; tier = probe() ? 'local' : 'memory'; return tier; },
    get tier() { return tier; },
    readRaw,

    saveState(blob) {
      const json = JSON.stringify(blob);
      if (tier === 'local' && writeRaw(STORE_KEY, json)) { lastWriteOk = true; return true; }
      lastWriteOk = false; tier = 'memory'; return false;
    },

    // HT-D3: durable single-slot pre-restore backup.
    backup(blob) {
      if (tier !== 'local') return false;
      return writeRaw(PRERESTORE_KEY, JSON.stringify(blob));
    },
    peekBackup() { return readRaw(PRERESTORE_KEY); },
    // Auxiliary keys OUTSIDE the state object -- the running version, and whatever
    // later needs to outlive a restore without entering the export.
    //
    // IT WRITES WHATEVER THE TIER. Until 2026-09-16 this comment said that on the
    // memory tier it "is a no-op", mirroring readRaw. The code never did that:
    // writeRaw does not look at the tier. So on the memory tier a write can
    // SUCCEED while readRaw returns null for the same key, and `true` here means
    // "storage took it", never "this session can read it back". C1's save trusted
    // the sentence, reported ok, and the card said nothing. A caller that needs
    // the value later must read it back through the path its consumer uses.
    writeAux(key, value) { return writeRaw(key, value); },
    revertBackup(snapshot) {
      if (tier !== 'local') return;
      if (snapshot == null) { try { localStorage.removeItem(PRERESTORE_KEY); } catch (e) {} }
      else writeRaw(PRERESTORE_KEY, snapshot);
    },

    status() {
      if (tier === 'memory' && lastWriteOk) {
        return { tier: 'memory', ok: false, message: '⚠ NOT saved (private mode / storage blocked) — export before closing' };
      }
      if (!lastWriteOk) {
        return { tier: 'memory', ok: false, message: '⚠ storage write FAILED — data is only in memory; export now' };
      }
      return { tier: 'local', ok: true, message: '✓ saved in this browser' };
    },
    forceWriteFailure(on) { forceFail = !!on; },
  };
})();

// ---- state (schema v1) ----------------------------------------------------
// No features, so the state carries only `settings`, preserved as an opaque
// object. `kind` is what lets restore refuse ANOTHER PRODUCT's export: a
// HealthTracker export carries version 7, and without a kind check it would be
// refused as "from a newer version" -- a wrong reason, stated confidently.
function emptyState() { return { kind: STATE_KIND, version: SCHEMA_VERSION, settings: {} }; }
function normalizeState(o) {
  const s = (o && o.settings && typeof o.settings === 'object' && !Array.isArray(o.settings))
    ? JSON.parse(JSON.stringify(o.settings)) : {};
  return { kind: STATE_KIND, version: SCHEMA_VERSION, settings: s };
}

// ---- boot -----------------------------------------------------------------
let APP_STATE = null;
let APP_SOURCE = 'empty';   // 'store' | 'restored' | 'empty' | 'future'

function boot() {
  Store.init();
  let state = null, source = 'empty', dirty = false;
  const raw = Store.readRaw(STORE_KEY);
  if (raw) {
    try {
      const parsed = JSON.parse(raw);
      if (parsed && typeof parsed === 'object' && parsed.kind === STATE_KIND) {
        const v = parsed.version;
        if (typeof v === 'number' && v > SCHEMA_VERSION) {
          // A newer app wrote this -- never migrate or overwrite it (HT-D7).
          APP_STATE = parsed; APP_SOURCE = 'future';
          return { state: parsed, source: 'future', status: Store.status() };
        }
        if (v === SCHEMA_VERSION) {
          state = normalizeState(parsed); source = 'store';
          if (JSON.stringify(state) !== raw) dirty = true;
        }
      }
    } catch (e) { state = null; }   // corrupt blob: fall through to a fresh state (as HealthTracker)
  }
  if (!state) { state = emptyState(); source = 'empty'; dirty = true; }
  if (dirty) Store.saveState(state);
  APP_STATE = state; APP_SOURCE = source;
  return { state, source, status: Store.status() };
}

// ---- export / import-restore (HT-D5) --------------------------------------
function exportJSON() { return JSON.stringify(APP_STATE, null, 2); }

// Validate + route a pasted blob WITHOUT mutating.
function parseImport(raw) {
  const text = cleanJSON(raw);
  if (!text) return { ok: false, error: 'Nothing to import.' };
  let o;
  try { o = JSON.parse(text); }
  catch (e) { return { ok: false, error: 'Bad JSON: ' + e.message }; }
  if (!o || typeof o !== 'object' || Array.isArray(o) || o.kind !== STATE_KIND)
    return { ok: false, error: 'Not a collectibles export.' };
  const v = o.version;
  if (typeof v !== 'number' || v < 1)
    return { ok: false, error: 'Unrecognized export format (no version).' };
  if (v > SCHEMA_VERSION)
    return { ok: false, error: 'This export is from a newer version of the app.' };
  return { ok: true, state: normalizeState(o), kind: 'restore' };
}

function showPrerestore(json) {
  const el = document.getElementById('prerestoreBox');
  const wrap = document.getElementById('prerestoreWrap');
  if (el) el.value = json;
  if (wrap) wrap.style.display = 'block';
}
function hidePrerestore() {
  const wrap = document.getElementById('prerestoreWrap');
  if (wrap) wrap.style.display = 'none';
}

// Destructive full replace. Nothing mutates until a valid replacement is in hand.
function restore(raw) {
  const parsed = parseImport(raw);
  if (!parsed.ok) return { ok: false, error: parsed.error };

  const prev = APP_STATE;
  showPrerestore(JSON.stringify(prev, null, 2));
  const priorSlot = Store.peekBackup();            // snapshot existing undo slot (HT-D5)
  const backedUp = Store.backup(prev);             // overwrite single rolling slot (HT-D3)

  const msg = backedUp
    ? 'Replace ALL current data with the imported data?\n\nYour previous data has been backed up (shown on the page) and can be recovered — proceed?'
    : 'Replace ALL current data?\n\n⚠ Storage could NOT keep a backup. Copy the "previous data" text shown on the page FIRST, then proceed anyway?';
  if (!window.confirm(msg)) {
    Store.revertBackup(priorSlot);                 // decline = true no-op for the undo slot
    hidePrerestore();
    return { ok: false, aborted: true };
  }

  APP_STATE = parsed.state;
  const saved = Store.saveState(APP_STATE);
  APP_SOURCE = 'restored';
  refresh();
  return { ok: true, kind: parsed.kind, backedUp: backedUp, saved: saved };
}

// ---- DOM handlers ---------------------------------------------------------
function copyOut() {
  const json = exportJSON();
  const box = document.getElementById('exportBox');
  if (box) { box.value = json; box.focus(); box.select(); try { box.setSelectionRange(0, json.length); } catch (e) {} }
  let done = false;
  try { done = document.execCommand('copy'); } catch (e) {}
  if (!done && navigator.clipboard && navigator.clipboard.writeText) {
    // HT-D63: a rejection is REPORTED, not swallowed.
    navigator.clipboard.writeText(json).then(
      function () { toast('Copied'); },
      function () { toast('Copy did not work — select the text above and copy it'); });
    return;
  }
  toast(done ? 'Copied' : 'Select-all + copy the text above');
}
function doRestore() {
  const box = document.getElementById('importBox');
  const raw = box ? box.value : '';
  if (!raw.trim()) { toast('Paste an export first'); return; }
  const r = restore(raw);
  if (!r.ok) { toast(r.aborted ? 'Restore cancelled' : (r.error || 'Restore failed')); return; }
  if (box) box.value = '';
  toast(r.saved ? 'Restored' : 'Restored to memory — export to be safe');
}
let _toastT;
function toast(m) {
  const e = document.getElementById('toast');
  if (!e) return;
  e.textContent = m; e.classList.add('show');
  clearTimeout(_toastT);
  _toastT = setTimeout(function () { e.classList.remove('show'); }, 1900);
}

// HT-D16: ask the browser to make storage persistent. Best-effort and SILENT by
// contract; export is the real durability guarantee.
function requestPersistentStorage() {
  try {
    if (navigator.storage && navigator.storage.persist) navigator.storage.persist().catch(function () {});
  } catch (e) { /* never blocks boot */ }
}

// HT-D53: provenance is auditable, not content -- fine print sits behind one tap.
// Safety text never goes in here.
function citeBlock(summary, innerHTML) {
  return `<details class="cited"><summary>${esc(summary)}</summary><div class="citebody">${innerHTML}</div></details>`;
}

// ---- PROVIDER TABLE (D1) --------------------------------------------------
// A provider is CONFIGURATION: its role, where it lives, how it authenticates
// and how fast it may be called. HT-D45's "a second provider is a table row, not
// a code change", extended to a second ROLE.
//
// `auth`: 'bearer'  -> Authorization header
//         'query'   -> the credential as the `authParam` URL parameter
//         'none'    -> no credential sent and none required. THIS IS THE SERVER
//                      MOVE (D1): point `base` at a server that holds the token
//                      and meters, set auth 'none', and no feature code changes.
const PROVIDERS = {
  // `jsonMode` / `reasoningEffort`: declared per provider, never assumed
  // (HT-D64, HT-D66). xAI defaults reasoning to HIGH; a real capture measured
  // 41.2s to first byte and 0.0s of body -- all deliberation.
  grok: { role: 'vision', label: 'xAI Grok', base: 'https://api.x.ai/v1', auth: 'bearer',
          model: 'grok-4.6', jsonMode: true, reasoningEffort: 'low', keyPrefix: 'xai-', dailyCap: 20 },
  // Verified in the live docs 2026-09-11: 40-character token as the `t`
  // parameter; "limited to 1 call every second ... account permissions revoked
  // if it persists". The pacing is HERE, not in each feature's memory.
  pricecharting: { role: 'prices', label: 'PriceCharting', base: 'https://www.pricecharting.com', auth: 'query',
                   authParam: 't', keyLength: 40, minIntervalMs: 1000, noun: 'Token',
                   warn: 'This token is a paid-subscription credential, and anyone with access to this browser can read it. Only use it on your own device.' },
  // R2b. Verified 2026-09-13: Apify sends `access-control-allow-origin: *` and
  // permits `Authorization`, so the page calls it directly -- unlike GCD, which
  // is why R2b goes before R2a (D6). The token rides as a BEARER HEADER, never a
  // URL parameter: PriceCharting's `t=` above this line is the lesson.
  //
  // `actor` uses `~`, not `/` -- `caffein.dev/ebay-sold-listings` is the store
  // path, `caffein.dev~ebay-sold-listings` is the API id (actor oTtB3VgfuE9GtxQt2,
  // public). Both endpoint paths confirmed unauthenticated 2026-09-13: the real
  // ones answer 401 token-not-provided, a misspelled one answers 404, so the 401
  // is a signal rather than the blanket reply.
  //
  // COST IS CONFIGURATION, because it is what a wrong guess spends. The API
  // payload advertises "$2.00 / 1000"; the console charges $4.00. The measured
  // number is the one here.
  apify: { role: 'comps', label: 'Apify', base: 'https://api.apify.com/v2', auth: 'bearer',
           actor: 'caffein.dev~ebay-sold-listings', keyPrefix: 'apify_api_',
           minIntervalMs: 1000, usdPer1000: 4.00, noun: 'Token',
           categoryId: '259104',            // eBay Comics & Graphic Novels -> `_sacat`
           site: 'ebay.com',
           warn: 'This token SPENDS MONEY — about $0.40 each time you look up comps, charged to your Apify account. ' +
                 'Anyone with access to this browser can read it and spend it. Only use it on your own device.' },
};
const ROLES = ['vision', 'prices', 'comps'];
const ROLE_DEFAULT = { vision: 'grok', prices: 'pricecharting', comps: 'apify' };
const ROLE_LABEL = { vision: 'Vision key', prices: 'Price-guide token', comps: 'Comps token' };

// ---- credentials: OUTSIDE THE STATE OBJECT, one store per role (D1, HT-D45) --
// The credential never enters APP_STATE, so export, the pre-restore backup and
// restore cannot carry it BY CONSTRUCTION. One storage key per role, so a write
// to one role cannot touch the other.
const _credMem = {};                        // HT-D1: memory fallback, same as Store
function credStoreKey(role) { return CRED_PREFIX + role; }
function credRead(role) {
  if (_credMem[role]) return _credMem[role];
  try {
    const raw = localStorage.getItem(credStoreKey(role));
    if (!raw) return null;
    const o = JSON.parse(raw);
    return (o && typeof o === 'object') ? o : null;
  } catch (e) { return null; }
}
function credWrite(role, o) {
  _credMem[role] = o;
  try { localStorage.setItem(credStoreKey(role), JSON.stringify(o)); return true; } catch (e) { return false; }
}
// HT-D49 -- ONE WAY TO WRITE, and it is a MERGE. HealthTracker's counter rebuilt
// the blob from its own field list and ERASED the verified status mid-capture;
// "remember to carry the other fields" is a rule, and the rule failed. A merge
// cannot forget, including fields no writer has been taught about yet.
function credPatch(role, patch) {
  const o = credRead(role) || {};
  Object.keys(patch || {}).forEach(function (k) { o[k] = patch[k]; });
  return credWrite(role, o);
}
function credClear(role) {
  delete _credMem[role];
  try { localStorage.removeItem(credStoreKey(role)); } catch (e) {}
  if (CRED_STATE[role]) CRED_STATE[role] = null;
  refresh();
  return { ok: true };
}
function credSettings(role) {
  const o = credRead(role) || {};
  const pick = (PROVIDERS[o.provider] && PROVIDERS[o.provider].role === role) ? o.provider : ROLE_DEFAULT[role];
  const row = PROVIDERS[pick] || {};
  const st = (o.status && typeof o.status === 'object') ? o.status : null;
  return { role: role, provider: pick, key: String(o.key || ''),
           cap: (o.cap > 0 ? o.cap : num(row.dailyCap)),
           used: (o.used && typeof o.used === 'object') ? o.used : { date: '', n: 0 },
           status: st || { state: 'unverified', at: '', message: '' } };
}
// HT-D46: a SHAPE check, not a validity check. Blocking rules are the ones that
// are certainly wrong for any provider; a surprising prefix or length WARNS and
// saves anyway, because key formats change and refusing on a guess is worse.
function credKeyIssue(provider, key) {
  const k = String(key == null ? '' : key);
  const row = PROVIDERS[provider] || {};
  if (!k.trim()) return { block: true, message: 'Nothing entered.' };
  if (/\s/.test(k.trim())) return { block: true, message: 'That contains a space — check for a copy-paste stray.' };
  if (k.trim().length < 20) return { block: true, message: 'That looks too short to be complete.' };
  if (row.keyPrefix && k.trim().indexOf(row.keyPrefix) !== 0)
    return { block: false, message: 'That does not start with "' + row.keyPrefix + '", which ' + row.label +
             ' keys usually do. Saved anyway — test it to find out.' };
  if (row.keyLength && k.trim().length !== row.keyLength)
    return { block: false, message: row.label + ' tokens are ' + row.keyLength + ' characters; this one is ' +
             k.trim().length + '. Saved anyway — test it to find out.' };
  return null;
}
// THE single source of truth for "does this credential work": what the provider
// last said about it, whichever call asked (HT-D49).
function credSetStatus(role, state, message) {
  const st = { state: state, at: new Date(nowMs()).toISOString(), message: String(message || '') };
  credPatch(role, { status: st });
  return st;
}
function credConfigured(role) { return credSettings(role).key.length > 0; }
function credStatusLine(role) {
  if (!credConfigured(role)) return '';
  const st = credSettings(role).status;
  if (st.state === 'verified') return 'verified';
  if (st.state === 'failed') return 'failed its last test';
  return 'not tested yet';
}
// NEVER returns the credential. The mask is the ONLY thing any surface may show.
function credMask(role) {
  const k = credSettings(role).key;
  if (!k) return '';
  return k.length <= 8 ? '********' : (k.slice(0, 3) + ' ... ' + k.slice(-3));
}
function credSave(role, provider, key, cap) {
  const o = credSettings(role);
  const row = PROVIDERS[provider];
  const next = { provider: (row && row.role === role) ? provider : o.provider,
                 key: (key == null ? o.key : String(key).trim()),
                 cap: (cap == null || !(Number(cap) > 0)) ? o.cap : Math.round(Number(cap)),
                 used: o.used };
  const issue = (key == null) ? null : credKeyIssue(next.provider, next.key);
  if (issue && issue.block) return { ok: false, blocked: true, message: issue.message, configured: credConfigured(role) };
  // Merging must not preserve a verdict about a DIFFERENT credential (HT-D49).
  next.status = (key != null && next.key !== o.key) ? { state: 'unverified', at: '', message: '' } : o.status;
  // A write that did not land must NOT report success (HT-D46): the memory
  // fallback masks it until the next reload, and then the credential is gone.
  const ok = credPatch(role, next);
  refresh();
  return { ok: ok, stored: ok, warning: (issue && !issue.block) ? issue.message : '',
           provider: next.provider, cap: next.cap, configured: next.key.length > 0 };
}
// HT-D45 Fork E: the counter lives WITH THE CREDENTIAL, not in the state, so a
// restore cannot move it. Resets at local midnight. Only a row that declares a
// dailyCap is capped.
function credCap(role) {
  const s = credSettings(role);
  const today = todayKey();
  const n = (s.used.date === today) ? num(s.used.n) : 0;
  const capped = s.cap > 0;
  return { date: today, used: n, cap: s.cap, capped: capped,
           left: capped ? Math.max(0, s.cap - n) : Infinity, exhausted: capped && n >= s.cap };
}
// Touches the COUNTER and nothing else (HT-D49).
function credCount(role) {
  const c = credCap(role);
  credPatch(role, { used: { date: c.date, n: c.used + 1 } });
  return credCap(role);
}

// ---- EGRESS (D1): every network call in this app goes through this function --
// It resolves the provider row, attaches the credential AS THE ROW DECLARES,
// paces the call, bounds it with a timeout, and classifies transport failure.
// Nothing else calls the network -- tests/check-egress.sh counts the sites.
//
// It never puts a URL into anything it returns: with query-parameter auth the
// URL CONTAINS the credential (D1).
let CALL_TIMEOUT_MS = 120000;      // HT-D48: a model reading a photograph
let TEST_TIMEOUT_MS = 15000;       // HT-D48: a one-token ping
function setCallTimeout(ms) { CALL_TIMEOUT_MS = (Number(ms) > 0) ? Number(ms) : 120000; }
function setTestTimeout(ms) { TEST_TIMEOUT_MS = (Number(ms) > 0) ? Number(ms) : 15000; }
let EGRESS_INFLIGHT = null;        // the controller, so a wait can be abandoned
let EGRESS_CANCELLED = false;
const PACE = {};                   // provider -> { last, chain }
function errOf(kind, message) { return { ok: false, kind: kind, error: message }; }

// D1: pacing is SERIALIZED per provider, and measured send-to-send. Two calls
// requested together leave at least minIntervalMs apart, never together.
function pace(name, row) {
  const gap = num(row && row.minIntervalMs);
  if (!(gap > 0)) return Promise.resolve();
  const p = PACE[name] || (PACE[name] = { last: -Infinity, chain: Promise.resolve() });
  const turn = p.chain.then(function () {
    const wait = Math.max(0, p.last + gap - nowMs());
    return new Promise(function (r) { setTimeout(r, wait); }).then(function () { p.last = nowMs(); });
  });
  p.chain = turn.catch(function () {});
  return turn;
}
// D1: a provider's own words may carry the credential back. Redacted before any
// surface sees them -- HealthTracker surfaces provider text verbatim, which is
// safe only against a provider known not to echo.
function redact(text, secret) {
  let s = String(text == null ? '' : text);
  if (secret && String(secret).length >= 8) s = s.split(String(secret)).join('[redacted]');
  return s;
}
// The provider's OWN error text, for a diagnosable failure: never the key, never
// the request we sent. PriceCharting uses `error-message`; OpenAI-style uses
// `error` (a string or {message}).
function providerMessage(raw, secret) {
  try {
    const j = JSON.parse(raw);
    const m = (j && (j['error-message'] || j.error || j.message)) || '';
    return redact(String(typeof m === 'string' ? m : (m.message || '')), secret).slice(0, 160);
  } catch (e) { return ''; }
}
function egress(role, req) {
  const cred = credSettings(role);
  const row = PROVIDERS[cred.provider];
  if (!row) return Promise.resolve(errOf('config', 'No provider configured.'));
  const needsKey = row.auth === 'bearer' || row.auth === 'query';
  if (needsKey && !cred.key) return Promise.resolve(errOf('config', 'No key saved.'));
  const o = req || {};
  const q = o.query || {};
  const parts = Object.keys(q).map(function (k) { return encodeURIComponent(k) + '=' + encodeURIComponent(q[k]); });
  if (row.auth === 'query') parts.push(encodeURIComponent(row.authParam) + '=' + encodeURIComponent(cred.key));
  const url = row.base + String(o.path || '') + (parts.length ? '?' + parts.join('&') : '');
  const headers = {};
  if (o.json !== undefined) headers['Content-Type'] = 'application/json';
  if (row.auth === 'bearer') headers.Authorization = 'Bearer ' + cred.key;
  const budget = Number(o.budget) > 0 ? Number(o.budget) : CALL_TIMEOUT_MS;
  const att = o.attempt || null;
  return pace(cred.provider, row).then(function () {
    const ctl = (typeof AbortController === 'function') ? new AbortController() : null;
    EGRESS_INFLIGHT = ctl; EGRESS_CANCELLED = false;
    const timer = setTimeout(function () { if (ctl) ctl.abort(); }, budget);
    if (att) att.sentAt = nowMs();
    return fetch(url, {
      method: o.method || (o.json !== undefined ? 'POST' : 'GET'),
      headers: headers,
      body: o.json !== undefined ? JSON.stringify(o.json) : undefined,
      signal: ctl ? ctl.signal : undefined,
    }).then(function (res) {
      clearTimeout(timer);
      EGRESS_INFLIGHT = null;
      // Headers are here: this is TIME TO FIRST BYTE (HT-D65). Everything after
      // it is the provider writing the body.
      if (att) { att.ttfbMs = nowMs() - att.sentAt; att.status = res.status; }
      return res.text().then(function (raw) {
        if (att) att.totalMs = nowMs() - att.sentAt;
        // The credential is NOT part of the result: a caller that logs this object
        // must not be able to log the key. Callers read it from settings to redact.
        return { transport: true, status: res.status, httpOk: !!res.ok, raw: String(raw == null ? '' : raw) };
      });
    }).catch(function (e) {
      clearTimeout(timer);
      EGRESS_INFLIGHT = null;
      const name = String((e && e.name) || '');
      if (att) { att.totalMs = nowMs() - att.sentAt; att.outcome = (name === 'AbortError' ? (EGRESS_CANCELLED ? 'cancelled' : 'aborted at budget') : 'network error'); }
      if (name === 'AbortError' && EGRESS_CANCELLED) return errOf('cancelled', 'Cancelled.');
      // HT-D48: an aborted request is not an unmade one.
      if (name === 'AbortError')
        return errOf('timeout', 'The provider did not answer within ' + Math.round(budget / 1000) +
          ' seconds. If it answered afterwards, that call still counted — check your provider console.');
      return errOf('network', 'The call could not be made. Check the connection.');
    });
  });
}

// ---- the VISION CONTRACT: UNRULED (D1 -- no features yet) -------------------
// The chain reads a reply against VISION: the prompt sent beside the photo, the
// parser that validates the reply, and what "use this" does with it. The
// identification contract (title, issue, publisher, cover date, cover price,
// variant markers, key-issue flag -- NEVER a value) is the first feature slice
// and is NOT ruled. Until it is, VISION is empty and capture says so instead of
// calling out.
const VISION_NONE = { version: 0, prompt: '', parse: null, accept: null, acceptLabel: '' };
let VISION = VISION_NONE;
// Test seam until a contract is ruled. The gates install a SYNTHETIC contract to
// drive the chain -- which proves the chain, and never a contract.
function setVisionContract(c) { const prev = VISION; VISION = (c && typeof c === 'object') ? c : VISION_NONE; return prev; }
function visionReady() { return !!(VISION && VISION.prompt && typeof VISION.parse === 'function'); }
// HT-D45 Fork B: the direct call needs a preamble a pasted reply does not, so it
// rides as a PREFIX carrying the contract's version -- never a forked prompt.
function visionPrefix() {
  return 'Contract v' + num(VISION && VISION.version) +
    '. Reply with the JSON object ONLY: no markdown fence, no prose before or after it.\n\n';
}

// ---- the capture RESULT: the success state ----------------------------------
let CAPTURE_RESULT = null;   // { value } | null -- held in memory, never persisted
// THE ONE DOOR (HT-D45: one downstream, not two). A called reply and a pasted
// reply both come through here, so identical text gives an identical result BY
// CONSTRUCTION rather than by two code paths agreeing.
function openCaptureResult(text) {
  const rep = document.getElementById('replyReport');
  const r = visionReady() ? VISION.parse(String(text == null ? '' : text))
    : { ok: false, error: 'Identification is not built yet, so there is nothing to read a reply against.' };
  if (!r || !r.ok) {
    const msg = (r && r.error) || 'That reply did not match.';
    if (rep) rep.innerHTML = `<div class="ireport bad">${esc(msg)}</div>`;
    return r || { ok: false, error: msg };
  }
  CAPTURE_RESULT = { value: r.value };
  if (rep) rep.innerHTML = '';
  renderCaptureResult();
  return r;
}
function doReplyPaste() {
  const box = document.getElementById('replyBox');
  const r = openCaptureResult(box ? box.value : '');
  if (r.ok && box) box.value = '';
  return r;
}
function captureResult() { return CAPTURE_RESULT; }
function captureDiscard() { CAPTURE_RESULT = null; renderCaptureResult(); return { ok: true }; }
function captureAccept() {
  const cur = CAPTURE_RESULT;
  if (!cur) return { ok: false };
  const out = (typeof VISION.accept === 'function') ? VISION.accept(cur.value)
    : { ok: false, error: 'Nothing is built to take this yet.' };
  if (out && out.ok) { CAPTURE_RESULT = null; renderCaptureResult(); }
  else if (out && out.error) toast(out.error);
  return out || { ok: false };
}
// A generic, escaped readout of the validated value. The identification slice
// replaces it with the identity question; it exists so the success state has a
// body that can be measured.
function resultReadoutHTML(value) {
  const v = (value && typeof value === 'object' && !Array.isArray(value)) ? value : { value: value };
  return Object.keys(v).map(function (k) {
    const x = v[k];
    const s = (x != null && typeof x === 'object') ? JSON.stringify(x) : String(x);
    return `<div class="kv"><span class="k">${esc(k)}</span><span class="v">${esc(s)}</span></div>`;
  }).join('');
}
function renderCaptureResult() {
  // HT-D51: EVERY exit repaints the modal, including the one that clears the
  // result -- otherwise it stays open around nothing.
  try {
    const el = document.getElementById('captureResult');
    if (el) {
      // The CONTRACT owns the success body (R1: the identity question). The
      // generic readout stays as the fallback for a contract that ships no
      // renderer -- the gates' synthetic contract uses it, which is what keeps
      // the chain provably contract-agnostic. A renderer escapes its own values.
      const body = !CAPTURE_RESULT ? ''
        : ((VISION && typeof VISION.render === 'function')
            ? VISION.render(CAPTURE_RESULT.value)
            : resultReadoutHTML(CAPTURE_RESULT.value));
      el.innerHTML = CAPTURE_RESULT ? `<div class="cresult">${body}</div>` : '';
    }
  } finally { try { renderCaptureOutcome(); } catch (e) {} }
}

// ---- HT-D51: the capture outcome is explicit, central and MODAL -------------
// Every capture ends in exactly ONE of three states, and that state owns the
// screen. HealthTracker's result once rendered inline below two textareas, off a
// phone's screen, and the first workaround painted it in a SECOND place. Two
// surfaces telling one story is not the fix for one being off-screen; a surface
// that cannot be off-screen is. The states are exclusive BY CONSTRUCTION.
function captureOutcomeState() {
  // A result outranks a stale busy line: the answer arrived.
  if (CAPTURE_RESULT) return 'success';
  if (BYOK_BUSY && BYOK_BUSY.phase === 'sending') return 'pending';
  if (BYOK_BUSY && BYOK_BUSY.phase === 'error') return 'error';
  return 'none';
}
// Only FAILURE is dismissable. A success must be answered -- a result dismissed
// by a stray tap on the scrim is silently thrown away. Pending has a cancel,
// which says what it does.
function captureOutcomeDismiss() {
  if (captureOutcomeState() !== 'error') return { ok: false, kind: 'not-dismissable' };
  byokBusy(null);
  return { ok: true };
}
// "Try again" re-opens the picker rather than replaying the photo: the image is
// held in memory FOR THE CALL ONLY (HT-D45), and keeping it alive across a
// failure would stretch that bound for convenience. HT-D51 left the replay as an
// open hygiene option; it is not taken here either.
function captureRetry() {
  byokBusy(null);
  const inp = document.getElementById('captureFile');
  if (!inp) return { ok: false, error: 'no capture input' };
  try { inp.click(); } catch (e) { return { ok: false, error: 'picker unavailable' }; }
  return { ok: true };
}
// The floor under every failure: the reply box, which holds the raw reply when
// one arrived (HT-D64).
function capturePasteInstead() {
  byokBusy(null);
  const box = document.getElementById('replyBox');
  if (box) { try { box.focus(); box.scrollIntoView({ block: 'center' }); } catch (e) {} }
  return { ok: true };
}
function renderCaptureOutcome() {
  const wrap = document.getElementById('captureOutcome');
  const scrim = document.getElementById('outcomeScrim');
  const title = document.getElementById('outcomeTitle');
  const msg = document.getElementById('outcomeMsg');
  const foot = document.getElementById('outcomeFoot');
  const x = document.getElementById('outcomeX');
  if (!wrap || !title || !msg || !foot) return;
  const st = captureOutcomeState();
  if (st === 'none') {
    wrap.style.display = 'none';
    if (scrim) scrim.style.display = 'none';
    msg.innerHTML = '';
    foot.innerHTML = '';
    return;
  }
  wrap.style.display = 'flex';
  if (scrim) scrim.style.display = 'block';
  if (x) x.style.display = (st === 'error') ? '' : 'none';
  const busyMsg = BYOK_BUSY ? String(BYOK_BUSY.message || '') : '';
  // HT-D65: WHERE THE TIME WENT, on the surface the finger is on -- on success
  // as well as failure, or a working run cannot be compared against a broken one.
  const traceTxt = byokTraceLine();
  const traceHTML = traceTxt ? `<div class="otrace">${esc(traceTxt)}</div>` : '';
  if (st === 'success') {
    title.textContent = 'Reply read — check it before using it';
    msg.innerHTML = traceHTML;
    foot.innerHTML =
      `<button class="btn primary" onclick="captureAccept()">${esc((VISION && VISION.acceptLabel) || 'Use this')}</button>` +
      `<button class="btn" onclick="captureDiscard()">Discard</button>`;
  } else if (st === 'pending') {
    title.textContent = 'Reading your photo';
    msg.innerHTML = `<div class="opend"><span class="byokspin"></span>${esc(busyMsg)}</div>` +
      `<div class="osub">The photo is sent once, to the provider you configured. Nothing else is sent, ` +
      `and the photo is never stored.</div>` + traceHTML;
    foot.innerHTML = `<button class="btn" onclick="byokCancel()">Cancel</button>`;
  } else {
    title.textContent = 'That did not work';
    msg.innerHTML = traceHTML + `<div class="omsg obad">${esc(busyMsg)}</div>` +
      `<div class="osub">Your photo is still on your phone. Trying again opens the picker so you can ` +
      `choose it once more.</div>`;
    foot.innerHTML =
      `<button class="btn primary" onclick="captureRetry()">Try again</button>` +
      `<button class="btn" onclick="capturePasteInstead()">Paste the reply by hand</button>`;
  }
}

// ---- the capture flow -------------------------------------------------------
let BYOK_BUSY = null;                        // {phase, message} | null
function byokBusyState() { return BYOK_BUSY; }
function byokBusyClear() { byokBusy(null); }
// HT-D65: the capture TRACE. console.info is unreachable on a phone, and a number
// nobody can read is not instrumentation. The split that matters is TIME TO FIRST
// BYTE vs BODY: a long TTFB is the model thinking, a long body is it writing, and
// those have opposite fixes.
let BYOK_TRACE = null;
function byokTraceReset() { BYOK_TRACE = { t0: nowMs(), attempts: [] }; return BYOK_TRACE; }
function byokTrace() { return BYOK_TRACE; }
function byokTraceNote(k, v) { if (BYOK_TRACE) BYOK_TRACE[k] = v; }
function byokTraceAttempt(a) { if (BYOK_TRACE) BYOK_TRACE.attempts.push(a); return a; }
const kb = function (n) { return n >= 1048576 ? (n / 1048576).toFixed(1) + ' MB' : Math.round(n / 1024) + ' kB'; };
const secs = function (ms) { return (ms / 1000).toFixed(1) + 's'; };
function byokTraceLine() {
  const t = BYOK_TRACE;
  if (!t || !t.attempts.length && !t.bytes) return '';
  const bits = [];
  if (t.bytes) bits.push(kb(t.bytes) + (t.w ? ' · ' + t.w + '×' + t.h : '') + ' · encode ' + secs(t.decodeMs || 0));
  t.attempts.forEach(function (a, i) {
    const parts = ['call ' + (i + 1)];
    if (a.ttfbMs != null) parts.push('first byte ' + secs(a.ttfbMs));
    if (a.totalMs != null) parts.push('done ' + secs(a.totalMs));
    if (a.status) parts.push('HTTP ' + a.status);
    if (a.outcome) parts.push(a.outcome);
    parts.push(a.jsonMode ? 'json_object sent' : 'no json_object');
    // HT-D66: the effort actually sent, so a changed first-byte time is attributable.
    parts.push(a.effort ? ('effort ' + a.effort) : 'effort default');
    bits.push(parts.join(' · '));
  });
  bits.push('total ' + secs(nowMs() - t.t0));
  return bits.join('  |  ');
}
// HT-D48: a long wait must look alive. The elapsed seconds tick on screen.
let BYOK_TICK = null;
function byokStopTick() { if (BYOK_TICK) { clearInterval(BYOK_TICK); BYOK_TICK = null; } }
function byokStartTick(label) {
  byokStopTick();
  const t0 = nowMs();
  byokBusy('sending', label + ' 0s');
  BYOK_TICK = setInterval(function () {
    if (!BYOK_BUSY || BYOK_BUSY.phase !== 'sending') { byokStopTick(); return; }
    byokBusy('sending', label + ' ' + Math.round((nowMs() - t0) / 1000) + 's');
  }, 1000);
}
// One live accessor: exporting the `let`s would freeze their value at load.
function byokTimeouts() {
  return { call: CALL_TIMEOUT_MS, test: TEST_TIMEOUT_MS, decode: BYOK_DECODE_TIMEOUT_MS, lease: BYOK_BITMAP_LEASE_MS };
}
function byokCancel() {
  EGRESS_CANCELLED = true;
  try { if (EGRESS_INFLIGHT) EGRESS_INFLIGHT.abort(); } catch (e) {}
  byokStopTick();
  byokBusy('error', 'Cancelled. The photo is still on your phone — capture again when you are ready.');
  return { ok: false, kind: 'cancelled' };
}
function byokBusy(phase, message) {
  BYOK_BUSY = phase ? { phase: phase, message: message || '' } : null;
  try { renderCaptureOutcome(); } catch (e) {}
  try { renderCaptureBtn(); } catch (e) {}
}
// HT-D49: a capture is a verdict on the key as much as a test ping is. A reply
// VERIFIES it; only an `auth` rejection FAILS it. A timeout, a rate limit or a
// malformed body say nothing about the key and must never demote it.
function byokNoteVerdict(r) {
  if (!r) return r;
  if (r.ok) credSetStatus('vision', 'verified', '');
  else if (r.kind === 'auth') credSetStatus('vision', 'failed', String(r.error || ''));
  return r;
}
// HT-D64: below this, a retry is not worth starting -- it would report a timeout
// for a parse failure that already happened, and bill a second call to say so.
const BYOK_RETRY_MIN_MS = 30000;
// Attempts are logged by stage and size only -- NEVER the key, the URL or the body.
function byokLog(line) { try { if (window.console && console.info) console.info('[capture] ' + line); } catch (e) {} }

// Runs only from an explicit capture-send (D1).
function byokCapture(file, source) {
  // No contract, no call. Guarded here as well as on the surface, because a
  // surface that hides a button is not a guarantee.
  if (!visionReady()) {
    byokBusy('error', 'Identification is not built yet, so a photo has nothing to be read against. Nothing was sent.');
    return Promise.resolve({ ok: false, kind: 'contract' });
  }
  // HealthTracker returned SILENTLY here, safe only because its buttons never
  // render without a key. HT-D47's bar is "never in nothing", so this paints.
  if (!credConfigured('vision')) {
    byokBusy('error', 'No vision key saved. Add your key in Settings, then capture again.');
    return Promise.resolve({ ok: false, kind: 'config', error: 'No key saved.' });
  }
  const cap = credCap('vision');
  if (cap.exhausted) {
    byokBusy('error', 'Daily cap reached (' + cap.cap + '). Raise it in Settings, or try tomorrow.');
    return Promise.resolve({ ok: false, kind: 'cap' });
  }
  byokBusy('sending', 'Reading the photo…');
  const capT0 = nowMs();                 // HT-D64: the retry must know what it has left
  byokTraceReset();                      // HT-D65: one trace per capture
  byokLog('source=' + (source === 'library' ? 'library' : 'camera') +
          ' type=' + String((file && file.type) || '?') + ' bytes=' + Number((file && file.size) || 0));
  return byokDownscale(file, source).then(function (img) {
    // HT-D65: the payload the provider actually receives, not the target it was
    // aimed at. base64 inflates by 4/3, and that is what crosses the wire.
    byokTraceNote('decodeMs', nowMs() - capT0);
    byokTraceNote('bytes', String(img.dataUrl || '').length);
    byokTraceNote('w', img.w); byokTraceNote('h', img.h);
    byokStartTick('Sending to your provider…');
    credCount('vision');
    return visionCall(img.dataUrl, {}).then(byokNoteVerdict).then(function (r1) {
      if (r1.ok) {
        const d1 = openCaptureResult(r1.text);
        if (d1.ok) { byokStopTick(); byokBusy(null); return { ok: true, source: 'call', attempts: 1 }; }
        // RETRY ONCE, and only for a malformed BODY: a rejected key or a dead
        // network fails the same way twice. AND ONLY WITH BUDGET LEFT (HT-D64):
        // a slow first attempt plus a full second one reported a TIMEOUT for what
        // was a PARSE failure -- a symptom naming the wrong cause.
        byokLog('reply did not validate (' + String(r1.text || '').length + ' chars); ' +
                Math.round((nowMs() - capT0) / 1000) + 's spent');
        const left = CALL_TIMEOUT_MS - (nowMs() - capT0);
        if (left < BYOK_RETRY_MIN_MS)
          return byokFallback(r1.text, 'The reply did not match, and too little time was left to ask again.');
        byokStartTick('That reply did not match. Asking once more…');
        credCount('vision');
        return visionCall(img.dataUrl, { budget: left }).then(byokNoteVerdict).then(function (r2) {
          if (r2.ok) {
            const d2 = openCaptureResult(r2.text);
            if (d2.ok) { byokStopTick(); byokBusy(null); return { ok: true, source: 'call', attempts: 2 }; }
            return byokFallback(r2.text, 'The reply did not match twice.');
          }
          // HT-D64: THE FIRST REPLY IS NOT THROWN AWAY. It arrived, it was paid
          // for, and it is the only thing the user can act on.
          return byokFallback(r1.text, String(r2.error || '') +
            ' The first reply did not match, but it is what the model sent.');
        });
      }
      return byokFallback('', r1.error);
    });
  }).catch(function (e) {
    return byokFallback('', (e && e.message) || 'The photo could not be prepared.');
  });
}
// NEVER A DEAD END. Whatever failed, the raw reply (when there is one) lands in
// the reply box, and the failure is stated where the finger is.
function byokFallback(raw, message) {
  byokStopTick();
  const box = document.getElementById('replyBox');
  if (box && raw) box.value = String(raw);
  byokBusy('error', String(message || 'That did not work.') + (raw ? ' What the model sent is in the reply box.' : ''));
  return { ok: false, kind: 'fallback', fellBack: true, hasRaw: !!raw };
}
// HT-D58: the source is DERIVED FROM THE INPUT THAT FIRED. The `capture`
// attribute is what forces the camera, so its presence IS the fact; a second
// argument in the markup could disagree with it.
function captureSourceOf(input) {
  return (input && input.hasAttribute && input.hasAttribute('capture')) ? 'camera' : 'library';
}
// HT-D47: the instant a photo comes back, SOMETHING is on screen, and the input
// is cleared only AFTER the read -- on iOS clearing it first can invalidate the
// very File it just handed over.
function onCaptureFile(input) {
  const source = captureSourceOf(input);
  const f = input && input.files && input.files[0];
  if (!f) {
    // A cancelled library picker is the ordinary way to change your mind, and
    // must not read as a camera fault (HT-D58).
    byokBusy('error', source === 'library'
      ? 'No photo was chosen. Pick one, or take a photo instead.'
      : 'No photo came back from the camera. Try again.');
    byokLog('the input delivered no file (source=' + source + ')');
    return { ok: false, kind: 'nofile', source: source };
  }
  byokBusy('sending', 'Reading the photo…');
  const done = function (r) { if (input) { try { input.value = ''; } catch (e) {} } return r; };
  return byokCapture(f, source).then(done, function (e) {
    done();
    byokFallback('', 'Reading the photo failed: ' + String((e && e.message) || e).slice(0, 140));
    return { ok: false, kind: 'threw' };
  });
}

// ---- the decode chain (HT-D47, HT-D58) --------------------------------------
// Downscale for the wire ONLY: no record, no store, no export ever holds an image.
//
// HT-D47 -- CAPTURE DID NOTHING ON THE DEVICE, and "used today: 0" was the tell:
// the counter increments AFTER the decode, so the decode never finished. A plain
// `new Image()` on an object URL has three ways to fail QUIETLY on a phone:
//   * neither onload NOR onerror fires -- so the decode is BOUNDED by a timeout;
//   * a 12 MP photo blows iOS Safari's canvas limit and drawImage yields a BLANK
//     canvas with no exception -- so createImageBitmap resizes without the
//     full-size allocation, and the output is sanity-checked (BYOK_MIN_DATAURL);
//   * an HEIC frame decodes nowhere in a browser -- so that is NAMED.
// Every one of those ends in a MESSAGE, never in nothing.
const BYOK_MAX_EDGE = 1280;                  // HT-D45 Fork D: latency binds long before 20 MiB does
const BYOK_JPEG_Q = 0.8;
let BYOK_DECODE_TIMEOUT_MS = 20000;
// THE LEASH. The preferred decoder gets 5 seconds before the fallback takes over.
// Not hypothetical: HealthTracker's first build without it HUNG THE HARNESS exactly
// the way the button hung the device. Do not remove it (HT-D47).
let BYOK_BITMAP_LEASE_MS = 5000;
function setByokBitmapLease(ms) { BYOK_BITMAP_LEASE_MS = (Number(ms) > 0) ? Number(ms) : 5000; }
function setByokDecodeTimeout(ms) { BYOK_DECODE_TIMEOUT_MS = (Number(ms) > 0) ? Number(ms) : 20000; }
const BYOK_MIN_DATAURL = 2048;               // a blank/failed canvas encodes to almost nothing
function byokBounds(w, h) {
  const long = Math.max(w, h) || 1;
  const scale = Math.min(1, BYOK_MAX_EDGE / long);
  return { w: Math.max(1, Math.round(w * scale)), h: Math.max(1, Math.round(h * scale)) };
}
function byokEncode(src, w, h) {
  const b = byokBounds(w, h);
  const c = document.createElement('canvas');
  c.width = b.w; c.height = b.h;
  const ctx = c.getContext('2d');
  if (!ctx) throw new Error('This browser would not give a drawing context.');
  ctx.drawImage(src, 0, 0, b.w, b.h);
  const out = c.toDataURL('image/jpeg', BYOK_JPEG_Q);
  // iOS can hand back a BLANK canvas rather than throwing. Checked, not trusted.
  if (!out || out.indexOf('data:image/jpeg') !== 0 || out.length < BYOK_MIN_DATAURL)
    throw new Error('The photo encoded to nothing — it may be too large for this browser.');
  return { dataUrl: out, w: b.w, h: b.h };
}
// Preferred: createImageBitmap resizes during decode, so a 12 MP photo never
// becomes a 12 MP bitmap in memory. ONE decode; drawImage does the scaling.
// HT-D58: `imageOrientation` is PINNED ON THE CALL. The default has moved (spec
// said "none", now "from-image", and "none" was folded in), so the answer is a
// browser-version fact rather than a contract, and a library photo carries EXIF
// far more often than a fresh camera frame. A browser too old for the option
// still degrades correctly: any bitmap failure falls to byokDecodeImage.
function byokDecodeBitmap(file) {
  if (typeof createImageBitmap !== 'function') return Promise.reject(new Error('no createImageBitmap'));
  return createImageBitmap(file, { imageOrientation: 'from-image' }).then(function (bmp) {
    try { const out = byokEncode(bmp, bmp.width, bmp.height); try { bmp.close(); } catch (e) {} return out; }
    catch (e) { try { bmp.close(); } catch (e2) {} throw e; }
  });
}
function byokDecodeImage(file) {
  return new Promise(function (resolve, reject) {
    const url = URL.createObjectURL(file);
    const img = new Image();
    const done = function (fn, arg) { try { URL.revokeObjectURL(url); } catch (e) {} fn(arg); };
    img.onload = function () {
      try { done(resolve, byokEncode(img, img.naturalWidth || img.width, img.naturalHeight || img.height)); }
      catch (e) { done(reject, e); }
    };
    img.onerror = function () { done(reject, new Error('This browser could not decode that image.')); };
    img.src = url;
  });
}
// HT-D58: the HEIC advice depends on WHERE the photo came from. A camera setting
// fixes the NEXT photo; it does nothing for one already in the library.
function byokHeicMessage(source) {
  return source === 'library'
    ? 'That photo is in HEIC, which browsers cannot read. Share or re-save it as a JPEG first.'
    : 'That photo is in HEIC, which browsers cannot read. Set the camera to "Most Compatible" and take it again.';
}
function byokDownscale(file, source) {
  const type = String((file && file.type) || '').toLowerCase();
  const heic = /heic|heif/.test(type) || /\.hei[cf]$/i.test(String((file && file.name) || ''));
  let timer = null;
  const bounded = new Promise(function (_, reject) {
    timer = setTimeout(function () {
      reject(new Error(heic ? byokHeicMessage(source)
        : 'Reading the photo timed out after ' + (BYOK_DECODE_TIMEOUT_MS / 1000) + ' seconds.'));
    }, BYOK_DECODE_TIMEOUT_MS);
  });
  // Bitmap first, on a SHORT LEASH (see BYOK_BITMAP_LEASE_MS above).
  const leash = new Promise(function (_, reject) {
    setTimeout(function () { reject(new Error('bitmap decode did not answer in time')); }, BYOK_BITMAP_LEASE_MS);
  });
  const work = Promise.race([byokDecodeBitmap(file), leash])
    .catch(function () { return byokDecodeImage(file); })
    .catch(function (e) {
      if (heic) throw new Error(byokHeicMessage(source));
      throw e;
    });
  return Promise.race([work, bounded]).then(function (r) {
    clearTimeout(timer); return r;
  }, function (e) { clearTimeout(timer); throw e; });
}

// ---- the vision call (HT-D45, HT-D64, HT-D66) -------------------------------
// Verified by HealthTracker against the live API 2026-09-04: OpenAI-CLASSIC
// content parts on /chat/completions. The input_image shape in xAI's image guide
// is the Responses API's and is REJECTED here.
const BYOK_MAX_TOKENS = 2048;   // HT-D64: an essay is not only unparseable, it is SLOW
// The capabilities sent on THIS attempt: declarations minus whatever a previous
// 400 said the provider refuses. TWO independent flags (HT-D66), so refusing one
// field never silently costs the other.
function visionCaps(row, o) {
  if (!row) return null;
  return { jsonMode: !!row.jsonMode && !(o && o.noJsonMode),
           reasoningEffort: (o && o.noEffort) ? null : (row.reasoningEffort || null) };
}
function visionBody(dataUrl, text, model, caps) {
  const b = { model: model, messages: [{ role: 'user', content: [
    { type: 'image_url', image_url: { url: dataUrl } },
    { type: 'text', text: text },
  ] }] };
  if (caps && caps.jsonMode) b.response_format = { type: 'json_object' };   // a constraint, not a request
  if (caps && caps.reasoningEffort) b.reasoning_effort = caps.reasoningEffort;
  b.max_tokens = BYOK_MAX_TOKENS;
  return b;
}
function visionCall(dataUrl, opts) {
  const s = credSettings('vision');
  const row = PROVIDERS[s.provider];
  if (!row) return Promise.resolve(errOf('config', 'No provider configured.'));
  const o = opts || {};
  const caps = visionCaps(row, o);
  const body = o.ping
    ? { model: row.model, messages: [{ role: 'user', content: 'ping' }], max_tokens: 1 }
    : visionBody(dataUrl, visionPrefix() + VISION.prompt, row.model, caps);
  // The ping is bounded by the test's own race, so its abort must not sit behind it.
  const budget = o.ping ? TEST_TIMEOUT_MS : (Number(o.budget) > 0 ? Number(o.budget) : CALL_TIMEOUT_MS);
  // HT-D65: per-attempt timing, for the CAPTURE call only.
  const att = o.ping ? null : byokTraceAttempt({ jsonMode: !!(caps && caps.jsonMode), effort: (caps && caps.reasoningEffort) || null });
  return egress('vision', { path: '/chat/completions', method: 'POST', json: body, budget: budget, attempt: att }).then(function (t) {
    if (!t.transport) return t;
    // HT-D46: xAI answers a bad key with 400, not 401, so the provider's words
    // are read as well as the status.
    const pmsg = providerMessage(t.raw, s.key);
    if (t.status === 401 || t.status === 403 || (t.status === 400 && /api key|unauthor|credential/i.test(pmsg)))
      return errOf('auth', pmsg || 'The provider rejected the key. Check it in Settings.');
    if (t.status === 429)
      return errOf('ratelimit', 'The provider is rate-limiting. Wait a moment and try again.');
    // HT-D64 / HT-D66: a provider that rejects an optional field must not cost
    // the capture. Retried ONCE without the field it NAMED; a generic refusal
    // strips both at once, so the worst case is two calls, never three.
    if (!t.httpOk && t.status === 400 && !(o.noJsonMode && o.noEffort)) {
      const wantsEffort = /reasoning[_ ]?effort|reasoning/i.test(pmsg) && !o.noEffort;
      const wantsJson = /response_format|json_object/i.test(pmsg) && !o.noJsonMode;
      const generic = !wantsEffort && !wantsJson && /unknown|unsupported|unrecognized|not supported/i.test(pmsg);
      if (wantsEffort || wantsJson || generic) {
        const drop = Object.assign({}, o, { budget: budget });
        if (wantsEffort || generic) drop.noEffort = true;
        if (wantsJson || generic) drop.noJsonMode = true;
        const dropped = [drop.noEffort && !o.noEffort ? 'reasoning_effort' : null,
                         drop.noJsonMode && !o.noJsonMode ? 'response_format' : null].filter(Boolean).join(' + ');
        if (att) att.outcome = dropped + ' REFUSED, retried without';
        return visionCall(dataUrl, drop);
      }
    }
    if (!t.httpOk) return errOf('http', 'The provider returned ' + t.status + '. ' + pmsg);
    let j; try { j = JSON.parse(t.raw); } catch (e) { return errOf('malformed', 'The reply was not JSON.'); }
    const msg = j && j.choices && j.choices[0] && j.choices[0].message;
    const content = msg && (typeof msg.content === 'string' ? msg.content
      : (Array.isArray(msg.content) ? msg.content.map((c) => c && c.text ? c.text : '').join('') : ''));
    if (!content) return errOf('malformed', 'The reply carried no content.');
    if (att) att.outcome = 'reply ' + content.length + ' chars';
    return { ok: true, text: content };
  });
}

// ---- the prices role: Test connection only (D1) -----------------------------
// No price feature exists. The ping is the one call the settings surface needs.
// VERIFIED 2026-09-11 from the docs: `status: success|error`, `error-message`.
// NOT verified (no token here): a comics subscription's success body, and the
// wrong-token wording -- which is what this button exists to show on the device.
const PRICES_PING_QUERY = 'batman';
function pricesPing() {
  const s = credSettings('prices');
  return egress('prices', { path: '/api/products', query: { q: PRICES_PING_QUERY }, budget: TEST_TIMEOUT_MS }).then(function (t) {
    if (!t.transport) return t;
    let j = null; try { j = JSON.parse(t.raw); } catch (e) {}
    if (t.httpOk && j && j.status === 'success') return { ok: true, text: '' };
    const pmsg = providerMessage(t.raw, s.key);
    if (t.status === 401 || t.status === 403 || /token|subscription|unauthor|permission/i.test(pmsg))
      return errOf('auth', pmsg || 'The price guide rejected the token. Check it in Settings.');
    if (t.status === 429) return errOf('ratelimit', 'The price guide is rate-limiting. Wait before trying again.');
    if (!j) return errOf('malformed', 'The price guide did not answer with JSON.');
    return errOf('http', 'The price guide returned ' + t.status + '. ' + pmsg);
  });
}

// ---- Test connection: EVERY EXIT PAINTS (HT-D46) ----------------------------
// HealthTracker's button was silent on the device through three defects: no
// .catch, a disabled button, no distinct timeout. The fix is one rule.
let CRED_STATE = { vision: null, prices: null };
function credPaint(role, phase, ok, message) {
  CRED_STATE[role] = { phase: phase, ok: !!ok, message: String(message || '') };
  try { renderCred(role); } catch (e) {}          // a render fault must not eat the state
  try { renderCaptureBtn(); } catch (e) {}
  return { ok: !!ok, state: phase, message: CRED_STATE[role].message };
}
function credTest(role) {
  let secret = '';
  try {
    const s = credSettings(role);
    secret = s.key;
    const row = PROVIDERS[s.provider];
    // A row with auth 'none' needs no credential (D1: the server move), so it must
    // be testable with none saved -- or the config change could not be verified.
    if (row && row.auth !== 'none' && !s.key)
      return Promise.resolve(credPaint(role, 'tested', false, 'Nothing saved. Paste it above, tap Save, then test.'));
    credPaint(role, 'testing', false, 'Testing — calling ' + (row ? row.label : s.provider) + '…');
    byokLog('test: role=' + role + ' provider=' + s.provider);
    let settled = false;
    const race = new Promise(function (resolve) {
      setTimeout(function () {
        if (!settled) resolve(credPaint(role, 'tested', false, 'No answer in ' + (TEST_TIMEOUT_MS / 1000) +
          ' seconds. The provider may be slow or unreachable.'));
      }, TEST_TIMEOUT_MS);
    });
    // DISPATCH BY ROLE, not by "vision or the other one". A two-role ternary sent
    // the THIRD role's token to PriceCharting as a `t=` URL parameter -- a dead
    // test and a credential handed to the wrong provider in a query string, which
    // is the exact thing D1 forbids. A table is the fix: adding a role must not
    // be able to silently inherit another role's call.
    const PING = { vision: function () { return visionCall(null, { ping: true }); },
                   prices: pricesPing, comps: compsPing };
    const ping = PING[role];
    if (!ping) return Promise.resolve(credPaint(role, 'tested', false,
      'No connection test exists for this role yet.'));
    const call = ping().then(function (r) {
      settled = true;
      credSetStatus(role, r.ok ? 'verified' : 'failed', r.ok ? '' : String(r.error || ''));
      return credPaint(role, 'tested', r.ok, r.ok
        ? ('Connected — ' + (row ? (row.model || row.label) : 'the provider') + ' responded.')
        : String(r.error || 'The call failed.'));
    }).catch(function (e) {
      settled = true;
      credSetStatus(role, 'failed', 'unexpected error');
      return credPaint(role, 'tested', false, 'Something went wrong making the call: ' +
        redact(String((e && e.message) || e), secret).slice(0, 120));
    });
    return Promise.race([call, race]);
  } catch (e) {
    return Promise.resolve(credPaint(role, 'tested', false, 'Could not start the test: ' +
      redact(String((e && e.message) || e), secret).slice(0, 120)));
  }
}

// ---- the settings surface (HT-D45/D46/D49, one card per role) ---------------
// Write-only: what renders is the MASK, never the credential.
function renderCred(role) {
  const el = document.getElementById('credBox-' + role);
  if (!el) return;
  const s = credSettings(role);
  const row = PROVIDERS[s.provider] || {};
  const st0 = s.status;
  const cap = credCap(role);
  const live = CRED_STATE[role];
  const liveHTML = live
    ? `<div class="byoks ${live.phase === 'testing' ? 'byoktesting' : (live.ok ? 'byokok' : 'byokbad')}">` +
      (live.phase === 'testing' ? '<span class="byokspin"></span>' : '') + `${esc(live.message)}</div>`
    : '';
  const storedHTML = (!live && s.key)
    ? `<div class="byoks ${st0.state === 'verified' ? 'byokok' : (st0.state === 'failed' ? 'byokbad' : '')}">` +
      `${esc(credStatusLine(role))}${st0.at ? ' · ' + esc(String(st0.at).slice(0, 10)) : ''}` +
      `${st0.state === 'failed' && st0.message ? ' — ' + esc(st0.message) : ''}</div>`
    : '';
  const opts = Object.keys(PROVIDERS).filter((k) => PROVIDERS[k].role === role).map((k) =>
    `<option value="${esc(k)}"${k === s.provider ? ' selected' : ''}>${esc(PROVIDERS[k].label)}</option>`).join('');
  // The noun comes from the ROW, not from the auth mechanism. Keyed to
  // `auth === 'query'` it labelled the Apify row "API key" while the card summary,
  // ROLE_LABEL and the settings note all said "token" -- a name disagreeing with
  // itself across a seam, which is D3's shape at its smallest.
  const noun = row.noun || (row.auth === 'query' ? 'Token' : 'API key');
  // D1: the extractability warning is SAFETY text, so it is visible, never folded
  // behind a disclosure (HT-D53: provenance may hide, safety may not).
  //
  // KEYED TO THE ROW, NOT TO A ROLE NAME. Gated on `role === 'prices'`, the comps
  // token -- which can SPEND, not merely subscribe -- rendered no warning at all.
  // A credential's cost is a property of the provider, so the provider declares it.
  const warn = row.warn
    ? `<div class="note warnline">${esc(row.warn)}</div>`
    : '';
  el.innerHTML =
    `<div class="row"><div><label>Provider</label><select id="credProv-${role}">${opts}</select></div>` +
    (cap.capped ? `<div><label>Daily cap</label><input id="credCap-${role}" type="number" inputmode="numeric" min="1" value="${esc(s.cap)}"></div>` : '') +
    `</div>` +
    `<label>${esc(noun)}${s.key ? ' <small>(saved: ' + esc(credMask(role)) + ')</small>' : ''}</label>` +
    `<input id="credKey-${role}" type="password" autocomplete="off" placeholder="${s.key ? 'Enter a new one to replace it' : 'Paste it here'}">` +
    `<div class="row btnrow">` +
    `<button class="btn primary" onclick="saveCred('${role}')">Save</button>` +
    `<button class="btn" onclick="credTest('${role}')">Test connection</button>` +
    `<button class="btn" onclick="credClear('${role}')"${s.key ? '' : ' disabled'}>Remove</button></div>` +
    liveHTML + storedHTML + warn +
    (cap.capped ? `<div class="note">Used today: ${esc(cap.used)} of ${esc(cap.cap)}.</div>` : '') +
    citeBlock('How this is handled',
      `<small class="fine">Stored on this device only, in its own place outside your data — never included in an export or a backup. ` +
      `Sent only to ${esc(row.label || 'its provider')}, and only when you ${role === 'vision' ? 'send a photo' : 'look something up'} or tap Test connection.` +
      `${row.auth === 'query' ? ' It travels inside the request address, which is how ' + esc(row.label) + ' requires it.' : ''}</small>`);
}
function saveCred(role) {
  const k = document.getElementById('credKey-' + role);
  const pv = document.getElementById('credProv-' + role);
  const cp = document.getElementById('credCap-' + role);
  const r = credSave(role, pv ? pv.value : null, (k && k.value) ? k.value : null, cp ? cp.value : null);
  if (k) k.value = '';                        // never leave it in the DOM
  if (r.blocked) { CRED_STATE[role] = { phase: 'tested', ok: false, message: r.message }; renderCred(role); return r; }
  CRED_STATE[role] = r.stored
    ? (r.warning ? { phase: 'tested', ok: false, message: r.warning } : null)
    : { phase: 'tested', ok: false, message: 'This device would not store it. It will work until you reload, and then be gone.' };
  toast(r.stored ? (r.configured ? 'Saved on this device' : 'Settings saved') : 'Could not store it');
  renderCred(role);
  return r;
}
// The capture surface. The outcome is NOT painted here (HT-D51): a second copy
// would BE a second outcome state. The key status IS here, and it is never
// stated without an offer to settle it on the spot (HT-D49), and never a gate.
function renderCaptureBtn() {
  const el = document.getElementById('captureBox');
  if (!el) return;
  if (!visionReady()) {
    el.innerHTML = `<div class="note">Identification is not built yet, so there is nothing to send a photo for. ` +
      `This is the capture scaffolding it will use.</div>`;
    return;
  }
  const stC = credSettings('vision').status;
  const live = CRED_STATE.vision;
  const testingC = (live && live.phase === 'testing')
    ? `<div class="byoks byoktesting"><span class="byokspin"></span>${esc(live.message)}</div>` : '';
  const verifyC = (stC.state === 'verified') ? ''
    : ` <button type="button" class="linklike" onclick="credTest('vision')">verify now</button>`;
  el.innerHTML = testingC + (credConfigured('vision')
    ? `<div class="caprow">` +
      `<button class="btn primary" onclick="document.getElementById('captureFile').click()">Take photo</button>` +
      `<button class="btn" onclick="document.getElementById('captureLib').click()">Choose photo</button>` +
      `</div>` +
      (testingC ? '' :
        `<div class="byoks ${stC.state === 'verified' ? 'byokok' : (stC.state === 'failed' ? 'byokbad' : '')}">` +
        `key ${esc(credStatusLine('vision'))}${verifyC}</div>`) +
      `<div class="note">Take one now, or choose one you already have. One call to your provider with the photo. Nothing else is sent.</div>`
    // D2 Fork G1: without a key there is still a route, and it is named here
    // rather than left to be discovered.
    : `<div class="note">No vision key saved. Add one in Settings to send a photo — or use the prompt below with your own AI assistant and paste its reply back.</div>`);
}

// ---- R1 / D2: THE IDENTIFICATION CONTRACT -----------------------------------
// The model READS THE COVER; the human confirms it. Nothing here prices, grades,
// or saves anything: R1 ends at a confirmed identity and the query it implies
// (D2 Fork A1), and it is a MILESTONE, NOT A RELEASE -- a seam with a confirmed
// reading on one side and nothing on the other.
//
// What may come back is what a photograph can show. What may NOT -- what the book
// is worth, any market or guide value, a grade, or whether it is a key issue --
// is refused ACTIVELY: detected, counted and SAID, never dropped as a side effect
// (HT-D45 Fork H).
//
// D2 Fork C1 dropped the key-issue field from the brief's own list, and the
// reason is recorded rather than softened: "whether it looks like a key issue" is
// MARKET MEMORY, not a property of the photograph. It is the one field the model
// would recall rather than see, the one most likely to be confidently wrong, and
// the one where being wrong costs money at a table. Dropped, not deferred.
//
// `notes` is deliberately absent too (a deviation from Fork B's sketch, ruled in
// D2): a free-text field is a hole in a structural refusal -- a valuation can
// simply be written into it -- and everything legitimate it could carry is either
// already structured here or is condition information this app refuses by design.
const ID_TEMPLATE_VERSION = 1;
const ID_FIELDS = [
  { key: 'title',       label: 'Title' },
  { key: 'issue',       label: 'Issue' },
  { key: 'publisher',   label: 'Publisher' },
  { key: 'cover_date',  label: 'Cover date', hint: 'as printed' },
  { key: 'cover_price', label: 'Cover price', hint: 'printed on the cover' },
];
const ID_FIELD_KEYS = ID_FIELDS.map((f) => f.key);
// A CLOSED vocabulary, and only what is VISIBLE on a cover (D2 Fork B1).
const ID_MARKERS = ['newsstand', 'direct', 'foil', 'facsimile', 'variant-cover', 'price-variant'];
// Refused BY NAME, on the call path and the paste path alike. `key_issue` is on
// this list because C1 dropped it: a model that volunteers it is answering from
// memory, and the app says so rather than quietly ignoring it.
// R1.1 (D2 amendment): the ASKING PRICE joins the refusal list, with its likely
// spellings. At a flea market the seller's number is often VISIBLE in the photo
// -- a sticker on the bag, a board behind the stack -- so a model can read it off
// the picture and hand back PRICING data through the IDENTIFICATION path. The
// asking price is attested by the person holding the book, never perceived, and
// the two must never be conflated in the record (brief rules 3, 4 and 7).
//
// The failure this closes is SILENT: a sticker price sitting in `cover_price`
// looks exactly like a printed one, nothing downstream can tell them apart, and
// noticing it depends on someone spotting that a 1988 book claims a $5 cover.
//
// `ID_TEMPLATE_VERSION` HOLDS at 1: the field contract does not change, only what
// may fill one of its fields (D2, on HT-D64's distinction).
const ID_REFUSED_KEYS = ['value', 'worth', 'market_value', 'market_price', 'estimate', 'estimated_value',
  'price_estimate', 'nm_price', 'guide_value', 'book_value', 'grade', 'condition', 'grades', 'ladder',
  'key_issue', 'key', 'asking_price', 'sticker_price', 'seller_price', 'sale_price'];
// Absence is a STATE. A model writing "unknown" is saying "not legible" in a form
// that would otherwise travel into a search query, so it is read as absence.
const ID_ABSENT_RE = /^(unknown|n\/a|na|none|not legible|illegible|not visible|\?+|-+)$/i;

const ID_PROMPT =
'You are helping me identify a comic book from a photo of its cover.\n' +
'Reply with JSON ONLY - no prose, no markdown fence, straight quotes only.\n\n' +
'Format:\n' +
'{"title":"<as printed>","issue":"<as printed>","publisher":"<as printed>",' +
'"cover_date":"<as printed>","cover_price":"<as printed>","markers":["<from the list>"]}\n\n' +
'Rules:\n' +
'- Report ONLY what is visible on the cover in this photo.\n' +
'- If something is not legible, LEAVE THAT FIELD OUT. Do not guess, and do not write "unknown".\n' +
'- "issue" and "cover_price" are strings, exactly as printed: "300", "1/2", "$1.00", "75c".\n' +
'- "cover_price" is the price PRINTED ON THE COVER by the publisher. A price on a sticker, a bag, a\n' +
'  label, a board or a shop tag is NOT the cover price: leave it out entirely, and never report what\n' +
'  anyone is asking for the book.\n' +
'- "cover_date" is the date printed on the cover, as printed: "MAY 88".\n' +
'- "markers" may contain only: ' + ID_MARKERS.join(', ') + '. Include one only if the cover\n' +
'  shows it (a UPC barcode box is newsstand; a direct-sales box or diamond is direct). If none are\n' +
'  visible, use [].\n' +
'- Do NOT include what the book is worth, any market or price-guide value, any price other than the\n' +
'  one printed on the cover, any grade or condition assessment, or any judgement about whether it is\n' +
'  a key issue. This app looks prices up itself from the identity you return, and a photograph cannot\n' +
'  show any of those.\n' +
'Nothing else. No commentary.\n' +
'Your entire reply must start with { and end with }.';

// Adjacent sample that obeys the template, run through the REAL parser by a gate,
// so the two cannot drift apart (HT-D11).
const ID_SAMPLE = '{"title":"The Amazing Spider-Man","issue":"300","publisher":"Marvel",' +
  '"cover_date":"MAY 88","cover_price":"$1.00","markers":["newsstand"]}';

function parseIdentity(raw) {
  const text = cleanJSON(raw);
  if (!text) return { ok: false, error: 'Nothing to read.' };
  let o;
  try { o = JSON.parse(text); } catch (e) { return { ok: false, error: 'Bad JSON: ' + e.message }; }
  if (!o || typeof o !== 'object' || Array.isArray(o))
    return { ok: false, error: 'Expected the identification JSON object from the template.' };
  // The refusal happens FIRST, and it counts. A value that is merely absent from
  // the output was never refused -- it was dropped, which is the distinction
  // HT-D45 Fork H exists to keep.
  let refused = 0;
  ID_REFUSED_KEYS.forEach(function (k) { if (Object.prototype.hasOwnProperty.call(o, k)) refused++; });
  const fields = {};
  ID_FIELD_KEYS.forEach(function (k) {
    const v = (o[k] == null) ? '' : String(o[k]).trim();
    if (v && !ID_ABSENT_RE.test(v)) fields[k] = v;
  });
  const markers = [];
  let droppedMarkers = 0;
  (Array.isArray(o.markers) ? o.markers : []).forEach(function (m) {
    const s = String(m == null ? '' : m).trim().toLowerCase();
    if (!s) return;
    if (ID_MARKERS.indexOf(s) >= 0) { if (markers.indexOf(s) < 0) markers.push(s); }
    else droppedMarkers++;
  });
  if (!Object.keys(fields).length)
    return { ok: false, error: 'Nothing legible came back — there is no identity to confirm.' };
  return { ok: true, value: {
    fields: fields, markers: markers,
    // The model's originals, kept beside the accepted values (HT-D55/D57's
    // correction-loop shape): a correction never erases what was read.
    ai: { fields: JSON.parse(JSON.stringify(fields)), markers: markers.slice() },
    refused: refused, droppedMarkers: droppedMarkers,
  } };
}

// The query R2 will send, derived from the CONFIRMED fields -- never from the
// model's originals, so correcting a misread issue number changes what is
// searched. Title and issue only: publisher and date disambiguate for the human,
// and whether they help the search is R2's probe to answer, not this slice's guess.
function identityQuery(v) {
  const f = (v && v.fields) || {};
  return [f.title, f.issue].filter(Boolean).join(' ').replace(/\s+/g, ' ').trim();
}
function identityValue() { return CAPTURE_RESULT ? CAPTURE_RESULT.value : null; }
function identitySetField(key, raw) {
  const v = identityValue();
  if (!v || ID_FIELD_KEYS.indexOf(key) < 0) return { ok: false };
  const s = String(raw == null ? '' : raw).trim();
  if (s) v.fields[key] = s; else delete v.fields[key];   // clearing restores ABSENT, never ''
  renderConfirmQuery();
  // D15: the flag RE-EVALUATES as the reading is corrected. In place, beside the
  // query line, for the same reason the query line is repainted this way.
  renderWantFlag();
  return { ok: true, query: identityQuery(v) };
}
function identityToggleMarker(m) {
  const v = identityValue();
  if (!v || ID_MARKERS.indexOf(m) < 0) return { ok: false };
  const i = v.markers.indexOf(m);
  if (i >= 0) v.markers.splice(i, 1); else v.markers.push(m);
  renderCaptureResult();
  return { ok: true, markers: v.markers.slice() };
}
// The live query line, repainted without rebuilding the inputs -- retyping a
// title must not cost the caret.
function renderConfirmQuery() {
  const el = document.getElementById('idQueryLive');
  const v = identityValue();
  if (el && v) el.textContent = identityQuery(v) || '(nothing to search for yet)';
}
// IDENTITY FIRST (D2, and HT-R30's rule): the question is what this IS. There is
// no grade control and no market value anywhere in here -- the cover price is
// present because it is PRINTED ON THE COVER, and it is labelled as such.
// R1.2: the issue is stored AS PRINTED (D2 Fork B1), so a cover that prints "#2"
// comes back as "#2". The header adds a # for the covers that print a bare "2" --
// and must not add a second one. Reported from the first device capture as
// "STAR WARS ##2"; the search string was right, because it never prepends.
// Exactly one leading #, whatever arrives.
function issueLabel(issue) {
  const s = String(issue == null ? '' : issue).trim();
  return s ? s.replace(/^#*/, '#') : '';
}
// ---- D15: the WANT-LIST, a capture-time filter ------------------------------
// NOT a list to browse: a filter that fires on the DRAFT, while the book is in
// your hand. Browsing a list you wrote is what a notes app does; recognising an
// entry in a box you are standing in front of is not.
//
// D15's asymmetry says err toward firing -- a miss means walking past the book
// you wanted, a false hit costs a two-second look. THE BOUND, ruled 2026-09-14:
// false hits do not stay independent. They compound into a flag that gets
// ignored, and an ignored flag turns every later false hit into a MISS. The
// cheap error, repeated, becomes the expensive one. "A flag I learn to ignore is
// worse than no flag" is the limit condition the rule needs to stay true.
//
// SO GENEROSITY IS ABOUT FORMAT, NOT ABOUT WIDENING WHAT COUNTS AS A WANT.
// "The Amazing Spider-Man #129" and "Amazing Spider-Man 129" are one want typed
// twice. A DIFFERENT ISSUE IS A DIFFERENT BOOK: firing on title alone would flag
// every ASM in the box, which is not generosity, it is noise.
//
// TWO OBJECTS, in D4's shape. `raw` is the line the person typed and is what
// every surface shows back; title/issue are the app's working object. The app
// never shows its own normalisation in place of someone's own words.
//
// THE FLAG ASSERTS NOTHING. It is a question put to the person holding the book
// -- which is why it is safe where D8/D10/D13 refuse to claim: precision is owed
// to claims, generosity is owed to questions.
const WANT_MAX = 500;

function wantNormTitle(s) {
  return String(s == null ? '' : s)
    .toLowerCase()
    .replace(/^\s*the\s+/, '')
    .replace(/[^a-z0-9]+/g, ' ')
    .trim();
}
// "007" -> "7", "#2a" -> "2a". Leading zeros and the # are FORMAT.
function wantNormIssue(s) {
  const t = String(s == null ? '' : s).trim().replace(/^#+/, '').trim().toLowerCase();
  const m = /^0*(\d+)\s*([a-z]*)$/.exec(t);
  return m ? m[1] + m[2] : t;
}
// A line with no issue is KEPT (it is the person's own text) but marked
// unmatchable, and the card says how many -- never silently dropped.
function parseWantLine(line) {
  const raw = String(line == null ? '' : line).trim();
  if (!raw) return null;
  const m = /^(.*?)\s*#?\s*([0-9]+[A-Za-z]?)$/.exec(raw);
  const title = m ? wantNormTitle(m[1]) : '';
  if (!m || !title) return { raw, title: '', issue: '', matchable: false };
  return { raw, title, issue: wantNormIssue(m[2]), matchable: true };
}
function parseWants(text) {
  const lines = String(text == null ? '' : text).split(/\r?\n/);
  const out = [];
  for (let i = 0; i < lines.length && out.length < WANT_MAX; i++) {
    const w = parseWantLine(lines[i]);
    if (w) out.push(w);
  }
  return out;
}
function wantsList() {
  const s = APP_STATE && APP_STATE.settings;
  return (s && Array.isArray(s.wants)) ? s.wants : [];
}
// THE FIRST THING THIS APP EVER PERSISTS. Everything before it was memory-only
// or a credential outside the state object (D1). Store.saveState returns FALSE
// on the memory tier, and that answer is carried to the surface rather than
// swallowed: a want that was not saved must not claim it was.
function wantsSave(text) {
  if (!APP_STATE) return { ok: false, saved: 0, unmatchable: 0 };
  if (!APP_STATE.settings || typeof APP_STATE.settings !== 'object') APP_STATE.settings = {};
  const list = parseWants(text);
  APP_STATE.settings.wants = list;
  const ok = Store.saveState(APP_STATE);
  renderWantsCard(); renderBadge(); renderWantFlag();
  return { ok, saved: list.length, unmatchable: list.filter(function (w) { return !w.matchable; }).length };
}
// EXACT after normalisation, not a prefix. Once case, a leading "the" and
// punctuation are gone, "The Amazing Spider-Man" and "Amazing Spider-Man" are
// already identical -- so a prefix rule would buy nothing except firing
// "Amazing Spider-Man" on "Amazing Spider-Man Annual", which is the noise the
// issue-must-match ruling exists to refuse.
function wantMatch(fields) {
  const f = fields || {};
  const t = wantNormTitle(f.title), i = wantNormIssue(f.issue);
  if (!t || !i) return null;
  const list = wantsList();
  for (let n = 0; n < list.length; n++) {
    const w = list[n];
    if (w && w.matchable && w.issue === i && w.title === t) return w;
  }
  return null;
}
// A PROMPT, never a claim -- and it shows the person THEIR line, not ours.
// Nothing here is written to any record: the flag is computed from the draft
// and the list, every time it paints (D15: nothing before confirm).
function wantFlagHTML(v) {
  const w = v ? wantMatch(v.fields) : null;
  if (!w) return '';
  return `<div class="wantflag" role="status">On your want list — take a look: <b>${esc(w.raw)}</b></div>`;
}
// IN PLACE, like renderConfirmQuery. identitySetField deliberately does NOT
// rebuild the draft -- retyping a title must not cost the caret (AK12) -- so a
// flag rendered only by renderIdentityHTML would paint once and then show a
// stale answer to a question the user had already changed.
function renderWantFlag() {
  const el = document.getElementById('wantFlag');
  if (el) el.innerHTML = wantFlagHTML(identityValue());
}
// C1's surface. Test machinery, and the card says so where someone would look.
//
// A THROW IS A RESULT TOO (2026-09-16). This runs from an inline onclick, and a
// phone has no console: an exception here is visible nowhere unless the card
// shows it.
function replaySaveFromBox() {
  const box = document.getElementById('replayBox');
  let r;
  try { r = replaySave(box ? box.value : '', compsQuery()); }
  catch (e) { r = { ok: false, error: 'The save failed: ' + String((e && e.message) || e) }; }
  renderReplayCard(r);
  return r;
}
function replayArmFromBox(on) { const r = replaySetArmed(on); renderReplayCard(); return r; }
function replayForget() { replayClear(); const b = document.getElementById('replayBox'); if (b) b.value = ''; renderReplayCard(); return { ok: true }; }
function renderReplayCard(last) {
  const rep = document.getElementById('replayReport');
  const arm = document.getElementById('replayArm');
  const saved = replayRead();
  if (arm) { arm.checked = replayArmed(); arm.disabled = !saved; }
  if (!rep) return;
  const bits = [];
  // THE RESULT OF THIS TAP, stamped with its time (2026-09-16). Reported from
  // use: an amber line went unread, Save was tapped again, the same outcome
  // rendered the same card, and an identical card reads as a control that is
  // dead. The stamp makes a second answer look like one.
  if (last) bits.push(last.ok
    ? '<b>Saved and read back</b> at ' + esc(clockTime()) + '.'
    : '<span class="idna">' + esc(last.error) + '</span> (' + esc(clockTime()) + ')');
  if (saved) {
    bits.push(esc(saved.rows + ' listing' + (saved.rows === 1 ? '' : 's') +
      ' saved ' + String(saved.at).slice(0, 10) +
      (saved.query ? ' for “' + saved.query + '”' : '')));
    bits.push(replayArmed()
      ? '<b>ARMED</b> — the next lookup will replay this instead of calling.'
      : 'Not armed. Lookups call the provider and cost money.');
  } else {
    bits.push('Nothing saved. Paste a response above.');
  }
  rep.innerHTML = `<div class="note">${bits.join('<br>')}</div>`;
}
function renderWantsCard() {
  const box = document.getElementById('wantsBox');
  const rep = document.getElementById('wantsReport');
  const list = wantsList();
  // Never overwrite the box the finger is in.
  if (box && document.activeElement !== box) box.value = list.map(function (w) { return w.raw; }).join('\n');
  if (!rep) return;
  const bad = list.filter(function (w) { return !w.matchable; }).length;
  const st = Store.status();
  const parts = [list.length + (list.length === 1 ? ' want saved' : ' wants saved')];
  if (bad > 0) {
    parts.push(bad + (bad === 1 ? ' line has' : ' lines have') +
      ' no issue number and will NEVER match — v1 matches exact issues only');
  }
  if (!st.ok) parts.push('NOT saved to this device — ' + st.message);
  rep.innerHTML = `<div class="note${(bad || !st.ok) ? ' wantwarn' : ''}">${esc(parts.join(' · '))}</div>`;
}

function renderIdentityHTML(v) {
  const f = v.fields;
  const head = [f.title || 'Title not legible', issueLabel(f.issue)].filter(Boolean).join(' ');
  const sub = [f.publisher, f.cover_date, f.cover_price].filter(Boolean).join(' · ');
  const rows = ID_FIELDS.map(function (spec) {
    const val = f[spec.key];
    return `<div class="idrow${val ? '' : ' idmissing'}">` +
      `<label for="id_${esc(spec.key)}">${esc(spec.label)}` +
      `${spec.hint ? ' <small>(' + esc(spec.hint) + ')</small>' : ''}` +
      `${val ? '' : ' <small class="idna">not legible</small>'}</label>` +
      `<input id="id_${esc(spec.key)}" type="text" value="${esc(val || '')}" ` +
      `placeholder="not legible — type it if you can" ` +
      `oninput="identitySetField('${esc(spec.key)}', this.value)"></div>`;
  }).join('');
  const chips = ID_MARKERS.map(function (m) {
    const on = v.markers.indexOf(m) >= 0;
    return `<button type="button" class="idchip${on ? ' on' : ''}" aria-pressed="${on ? 'true' : 'false'}" ` +
      `onclick="identityToggleMarker('${esc(m)}')">${esc(m)}</button>`;
  }).join('');
  const bits = [];
  if (v.refused > 0) bits.push(v.refused + (v.refused === 1 ? ' field was' : ' fields were') + ' refused');
  if (v.droppedMarkers > 0) bits.push(v.droppedMarkers + ' marker' + (v.droppedMarkers === 1 ? ' was' : 's were') + ' not on the list');
  const refusedHTML = bits.length
    ? `<div class="idrefused">${esc(bits.join(' · '))} — this app takes only what a photo can show. ` +
      `What a book is worth, its grade, and whether it is a key issue never come from the model.</div>`
    : '';
  return `<div class="iddraft">` +
    `<div class="idq">Is this the book?</div>` +
    `<div class="idhead">${esc(head)}</div>` +
    // D15: its own element, so corrections repaint the CONTENTS without
    // rebuilding the inputs above and below it.
    `<div id="wantFlag">${wantFlagHTML(v)}</div>` +
    (sub ? `<div class="idsub">${esc(sub)}</div>` : '') +
    refusedHTML +
    `<div class="idfields">${rows}</div>` +
    `<div class="idmarklabel">Markers visible on the cover</div><div class="idchips">${chips}</div>` +
    `<div class="idqueryrow">Will search for: <span id="idQueryLive">${esc(identityQuery(v) || '(nothing to search for yet)')}</span></div>` +
    `</div>`;
}

// CONFIRMED: memory only (D2 Fork F1 -- nothing persists in R1).
let CONFIRMED = null;
function confirmedIdentity() { return CONFIRMED; }
function identityAccept(v) {
  const q = identityQuery(v);
  COMPS = null; COMPS_EDITED = null;      // see clearConfirmed: nothing carries over
  CONFIRMED = {
    fields: JSON.parse(JSON.stringify(v.fields)), markers: v.markers.slice(),
    ai: JSON.parse(JSON.stringify(v.ai)), query: q, at: new Date(nowMs()).toISOString(),
  };
  renderConfirmed();
  return { ok: true, query: q };
}
// A new book inherits NOTHING from the last one: not its comps, not its edited
// query. A scatter left over from the previous lookup sitting under a new
// identity would be the confidently-wrong pairing brief rule 8 exists to stop.
// Fork D: Start over means a DIFFERENT BOOK, so the ask and the grade go with
// it -- a seller's price carried onto a new identity is brief rule 8's
// confidently-wrong pairing. A re-lookup with an edited query is the SAME book
// and the same seller, so compsLookup deliberately leaves them alone.
function clearConfirmed() {
  CONFIRMED = null; COMPS = null; COMPS_EDITED = null;
  askClear();
  renderConfirmed(); renderComps(); renderAsk();
  return { ok: true };
}
function renderConfirmed() {
  const el = document.getElementById('confirmedBox');
  if (!el) return;
  if (!CONFIRMED) { el.innerHTML = ''; return; }
  const f = CONFIRMED.fields;
  const head = [f.title, issueLabel(f.issue)].filter(Boolean).join(' ') || '(nothing legible)';
  // RULE 7 UNDER LOAD. The cover price rendered here as a bare "$1.00" between
  // the publisher and the date, which was harmless while it was the only price
  // on screen. R3 puts the ASKING price on the same screen, and an unlabelled
  // price beside a labelled one is exactly the conflation rule 7 forbids: one is
  // printed on the book, the other is what a stranger wants for it.
  const sub = [f.publisher, f.cover_date, f.cover_price ? 'cover ' + f.cover_price : '']
    .filter(Boolean).join(' · ');
  const marks = CONFIRMED.markers.length ? CONFIRMED.markers.join(', ') : 'none seen';
  el.innerHTML = `<div class="confirmed">` +
    `<div class="cfhead">Confirmed: ${esc(head)}</div>` +
    `<div class="cfsub">${sub ? esc(sub) + ' · ' : ''}markers: ${esc(marks)}</div>` +
    // D4, finally satisfied: R1 rendered this READ-ONLY and recorded that making
    // it editable was R2's. A normalisation that silently mangles a search is
    // worse than one the user can see and fix -- and typing here changes what is
    // SENT, not merely what is shown.
    `<label for="confirmedQuery">Search eBay sold listings for</label>` +
    `<div class="cfq"><input id="confirmedQuery" type="text" value="${esc(compsQuery())}" ` +
    `oninput="compsSetQuery(this.value)" aria-label="Search eBay sold listings for">` +
    `<button class="btn" onclick="copyQuery(this)">Copy</button></div>` +
    // FOLDED (R5/HT-D53): how the query was DERIVED explains the box above it;
    // it does not change what the query means, and it competed with the data for
    // the same screen. The box itself stays editable and visible.
    citeBlock('How this search was built',
      `<span class="fine">From the cover as printed, minus the leading article and the #. ` +
      `eBay is a full-text search, so the issue number belongs in it — edit the box above if it is wrong.</span>`) +
    (credConfigured('comps')
      ? `<button class="btn primary" onclick="compsLookup()">Look up sold comps</button> ` +
        `<button class="btn" onclick="clearConfirmed()">Start over</button></div>`
      // D2 Fork G1's shape: without a token there is still a route, and it is
      // named here rather than left to be discovered.
      : `<div class="note warnline">No comps token saved. Add one in Settings to look up what copies actually sold for — ` +
        `or copy the search text above into eBay yourself and set the filter to Sold.</div>` +
        `<button class="btn" onclick="clearConfirmed()">Start over</button></div>`);
}
function copyQuery() {
  if (!CONFIRMED) return { ok: false };
  const box = document.getElementById('confirmedQuery');
  const text = compsQuery();          // what would be SENT, not what R1 derived
  if (box) { try { box.focus(); box.select(); box.setSelectionRange(0, text.length); } catch (e) {} }
  let done = false;
  try { done = document.execCommand('copy'); } catch (e) { done = false; }
  if (done) { toast('Search text copied'); return { ok: true, via: 'selection' }; }
  if (navigator.clipboard && navigator.clipboard.writeText) {
    navigator.clipboard.writeText(text).then(
      function () { toast('Search text copied'); },
      function () { toast('Copy did not work — the text is in the box, select it and copy'); });
    return { ok: true, via: 'clipboard' };
  }
  toast('The text is in the box — select it and copy');
  return { ok: true, via: 'manual' };
}

// ---- R2b / D10: PRICE VIA eBAY SOLD COMPS ------------------------------------
// What a book ACTUALLY SOLD FOR -- not what a guide models it at. Two different
// claims that never share a label (brief rule 7's shape, applied to sources).
//
// THE QUERY IS eBAY'S AND ONLY eBAY'S (D4's per-source amendment). GCD returns 0
// results for `the AMAZING SPIDER-MAN 151` because it resolves series first and
// issue second. eBay is full-text over listing titles, where the issue number is
// the single most DISCRIMINATING token in the string -- drop it and you get every
// issue of the series ever sold. One rule, measured on two sources, opposite
// answers: a query builder belongs to its source.
const COMPS_WINDOW_DAYS = 90;     // Fork C, stated on every render. Actor default: 30.
const COMPS_COUNT       = 100;    // Fork A's bound: 100 x $4.00/1000 = $0.40 a lookup.
const COMPS_MIN_SHOWN   = 3;      // D8: below three, the surface says so.
const COMPS_BUDGET_MS   = 60000;  // the probe returned in <5s; run-sync may queue.
const COMPS_ARTICLE_RE  = /^(?:the|an?)\s+/i;

let COMPS = null;         // the last lookup. Memory only -- R2b persists nothing.
let COMPS_EDITED = null;  // the query the user typed, if they typed one.

// D4: the reading is EVIDENCE and is never normalised; the query is DERIVED and
// is a different object. Drop the leading article (universal -- a fact about the
// reading). Drop the `#` (eBay-scoped -- punctuation to a full-text index). Keep
// the issue number (eBay-scoped, and the exact opposite of GCD's rule).
function compsDefaultQuery(cf) {
  const f = (cf && cf.fields) || {};
  const title = String(f.title || '').replace(COMPS_ARTICLE_RE, '').trim();
  const issue = String(f.issue || '').replace(/^#+/, '').trim();
  return [title, issue].filter(Boolean).join(' ').replace(/\s+/g, ' ').trim();
}
function compsQuery() {
  return (COMPS_EDITED !== null) ? COMPS_EDITED : compsDefaultQuery(confirmedIdentity());
}
// VISIBLE AND EDITABLE (D4). A normalisation that silently mangles a search is
// worse than one the user can see and fix -- and editing must change what is
// SENT, not just what is shown, which is what the gate asserts on the body.
function compsSetQuery(raw) {
  COMPS_EDITED = String(raw == null ? '' : raw);
  return { ok: true, query: compsQuery() };
}
function compsResetQuery() { COMPS_EDITED = null; renderConfirmed(); return { ok: true, query: compsQuery() }; }

// EVERY input pinned; none left to the actor's default.
//
// `includeCompletedListings` above all. Set FALSE, the actor's own documentation
// says a Best-Offer sale reports the seller's ASKING PRICE in `soldPrice` -- brief
// rule 7's conflation committed INSIDE THE DATA SOURCE, silently, in the single
// field this app reads. TRUE is both correct and safe, and it is pinned rather
// than inherited: today's default agrees, and a vendor changing its default
// would not announce it.
//
// `daysToScrape` defaults to 30 and Fork C ruled 90 -- unset, the app would have
// shipped a third of its window with nothing on the surface to show for it.
//
// `count` is PER KEYWORD ("each keyword runs as a separate search"), so the bill
// is count x keywords.length. Exactly one keyword is what keeps it bounded.
function compsBody(query) {
  const row = PROVIDERS.apify;
  return {
    keywords: [String(query == null ? '' : query)],
    categoryId: String(row.categoryId),
    subcategoryId: '',
    daysToScrape: COMPS_WINDOW_DAYS,
    count: COMPS_COUNT,
    sortOrder: 'endedRecently',
    ebaySite: String(row.site),
    includeCompletedListings: true,
  };
}
// R2b-cost: the bill is BOUNDED AND STATED BEFORE the call, never discovered
// after it. A lookup cannot silently deepen.
function compsBound(body) {
  const n = ((body && body.keywords) || []).length * num(body && body.count);
  return { results: n, usd: n * (num(PROVIDERS.apify.usdPer1000) / 1000) };
}

// The contract as ONE REAL RUN returned it. Nine fields kept of the ten sent --
// and the ABSENCES are what shape the whole slice: no Grade, no Certification, no
// Variant, and NO CATEGORY either, though the vendor's own schema documentation
// claims the output carries one. D3: the contract is what ARRIVED, not what was
// advertised, and the two disagreed here on the very first run.
const COMP_KEYS = ['itemId', 'title', 'condition', 'conditionId', 'endedAt',
                   'soldPrice', 'soldCurrency', 'listingType', 'isBestOfferAccepted'];
// R5: ONE SOURCE OF TRUTH FOR WHAT A COMP IS.
//
// COMP_KEYS above declares what ARRIVES. This declares what we KEEP, and the row
// builder is driven BY it -- so a field cannot be consumed without being declared
// and cannot be declared-and-consumed while silently absent from a row.
//
// THE DEFECT THIS CLOSES: COMP_KEYS listed `listingType` and `conditionId` and
// parseComps dropped both, for the whole of R2b and R3. Nothing broke, because
// nothing read them -- and no assertion pinned the two together (CQ5 only checks
// what is ABSENT from COMP_KEYS). A declared contract and its consumer drifting
// while both pass their own assertions is D3, exactly. A comparison gate would
// have been a THIRD list to keep in step; deriving the rows removes the question.
//
// `keyword` is declared and deliberately NOT kept: it is our own query echoed
// back, not a fact about the sale. Declared-but-unused is fine; the reverse is
// what the derivation makes impossible.
const COMP_FIELDS = [
  { from: 'itemId',              to: 'itemId',       cast: 'str'  },
  { from: 'title',               to: 'title',        cast: 'str'  },
  { from: 'condition',           to: 'condition',    cast: 'str'  },
  { from: 'conditionId',         to: 'conditionId',  cast: 'str'  },
  { from: 'endedAt',             to: 'endedAt',      cast: 'str'  },
  { from: 'soldPrice',           to: 'soldPrice',    cast: 'num'  },
  { from: 'soldCurrency',        to: 'soldCurrency', cast: 'cur'  },
  { from: 'listingType',         to: 'listingType',  cast: 'str'  },
  { from: 'isBestOfferAccepted', to: 'bestOffer',    cast: 'bool' },
];

// listingType's VALUES ARE UNMEASURED. R2b's probe recorded that the field
// exists and never what range it takes, so this table is written from eBay's
// documented vocabulary and CANNOT yet be gated as exhaustive (D3: gate across
// the range a contract permits -- and that range is currently unknown).
//
// Therefore any value not in it renders VISIBLY as unstated, never absorbed into
// a default: a discriminator that silently stops discriminating looks exactly
// like one that works, which is D5's shape. The census comes free from the next
// real lookup rather than from a paid probe.
//
// THREE STATES, not two. `absent` (older data, and every existing fixture) is a
// different fact from `unrecognised` (a contract surprise). They look identical
// on the surface -- the reader's situation is the same, "not known" -- and stay
// distinct in the data, so a gate can tell a stale fixture from a live surprise.
const COMP_TYPES = {
  auction:        { kind: 'auction', label: 'auction' },
  auctionwithbin: { kind: 'auction', label: 'auction, with Buy It Now' },
  fixedprice:     { kind: 'bin',     label: 'Buy It Now' },
  buyitnow:       { kind: 'bin',     label: 'Buy It Now' },
  storeinventory: { kind: 'bin',     label: 'Buy It Now, shop listing' },
  // MEASURED, NOT DOCUMENTED. Two real runs (asm151 2026-09-15, action445
  // 2026-09-14) both carry `best_offer_accepted` as a listingType value, on 16 of
  // 84 kept rows in the first -- a fifth of a real scatter, which had been
  // rendering as "not recognised". It IS a Buy It Now; the price was negotiated.
  //
  // statesOffer: the value names the offer ITSELF, and isBestOfferAccepted is
  // true on exactly those rows, so the ring already carries that fact. Without
  // this flag the mark would read "Buy It Now · best offer accepted · best offer
  // accepted" -- the same field on two channels, said twice.
  bestofferaccepted: { kind: 'bin', label: 'Buy It Now', statesOffer: true },
};
function compTypeOf(r) {
  const given = (r && r.listingType != null) ? String(r.listingType) : '';
  const key = given.toLowerCase().replace(/[^a-z]/g, '');
  if (!key) return { kind: 'unstated', stated: false, known: false, label: 'listing type not stated' };
  const hit = COMP_TYPES[key];
  if (!hit) return { kind: 'unstated', stated: true, known: false,
                     label: 'listing type “' + given + '” not recognised' };
  return { kind: hit.kind, stated: true, known: true, label: hit.label,
           statesOffer: !!hit.statesOffer };
}

// THE REFUSAL NAMES WHERE THE TEXT CAME FROM (D27). One parser serves the live
// lookup and C1's paste, and until 2026-09-16 both were told "The provider sent
// something that is not JSON" -- which, for a paste cut short, blamed a party
// that had done nothing wrong and pointed away from the one recovery that works:
// copy the whole response again. `source` changes the WORDS and nothing else;
// the rows a given string parses to are identical either way.
const COMPS_PARSE_MSG = {
  provider: { notJson: 'The provider sent something that is not JSON.',
              notList: 'The provider did not send a list of listings.' },
  paste:    { notJson: 'The pasted text is not JSON. A response cut short looks exactly like this — copy the whole dataset and paste it again.',
              notList: 'The pasted text is JSON, but not a list of listings. Paste the dataset itself: the array of sold listings, starting with [.' },
};
function parseComps(raw, source) {
  const msg = COMPS_PARSE_MSG[source] || COMPS_PARSE_MSG.provider;
  let arr;
  try { arr = JSON.parse(String(raw == null ? '' : raw)); }
  catch (e) { return { ok: false, error: msg.notJson }; }
  if (!Array.isArray(arr)) return { ok: false, error: msg.notList };
  const rows = [];
  for (let i = 0; i < arr.length; i++) {
    const o = arr[i];
    if (!o || typeof o !== 'object') continue;
    const price = Number(o.soldPrice);
    if (!(price > 0)) continue;                  // a comp with no price is not a comp
    const row = {};
    COMP_FIELDS.forEach(function (f) {
      const v = o[f.from];
      if (f.cast === 'num') row[f.to] = price;
      else if (f.cast === 'bool') row[f.to] = !!v;
      else if (f.cast === 'cur') row[f.to] = String(v || 'USD');
      else row[f.to] = String(v == null ? '' : v);
    });
    rows.push(row);
  }
  return { ok: true, rows: rows };
}

// OURS, CLIENT-SIDE, so the rules are visible and gateable rather than buried in
// a vendor's query string (Fork D). The probe saw no lots in the first eight
// rows, so this is a safety net rather than the main event -- but eight rows is a
// thin sample, and one lot at the top of a scatter is exactly the tail risk that
// would mislead. WHAT IS DROPPED IS COUNTED AND SHOWN, never silently removed:
// a filter the user cannot see is a filter they cannot correct.
const COMPS_EXCLUDE = [
  { re: /\blots?\b/i,                                 why: 'lot' },
  { re: /\bbundles?\b|\bset of\b/i,                   why: 'bundle' },
  { re: /\breprints?\b|\bfacsimiles?\b/i,             why: 'reprint' },
  { re: /\btpb\b|\btrade paperbacks?\b|\bomnibus\b/i, why: 'collection' },
];
function compsFilter(rows) {
  const kept = [], dropped = [];
  (rows || []).forEach(function (r) {
    let why = '';
    for (let i = 0; i < COMPS_EXCLUDE.length && !why; i++)
      if (COMPS_EXCLUDE[i].re.test(r.title)) why = COMPS_EXCLUDE[i].why;
    if (why) dropped.push({ title: r.title, why: why }); else kept.push(r);
  });
  return { kept: kept, dropped: dropped };
}

// THE GRADE AND THE ASKING PRICE NEVER ENTER A LOOKUP (brief rules 3 and 4).
// Asserted against the REQUEST BODY, not the surface: a surface that does not
// show them proves nothing about what was sent.
const COMPS_NEVER_SENT = ['grade', 'asking', 'asking_price', 'askingPrice', 'sticker', 'sticker_price'];
function compsBodyIsClean(body) {
  const s = JSON.stringify(body || {}).toLowerCase();
  return !COMPS_NEVER_SENT.some(function (k) { return s.indexOf('"' + k.toLowerCase() + '"') >= 0; });
}

// A CONNECTION TEST MUST NOT SPEND. `pricesPing` is free; a run-sync call bills
// $0.40, so testing the token by doing a lookup would make the Test button cost
// money -- R2b-cost's prohibition, arrived at from the opposite direction.
// `/v2/users/me` authenticates the token and starts no actor.
function compsPing() {
  const s = credSettings('comps');
  return egress('comps', { path: '/users/me', method: 'GET', budget: TEST_TIMEOUT_MS }).then(function (t) {
    if (!t.transport) return t;
    let j = null; try { j = JSON.parse(t.raw); } catch (e) {}
    if (t.httpOk && j && j.data) return { ok: true, text: '' };
    const pmsg = providerMessage(t.raw, s.key);
    if (t.status === 401 || t.status === 403)
      return errOf('auth', pmsg || 'Apify rejected the token. Check it in Settings.');
    if (t.status === 429) return errOf('ratelimit', 'Apify is rate-limiting. Wait before trying again.');
    if (!j) return errOf('malformed', 'Apify did not answer with JSON.');
    return errOf('http', 'Apify returned ' + t.status + '. ' + pmsg);
  });
}

// ---- C1: RESPONSE REPLAY, FOR TESTING ONLY ---------------------------------
// A lookup costs about $0.40 and returns the same rows every time. Checking a
// layout change should not cost money -- and with credits exhausted the
// alternative to replay is not "pay per check", it is CANNOT CHECK AT ALL.
//
// C, NOT R. This is test-phase machinery, numbered apart from the feature series
// deliberately. NOT a product feature, NOT an offline mode, NOT a cache: there is
// no "use the last result if the call fails" path, because that is how a testing
// aid becomes a silent fallback nobody remembers is there.
//
// IN MEMORY ONLY (REPLAY_ARMED). A persisted arm could outlive a reload and
// replay silently in a later session, which would make every measurement taken
// afterwards untrustworthy without anything looking wrong. One click per session
// is the price of that guarantee.
//
// OUTSIDE THE STATE OBJECT, like a credential (D1). It is not the subscriber's
// data and must never enter an export -- and exportJSON serialises APP_STATE, so
// holding it elsewhere makes that impossible BY CONSTRUCTION rather than by a
// filter someone has to remember.
const REPLAY_KEY = 'collectibles-replay';   // PFX1: every storage key is prefixed
let REPLAY_ARMED = false;

function replayRead() {
  let raw = null;
  try { raw = Store.readRaw(REPLAY_KEY); } catch (e) {}
  if (!raw) return null;
  try {
    const o = JSON.parse(raw);
    if (!o || typeof o !== 'object' || typeof o.raw !== 'string' || !o.raw) return null;
    return { at: String(o.at || ''), query: String(o.query || ''), raw: o.raw, rows: num(o.rows) };
  } catch (e) { return null; }
}
// PARSED BEFORE IT IS STORED, so a paste that is not a comps response is refused
// with the PARSER'S OWN message rather than accepted and discovered later. What
// is in the key is therefore always something parseComps has already accepted.
// Parsed AS A PASTE, so the refusal names the paste rather than the provider.
//
// AND READ BACK BEFORE IT IS CALLED A SAVE (2026-09-16). "The write returned
// true" was never "the arm can read it". One failed state save puts a session on
// the memory tier, where writeAux still writes and readRaw returns null -- so
// this reported ok, the card re-rendered "Nothing saved" identical to the card
// before the tap, and the arm could never engage. The memory tier is now refused
// BEFORE writing, which keeps "not saved" true; any other write is read back
// through replayRead, the arm's own path, and a record it cannot read is not kept.
const REPLAY_MEMORY_MSG = 'Not saved. Storage is running in memory only this session — the badge at the top says why — so a saved response could not be read back to replay. Reload the page; if the badge then says saved, paste it again.';
function replaySave(text, query) {
  const body = String(text == null ? '' : text).trim();
  if (!body) return { ok: false, error: 'Nothing to save.' };
  const parsed = parseComps(body, 'paste');
  if (!parsed.ok) return { ok: false, error: parsed.error };
  if (Store.tier !== 'local') return { ok: false, error: REPLAY_MEMORY_MSG };
  const rec = { at: new Date(nowMs()).toISOString(), query: String(query || ''),
                raw: body, rows: parsed.rows.length };
  if (!Store.writeAux(REPLAY_KEY, JSON.stringify(rec)))
    return { ok: false, error: 'Storage refused the write — nothing was saved.' };
  const back = replayRead();
  if (!back || back.raw !== body) {
    Store.writeAux(REPLAY_KEY, '');
    return { ok: false, error: 'Storage took the write but did not give it back, so it was discarded — nothing is saved.' };
  }
  return { ok: true, rows: back.rows, at: back.at, error: '' };
}
function replayClear() { Store.writeAux(REPLAY_KEY, ''); REPLAY_ARMED = false; return { ok: true }; }
// Armed AND present. A saved response on its own is never a reason to replay.
function replayArmed() { return REPLAY_ARMED && !!replayRead(); }
function replaySetArmed(on) { REPLAY_ARMED = !!on && !!replayRead(); return { ok: true, armed: REPLAY_ARMED }; }
// RULED: a replayed response MUST SAY SO, with the date it was captured. Those
// sales were a 90-day window on that date and the window has moved since, so a
// surface identical either way would eventually mislead. Same reasoning that
// already puts the count and the window where the numbers are.
function replayNoticeHTML() {
  if (!COMPS || !COMPS.replay) return '';
  const d = String(COMPS.replay.at || '').slice(0, 10);
  return `<div class="note warnline replaynote">REPLAYED — a saved response from ` +
    `${esc(d || 'an unrecorded date')}, not looked up just now. Those sales were a ` +
    `${esc(String(COMPS_WINDOW_DAYS))}-day window on that date, and the window has moved since.</div>`;
}

function compsLookup() {
  const cf = confirmedIdentity();
  if (!cf) return Promise.resolve({ ok: false, error: 'Confirm a book first.' });
  const q = compsQuery();
  if (!q) return Promise.resolve({ ok: false, error: 'There is nothing to search for.' });
  const body = compsBody(q);
  const bound = compsBound(body);
  COMPS = { phase: 'loading', query: q, bound: bound, rows: [], dropped: [], error: '', at: '' };
  renderComps();
  // C1: THE ONLY LINE THAT DIFFERS. A replay substitutes the RAW STRING and
  // nothing else, so the branch below is not merely equivalent to the live
  // path -- it IS the live path, the same statements on the same object. The
  // parser, the filter, the plot, the ask comparison and the summon all operate
  // on parsed rows and cannot tell the difference, which is what makes this safe.
  const saved = replayArmed() ? replayRead() : null;
  const call = saved
    ? Promise.resolve({ transport: true, httpOk: true, status: 200, raw: saved.raw })
    : egress('comps', {
        path: '/acts/' + PROVIDERS.apify.actor + '/run-sync-get-dataset-items',
        json: body, budget: COMPS_BUDGET_MS,
      });
  return call.then(function (r) {
    const fail = function (msg) {
      COMPS = { phase: 'error', query: q, bound: bound, rows: [], dropped: [], error: msg, at: '' };
      renderComps();
      return { ok: false, error: msg };
    };
    if (!r.transport) return fail(r.message || r.error || 'The lookup could not be made.');
    if (!r.httpOk) return fail('The provider answered ' + r.status + '. ' +
      (r.status === 401 || r.status === 403 ? 'Check the comps token in Settings.'
       : 'Nothing was looked up; your account may still have been charged for a started run.'));
    const parsed = parseComps(r.raw);
    if (!parsed.ok) return fail(parsed.error);
    const split = compsFilter(parsed.rows);
    COMPS = { phase: 'done', query: q, bound: bound, rows: split.kept, dropped: split.dropped,
              error: '', at: new Date(nowMs()).toISOString(), returned: parsed.rows.length,
              // C1: how every surface knows. Null on a live lookup.
              replay: saved ? { at: saved.at } : null };
    renderComps(); renderAsk();   // the ask inputs appear WITH the comps they need
    return { ok: true, kept: split.kept.length, dropped: split.dropped.length };
  });
}
function compsClear() { COMPS = null; renderComps(); return { ok: true }; }
// TEST SEAM. The render is what D10 and D8 are asserted against, and driving it
// through a live egress call would make those cases a network test. This sets the
// state a completed lookup would have produced and paints it -- the same code
// path from `phase: 'done'` onward, which is where every rendering rule lives.
function __setComps(rows, dropped, query) {
  const body = compsBody(query);
  COMPS = { phase: 'done', query: String(query || ''), bound: compsBound(body),
            rows: rows || [], dropped: dropped || [], error: '',
            at: new Date(nowMs()).toISOString(), returned: (rows || []).length + (dropped || []).length };
  // MIRRORS compsLookup's SUCCESS BRANCH EXACTLY -- renderComps THEN renderAsk.
  // This seam stands in for a completed lookup, and for a while it did not
  // reproduce that lookup's render sequence: it called renderComps alone, so the
  // ask inputs were never painted. The data-layer suite stayed green because its
  // fixture called CT.renderAsk() by hand; the layout gate, which drives the real
  // page, failed with askBox present, phase done, rows 4 and innerHTML length 0.
  // A seam that does not reproduce the path it replaces is D3 at its smallest --
  // and the fixture papering over it is what kept the divergence invisible.
  renderComps(); renderAsk();
  return COMPS;
}

function compsMoney(n, cur) {
  const s = (Math.round(Number(n) * 100) / 100).toFixed(2).replace(/\.00$/, '');
  return (String(cur || 'USD') === 'USD' ? '$' : '') + s +
         (String(cur || 'USD') === 'USD' ? '' : ' ' + String(cur));
}
// SPELLED MONTH, never D/M. Reported from the first device pass: "17/08" reads
// as 17 August to half the world and as a malformed US month-first date to the
// other half, and there is nothing on the surface to disambiguate it. A comp's
// date is provenance -- it is what makes the 90-day window checkable -- so it
// must not be a number the reader has to guess the convention for.
function compsDate(iso) {
  const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(String(iso || ''));
  if (!m) return '';
  const MON = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return String(Number(m[3])) + ' ' + (MON[Number(m[2]) - 1] || '?');
}

// D10: ONE SCATTER, NO GROUPS. The search tier returns no Grade, no Certification
// and no Variant, so nothing here CONSTITUTES a raw/slabbed split -- and a group
// header is a claim about what the app knows. The seller's own title rides beside
// every price, VERBATIM, because that is where the grade actually is: free text,
// no format ("VF- 7.5", "GD", "VF- 1 CF staple detached"). The human splits them
// by eye, the same division of labour as the grade and the asking price.
//
// D8 AS AMENDED: NO RANGE AT ANY N. The min and the max would come from two
// different markets -- the probe's own scatter runs $9 to $145 -- and "$9-$145"
// describes no book anyone can buy. A span is not a claim. The word "value"
// appears nowhere near a comp, and no average, midpoint or ladder is computed.
function renderComps() {
  const el = document.getElementById('compsBox');
  if (!el) return;
  if (!COMPS) { el.innerHTML = ''; renderAsk(); return; }
  const win = COMPS_WINDOW_DAYS + ' days';
  if (COMPS.phase === 'loading')
    return void (el.innerHTML = `<div class="comps"><div class="opend"><span class="byokspin"></span>` +
      `Looking up sold listings for “${esc(COMPS.query)}”…</div>` +
      `<div class="note">Up to ${esc(COMPS.bound.results)} results, about ${esc(compsMoney(COMPS.bound.usd))}.</div></div>`);
  if (COMPS.phase === 'error')
    return void (el.innerHTML = `<div class="comps"><div class="omsg obad">${esc(COMPS.error)}</div>` +
      `<button class="btn" onclick="compsLookup()">Try again</button></div>`);

  const n = COMPS.rows.length;
  const sorted = COMPS.rows.slice().sort(function (a, b) { return a.soldPrice - b.soldPrice; });
  const head = `<div class="cmphead">${n} sold · last ${esc(win)}</div>`;
  // D8: below three, the surface SAYS SO rather than showing a thin scatter as
  // though it were a finding.
  if (n < COMPS_MIN_SHOWN)
    return void (el.innerHTML = `<div class="comps">${head}` +
      // A thin REPLAYED result is still a replay, and staleness matters more
      // here, not less: "too few sales" on a moved window is a different claim.
      replayNoticeHTML() +
      `<div class="note warnline">Too few recent sales to compare — ${n === 0 ? 'none' : 'only ' + n} in the last ${esc(win)}. ` +
      `That is not a low price or a high one; it is no answer. Try a broader search, or decide without this.</div>` +
      (n ? sorted.map(compsRowHTML).join('') : '') +
      compsFootHTML() + `</div>`);

  // R5, and HT-D53's cut: the WHAT stays on the surface, the WHY folds. Anything
  // that changes what a number MEANS is not foldable -- the count and the window
  // ride in `head` (CQ7 gates both), and the raw/slab statement is here.
  return void (el.innerHTML = `<div class="comps">${head}` +
    replayNoticeHTML() +
    // D10, stated WHERE THE NUMBERS ARE and not in a footnote. This sentence
    // changes what every price means, so it cannot be one tap away.
    `<div class="note warnline">These are mixed: this lookup cannot tell a raw copy from a graded slab. ` +
    `Read them — a slabbed 9.8 and a beaten reading copy are both in this list.</div>` +
    compsPlotHTML(sorted) +
    // FOLDED: the provenance half -- WHY it cannot tell. It explains the
    // sentence above rather than changing what a number means, which is exactly
    // where HT-D53 puts the cut.
    citeBlock('Why it cannot tell them apart',
      `<span class="fine">eBay's search results carry no grade and no certification field, so the seller's own words are the only grade there is. ` +
      `Three books at an identical “Pre-Owned / 3000” sold for $9, $29.99 and $89 — a 10× spread at one condition code, measured rather than argued (D7).</span>`) +
    // SUMMONED, not folded (R6). A fold kept the wall of text and closed a
    // drawer over it; the plot is the list now, and the words are one explicit,
    // scope-naming action away. D10's floor holds: scanning titles stays
    // possible, it just stops being the default.
    compsListBlockHTML(sorted, n) +
    compsFootHTML() + `</div>`);
}
// FOUND BY THE LAYOUT GATE, and it was a product defect rather than a test gap:
// the ask inputs are painted by renderAsk, and NOTHING on the shipped path
// called it after a lookup. compsLookup ended at renderComps; only refresh()
// reached renderAsk, so after a real lookup the ask fields would not have
// appeared until some unrelated repaint happened to run. The data-layer suite
// could not see it, because its fixture calls CT.renderAsk() by hand.
//
// Fixed at the two places that own the transition -- compsLookup's success
// branch, and renderComps' empty branch -- rather than behind a wrapper.
// Calling renderAsk on a repaint is safe BY CONSTRUCTION: it rebuilds only when
// the PHASE changes, which is the same guard that stops typing destroying the
// caret. That guard is why this is a one-line fix and not a new bug.
// The ask marker is placed BY VALUE, before the first sale that beat it -- not
// by an index computed elsewhere, so it cannot drift out of step with the sort.
// Sales at exactly the ask sit below it and are counted separately.
function compsListHTML(sorted) {
  const mk = askMarkerHTML();
  if (!mk) return sorted.map(compsRowHTML).join('');
  const out = [];
  let placed = false;
  sorted.forEach(function (r) {
    if (!placed && r.soldPrice > ASK) { out.push(mk); placed = true; }
    out.push(compsRowHTML(r));
  });
  if (!placed) out.push(mk);
  return out.join('');
}

// ---- R6: SURFACE ON DEMAND, not fold ---------------------------------------
// R5 folded the 84-row list behind a toggle, which kept the wall of text and
// merely closed a drawer over it. The better rule: THE PLOT IS THE LIST, and
// rows surface when something makes them relevant -- a tap, and later a filter.
//
// D7 AND D10 SET THE FLOOR THIS CANNOT GO BELOW: the seller's own words are the
// only grade signal this tier has, so scanning titles must remain POSSIBLE.
// Summoned, not sitting there by default -- removing them would be the opposite
// error from the one being fixed.
//
// Three paths to the words now, none of them permanent: a tap gives one sale,
// R3's nearest comps sit beside the ask unfolded, and this lists the whole set
// on an explicit action that NAMES ITS SCOPE. "List all N sales" rather than a
// bare "show" -- once filters land it becomes the current selection, and a
// control that hides how much it is about to show is the thing being removed.
//
// LIST_SHOWN IS DELIBERATELY NOT RESET between lookups. The list always renders
// from COMPS.rows, so a stale `true` shows THIS book's sales, never the previous
// one's -- there is no wrong-data risk to guard. Resetting it would mean the
// four-call-site bookkeeping that compsPick avoided by keying on object identity.
// ---- R6b: THE FILTERS. They COUNT AND LIST; the plot is untouched ----------
// RULED AS HIGHLIGHT-AND-DIM, BUILT AS COUNT-AND-LIST, because the measurement
// refused the design. Marks render at 5.31 x 5.31px, and at that size no channel
// can carry a second state:
//
//   opacity  dim vs backdrop peaks at 2.45:1 (dark) / 2.28:1 (light) -- below the
//            3:1 bar for a graphical object. Where dim-vs-NORMAL finally clears
//            3:1, dim-vs-backdrop has fallen to 2.08:1: the two requirements
//            cross at ~2.7:1 and neither is met. Light is strictly worse, because
//            a normal mark starts at 4.58:1 there rather than 7.12:1.
//   colour   --accent sits 2.10:1 (dark) / 1.74:1 (light) from a normal mark, and
//            1.14:1 / 1.01:1 at full alpha -- luminance-identical. Hue alone would
//            fail WCAG 1.4.1 and vanish in greyscale.
//   alpha up .pm:hover/:focus ALREADY own opacity 1, so a brighter highlight would
//            render identically to the mark under the user's finger.
//   size     the first shrink meeting a 1.4 ratio collapses shape discrimination:
//            circle/rect IoU 0.888, circle/diamond 0.878, rect/diamond 0.849. It
//            destroys the listing-type channel to add a selection one, and halves
//            the tap target of exactly the sales the user did NOT select.
//
// So the plot keeps every sale, unchanged, and the SELECTION drives the LIST.
// This is not a retreat: R6's own legibility-half fork already ruled the summon
// path as "an action that lists the CURRENT SELECTION -- 'list these N sales' --
// never the whole set by default. Once filters exist that becomes 'title mentions
// CGC -> list these'." The measurement pushed the build onto the path the record
// had already chosen.
//
// D10 GOVERNS THE LABELS. The app reports a STRING MATCH and cannot know what a
// title means: "CGC READY" sits on raw books. So every label says what was
// matched -- "title mentions CGC" -- never what it might imply ("slabbed").
const COMPS_CATS = [
  { key: 'cgc',       label: 'title mentions CGC',                      re: /\bCGC\b/i },
  { key: 'cbcs',      label: 'title mentions CBCS',                     re: /\bCBCS\b/i },
  { key: 'pgx',       label: 'title mentions PGX',                      re: /\bPGX\b/i },
  { key: 'graded',    label: 'title mentions graded or slabbed',        re: /\bgraded\b|\bslabbed\b|\bslab\b/i },
  { key: 'numgrade',  label: 'title mentions a number grade (9.8)',     re: /\b(?:10|[1-9])\.\d\b/ },
  { key: 'ltrgrade',  label: 'title mentions a letter grade (VF, NM)',  re: /\b(?:VF|NM|FN|VG|GD|FA|PR)\b/i },
  { key: 'signed',    label: 'title mentions signed',                   re: /\bsigned\b|\bsignature\b|\bautograph/i },
  { key: 'variant',   label: 'title mentions variant',                  re: /\bvariant\b/i },
  { key: 'key',       label: 'title mentions key',                      re: /\bkey\b/i },
  { key: 'damage',    label: 'title mentions damage (tape, tear)',      re: /\bdetached\b|\btapes?d?\b|\bwater\b|\bcoverless\b|\bmissing\b|\btears?\b/i },
  { key: 'newsstand', label: 'title mentions newsstand',                re: /\bnewsstand\b/i },
  { key: 'pence',     label: 'title mentions pence or UK',              re: /\bpence\b|\bUK\b/ },
];
let COMPS_FILTERS = [];
// DERIVED FROM THE RESPONSE, never declared. Twelve categories exist; only those
// the seller titles actually support render. An empty filter cannot narrow, and a
// button that matches nothing is a control that has stopped controlling (D5).
// Measured on the real 84: seven render, six do not -- and the six are the control
// that makes "derives from the response" a test rather than a claim.
function compsFilterCats() {
  const rows = (COMPS && COMPS.phase === 'done') ? COMPS.rows : [];
  const out = [];
  COMPS_CATS.forEach(function (c) {
    let n = 0;
    rows.forEach(function (r) { if (c.re.test(String((r && r.title) || ''))) n++; });
    if (n > 0) out.push({ key: c.key, label: c.label, n: n });
  });
  return out;
}
function compsFiltersActive() { return COMPS_FILTERS.slice(); }
function compsFilterClear() { COMPS_FILTERS = []; renderComps(); return { ok: true }; }
function compsFilterToggle(key) {
  const i = COMPS_FILTERS.indexOf(key);
  if (i >= 0) COMPS_FILTERS.splice(i, 1); else COMPS_FILTERS.push(key);
  renderComps();
  return { ok: true, active: COMPS_FILTERS.slice() };
}
// OR, not AND (ruled). AND shrinks the selection toward nothing, which is
// filtering by another name and contradicts the ruling this slice is built on.
function compsFilterMatch(r) {
  if (!COMPS_FILTERS.length) return true;
  const t = String((r && r.title) || '');
  return COMPS_FILTERS.some(function (k) {
    for (let i = 0; i < COMPS_CATS.length; i++)
      if (COMPS_CATS[i].key === k) return COMPS_CATS[i].re.test(t);
    return false;
  });
}
function compsSelected(sorted) { return (sorted || []).filter(compsFilterMatch); }
function compsFilterHTML() {
  const cats = compsFilterCats();
  if (!cats.length) return '';
  return `<div class="cmpfilters">` +
    `<div class="fine">Narrow the list by what the seller wrote. ` +
    `The plot never changes — every sale stays on it.</div>` +
    cats.map(function (c) {
      const on = COMPS_FILTERS.indexOf(c.key) >= 0;
      return `<button type="button" class="fbtn${on ? ' on' : ''}" aria-pressed="${on ? 'true' : 'false'}" ` +
        `onclick="compsFilterToggle('${esc(c.key)}')">${esc(c.label)} — ${esc(String(c.n))}</button>`;
    }).join('') +
    `</div>`;
}

// R5's four-call-site bookkeeping that compsPick avoided by keying on object identity.
let LIST_SHOWN = false;
function compsListShown() { return LIST_SHOWN; }
function compsListToggle() { LIST_SHOWN = !LIST_SHOWN; renderComps(); return { ok: true, shown: LIST_SHOWN }; }
function compsListBlockHTML(sorted, n) {
  // THE CONTROL NAMES ITS SCOPE, and the scope is now the selection. R6 ruled
  // the summon must say how much it is about to show; with filters active that
  // is "these N", not "all N" -- a button that reports the wrong number is the
  // thing R6 removed, wearing a filter.
  const sel = compsSelected(sorted);
  const narrowed = COMPS_FILTERS.length > 0;
  const label = LIST_SHOWN ? 'Hide the list'
    : (narrowed ? 'List these ' + sel.length + ' sales' : 'List all ' + n + ' sales');
  return `<div class="cmpsummon">` +
    compsFilterHTML() +
    `<button type="button" class="btn" onclick="compsListToggle()">` + esc(label) + `</button>` +
    (LIST_SHOWN ? `<div class="cmplist">${compsListHTML(sel)}</div>` : '') +
    `</div>`;
}
// THREE FIELDS, THREE ELEMENTS, and the source order matches the visual order:
// price and date on the first line, the seller's title on its own line beneath.
// The structured fields and the free text are different KINDS of thing -- one is
// provenance, the other is the only grade signal this tier has (D10) -- so they
// are separated rather than run together. They shipped as three unstyled inline
// spans and a phone rendered them as one string; see index.html's .cmprow.
function compsRowHTML(r) {
  return `<div class="cmprow">` +
    `<span class="cmpprice">${esc(compsMoney(r.soldPrice, r.soldCurrency))}</span>` +
    `<span class="cmpmeta">${esc(compsDate(r.endedAt))}${r.bestOffer ? ' · best offer accepted' : ''}</span>` +
    `<span class="cmptitle">${esc(r.title)}</span>` +
    `</div>`;
}
// ---- R5: THE DISTRIBUTION, DRAWN -------------------------------------------
// 98 sales spanning $2 to $2,300 is not one population. Raw, mid-grade and
// slabbed are superimposed, and the search tier gives no field that separates
// them -- measured, not argued (D7: three books at an identical Pre-Owned/3000
// sold for $9, $29.99 and $89). But they separate BY MODE, and the gaps between
// clusters are the grade boundaries the data refuses to state. The eye reads
// that instantly; no summary statistic conveys it. This is D8's "a scatter is
// the claim" RENDERED rather than written.
//
// WHAT IS REFUSED, and for D8's reason: no fitted model, no kernel density, no
// smoothing, no trendline, no asserted cluster count, and no bins that invent
// counts. n=98 is enough to SEE modes and not enough to CHARACTERISE them;
// mode-fitting on a small sample finds structure in noise. The app draws the
// dots, the human finds the modes.
//
// ONE MARK, ONE SALE. That is the property the whole plot rests on, which is why
// ties STACK rather than blending: opacity would make two sales at $9 look like
// one darker sale, and that invents a reading.
//
// GRADE NEVER REACHES HERE. askSetGrade deliberately has no path to the scatter
// ("the surest way to guarantee that is to give it no path at all"); the plot
// adds no second route.
const PLOT_W = 320, PLOT_H = 124;
const PLOT_BASE = 92;   // the baseline marks sit on
const PLOT_TOP = 16;    // the highest a stack may reach
const PLOT_STEP = 8;    // one stack level
const PLOT_COL = 4;     // viewBox units that count as "the same column"
const PLOT_MAX_STACK = Math.floor((PLOT_BASE - PLOT_TOP) / PLOT_STEP);

// LOG, AND IT IS A CLAIM RATHER THAN A CONVENIENCE (ruled 2026-09-14). Grade
// bands are MULTIPLICATIVE: $9 -> $29 is the same kind of step as $90 -> $290.
// Linear over $2-$2,300 would put the entire raw market in the first 2% of the
// axis and let one CGC 9.8 define the scale -- the modes would vanish, which is
// the slice defeated. Because it is a claim, it is STATED on the surface, and
// the ticks are dollars, never exponents.
//
// The ASK joins the domain when one is set, so the rule can never fall off the
// edge -- the axis spans what is shown, which is the honest reading of it.
function compsScale(prices) {
  const ps = (prices || []).filter(function (p) { return p > 0; });
  if (!ps.length) return null;
  let lo = Math.min.apply(null, ps), hi = Math.max.apply(null, ps);
  if (!(hi > lo)) { lo = lo / 2; hi = hi * 2; }   // one distinct price: give it room
  const l0 = Math.log(lo), l1 = Math.log(hi);
  return { lo: lo, hi: hi, x: function (p) {
    const t = (Math.log(Math.max(Number(p) || 0, 1e-9)) - l0) / (l1 - l0);
    return 10 + Math.max(0, Math.min(1, t)) * (PLOT_W - 20);
  } };
}
// Powers of ten inside the span. A NARROW span can contain none, and an axis
// with no labels is not readable -- so it falls back to the endpoints rather
// than shipping a bare strip with nothing to read it against.
function compsTicks(sc) {
  if (!sc) return [];
  const out = [];
  const e0 = Math.floor(Math.log(sc.lo) / Math.LN10), e1 = Math.ceil(Math.log(sc.hi) / Math.LN10);
  for (let e = e0; e <= e1; e++) {
    const v = Math.pow(10, e);
    if (v >= sc.lo && v <= sc.hi) out.push(v);
  }
  return out.length >= 2 ? out : [sc.lo, sc.hi];
}
// Ties STACK. Where a stack fills, the overflow is DISCLOSED rather than
// silently clipped -- D11's rule reused, not a second one invented.
function compsMarks(sorted, sc) {
  const buckets = {};
  (sorted || []).forEach(function (r, i) {
    const x = sc.x(r.soldPrice);
    const k = String(Math.round(x / PLOT_COL));
    (buckets[k] = buckets[k] || []).push({ i: i, r: r, x: x });
  });
  const marks = [], hidden = [];
  Object.keys(buckets).forEach(function (k) {
    buckets[k].forEach(function (m, lvl) {
      if (lvl < PLOT_MAX_STACK) {
        marks.push({ i: m.i, r: m.r, x: m.x, y: PLOT_BASE - lvl * PLOT_STEP, t: compTypeOf(m.r) });
      } else { hidden.push(m); }
    });
  });
  return { marks: marks, hidden: hidden };
}
// SHAPE = listing type, RING = best offer accepted. The two fields are
// ORTHOGONAL -- a Buy It Now can be best-offer-accepted -- so three exclusive
// marks would either lose that or double-count it. Encoding them on separate
// channels is the only rendering that does neither, and it makes best-offer
// density readable for free rather than as a parked feature.
//
// data-p carries the price because a gate must be able to ENUMERATE what the
// plot renders. CQ7's sweep reads prices out of `.cmpprice` spans, which marks
// do not have -- without this the sweep would keep passing while silently
// ceasing to cover the surface where prices are actually drawn.
function compsMarkSVG(m) {
  const x = m.x.toFixed(2), y = m.y;
  const shape = m.t.kind === 'auction'
    ? `<circle cx="${x}" cy="${y}" r="3"/>`
    : (m.t.kind === 'bin'
      ? `<rect x="${(m.x - 2.6).toFixed(2)}" y="${y - 2.6}" width="5.2" height="5.2"/>`
      : `<path d="M ${x} ${y - 3.4} L ${(m.x + 3.4).toFixed(2)} ${y} L ${x} ${y + 3.4} L ${(m.x - 3.4).toFixed(2)} ${y} Z"/>`);
  const ring = m.r.bestOffer ? `<circle class="pmring" cx="${x}" cy="${y}" r="5.6"/>` : '';
  // The suffix is suppressed where the listing TYPE already states the offer:
  // the ring and the type would otherwise report one field twice.
  const lab = compsMoney(m.r.soldPrice, m.r.soldCurrency) + ' · ' + m.t.label +
              ((m.r.bestOffer && !m.t.statesOffer) ? ' · best offer accepted' : '');
  return `<g class="pm pm-${esc(m.t.kind)}${m.r.bestOffer ? ' pm-bo' : ''}" data-p="${esc(String(m.r.soldPrice))}" ` +
    `tabindex="0" role="button" onclick="compsPick(${m.i})"><title>${esc(lab)}</title>${shape}${ring}</g>`;
}
function compsPlotHTML(sorted) {
  const rows = sorted || [];
  if (!rows.length) return '';
  const c = askComparison();
  const askIn = !!(c && !c.mixed && ASK !== null);
  const sc = compsScale(rows.map(function (r) { return r.soldPrice; }).concat(askIn ? [ASK] : []));
  if (!sc) return '';
  const mk = compsMarks(rows, sc);
  const cur = rows[0] ? rows[0].soldCurrency : 'USD';
  const ticks = compsTicks(sc).map(function (v) {
    const tx = sc.x(v).toFixed(2);
    return `<line class="pt" x1="${tx}" y1="${PLOT_BASE + 4}" x2="${tx}" y2="${PLOT_BASE + 9}"/>` +
      `<text class="ptl" x="${tx}" y="${PLOT_BASE + 20}" text-anchor="middle">${esc(compsMoney(v, cur))}</text>`;
  }).join('');
  // The ask is the ONE line here that is not a sale, so it is drawn differently
  // and named -- it cannot be read as a comp (AK6's property, in the plot).
  const ax = askIn ? sc.x(ASK).toFixed(2) : null;
  const askRule = askIn
    ? `<line class="askrule" x1="${ax}" y1="${PLOT_TOP - 6}" x2="${ax}" y2="${PLOT_BASE + 4}"/>` +
      `<text class="askrulel" x="${ax}" y="${PLOT_TOP - 9}" text-anchor="middle">YOUR ASK</text>`
    : '';
  const cut = mk.hidden.length
    ? `<div class="note">${mk.hidden.length} sale${mk.hidden.length === 1 ? '' : 's'} not drawn — ` +
      `the column is full where sales pile up at one price. They are in the list below, and in the counts (D11).</div>`
    : '';
  return `<div class="cmpplot">` +
    `<svg class="plotsvg" viewBox="0 0 ${PLOT_W} ${PLOT_H}" preserveAspectRatio="xMidYMid meet" ` +
    `role="img" aria-label="Every sale, one mark each, spaced by price on a ratio scale">` +
    `<line class="paxis" x1="10" y1="${PLOT_BASE + 4}" x2="${PLOT_W - 10}" y2="${PLOT_BASE + 4}"/>` +
    ticks + askRule + mk.marks.map(compsMarkSVG).join('') + `</svg>` +
    // R6: THE AFFORDANCE COMES FIRST, AND ALONE. It used to be the last clause
    // of the paragraph below -- "...Ticks are dollars. One mark is one sale; tap
    // a mark for the seller's own words." -- and was found by accident. An
    // instruction buried in provenance text reads as provenance, which is the
    // fold rule (HT-D53) applied to itself: the cut goes where the sentence
    // changes job, and this sentence does a different job from the three before
    // it. It sits where a thumb already is, directly under the marks.
    `<div class="plottap">Tap any mark to see that sale</div>` +
    `<div class="plotkey">` +
    `<span class="pk pk-auction"></span>auction` +
    `<span class="pk pk-bin"></span>Buy It Now` +
    `<span class="pk pk-unstated"></span>type not stated` +
    `<span class="pk pk-bo"></span>best offer accepted` +
    `</div>` +
    `<div class="note plotnote">One mark is one sale. Spaced by <b>ratio, not difference</b> — ` +
    `$9 to $29 is the same step as $90 to $290, because grade bands multiply. Ticks are dollars.</div>` +
    cut + `<div id="compsPick"></div></div>`;
}

// THE TAP. Repaints in place, like renderConfirmQuery -- no modal, so the plot
// and the detail stay on one screen. The index is into the SORTED rows, which
// renderComps recomputes identically on every paint.
// BY OBJECT IDENTITY, not by index, and that is what removes the bookkeeping.
// An index is only meaningful against one row set, so it would have to be
// cleared wherever a new one arrives -- compsLookup's success branch, its
// fail(), compsClear and __setComps, which is four places to keep in step and a
// fifth to forget later. That is the drift that left listingType declared in
// COMP_KEYS and dropped by parseComps.
//
// Keying on COMPS.at was the other candidate and is worse: it is nowMs()'s ISO
// string, and the harness fixes the clock, so two row sets in one tick collide.
//
// A reference answers it structurally. A new lookup builds new row objects, so a
// stale pick is simply not found; a re-sort cannot invalidate it; and re-seeding
// the same fixture rows resolves to the same sale, which is correct rather than
// stale. A tap from the previous book can never resolve to a sale on this one --
// brief rule 8's confidently-wrong pairing, in miniature.
let PICKED = null;
function compsPickClear() { PICKED = null; }
function compsPick(i) {
  const rows = (COMPS && COMPS.phase === 'done') ? COMPS.rows : [];
  const sorted = rows.slice().sort(function (a, b) { return a.soldPrice - b.soldPrice; });
  PICKED = (typeof i === 'number' && i >= 0 && sorted[i]) ? sorted[i] : null;
  renderCompsPick();
  return { ok: true, picked: !!PICKED };
}
function compsPickRow() {
  if (!COMPS || COMPS.phase !== 'done' || !PICKED) return null;
  return COMPS.rows.indexOf(PICKED) >= 0 ? PICKED : null;
}
// D10: the seller's title VERBATIM. It is the only grade signal this tier has,
// so a tap gives the words themselves, never a parse of them.
function renderCompsPick() {
  const el = document.getElementById('compsPick');
  if (!el) return;
  const r = compsPickRow();
  if (!r) { el.innerHTML = ''; return; }
  const t = compTypeOf(r);
  el.innerHTML = `<div class="cmprow cmppick">` +
    `<span class="cmpprice">${esc(compsMoney(r.soldPrice, r.soldCurrency))}</span>` +
    `<span class="cmpmeta">${esc(compsDate(r.endedAt))} · ${esc(t.label)}` +
    `${r.bestOffer ? ' · best offer accepted' : ''}</span>` +
    `<span class="cmptitle">${esc(r.title)}</span></div>`;
}

// THE CENSUS THE RULING NEEDS. listingType's values are unmeasured, and it was
// ruled that the census comes free from the next real lookup rather than a paid
// probe. That only works if the RAW values reach a surface: compTypeOf maps
// "FixedPrice" to "Buy It Now", so a reader looking at a real lookup could not
// report back what the provider actually sent.
//
// Raw strings, verbatim, with counts. An unrecognised value is legible here as
// itself rather than as the word the app chose for it -- which is the same
// reason D10 keeps the seller's title verbatim and D4 keeps `raw` beside the
// normalised form. Provenance, so it rides with the provenance line.
function compsTypeCensus(rows) {
  const by = {};
  (rows || []).forEach(function (r) {
    const k = (r && r.listingType) ? String(r.listingType) : '(not stated)';
    by[k] = (by[k] || 0) + 1;
  });
  return by;
}
function compsFootHTML() {
  const d = COMPS.dropped || [];
  const byWhy = {};
  d.forEach(function (x) { byWhy[x.why] = (byWhy[x.why] || 0) + 1; });
  const bits = Object.keys(byWhy).map(function (k) { return byWhy[k] + ' ' + k + (byWhy[k] === 1 ? '' : 's'); });
  const cen = compsTypeCensus(COMPS.rows);
  const cenBits = Object.keys(cen).sort().map(function (k) { return k + ' ' + cen[k]; });
  return (bits.length
      ? `<div class="note">${esc(bits.join(', '))} hidden — the title said so. ` +
        `<button type="button" class="linklike" onclick="compsShowDropped(this)">show what was hidden</button>` +
        `<span class="cmpdrop" hidden>${d.map(function (x) { return `<div class="cmprow"><span class="cmptitle">${esc(x.title)}</span><span class="cmpmeta">${esc(x.why)}</span></div>`; }).join('')}</span></div>`
      : '') +
    `<div class="note">eBay sold listings via Apify · searched “${esc(COMPS.query)}” · ` +
    // C1: a replay costs nothing, and saying it cost $0.40 would be a false
    // statement about the subscriber's own money -- brief rule 7's conflation
    // pointed at the wrong target.
    (COMPS.replay ? `no charge — replayed from a saved response. ` : `about ${esc(compsMoney(COMPS.bound.usd))} for this lookup. `) +
    `No average, no estimate — these are the sales.` +
    (cenBits.length ? `<br><span class="fine">Listing types as the provider sent them: ${esc(cenBits.join(', '))}.</span>` : '') +
    `</div>`;
}
function compsShowDropped(btn) {
  const box = btn && btn.parentElement ? btn.parentElement.querySelector('.cmpdrop') : null;
  if (!box) return { ok: false };
  box.hidden = !box.hidden;
  btn.textContent = box.hidden ? 'show what was hidden' : 'hide';
  return { ok: true, shown: !box.hidden };
}

// ---- R3: THE TRIAGE SURFACE -- grade and asking price ------------------------
// R2b produces a scatter. This turns it into an answer: "you're being asked $10;
// 47 of these 98 sold below that." Both inputs are the HUMAN'S (brief rules 3
// and 5) and neither is ever read from a photo -- ID_REFUSED_KEYS refuses
// asking_price on the model's path, and this is the only door it comes in by.
//
// THE COMPARISON IS AN ASK AGAINST A SCATTER (rule 4 as amended). No $X, no
// midpoint, no average, no "fair", no verdict, no percentile (D13). The user
// reads where their number sits and draws the conclusion; that reading IS the
// product, and it is the thing the app must not do for them.
const GRADES = ['PR', 'FR', 'GD-', 'GD', 'GD+', 'VG-', 'VG', 'VG+',
                'FN-', 'FN', 'FN+', 'VF-', 'VF', 'VF+', 'NM-', 'NM', 'NM+'];
const ASK_NEAREST = 3;        // either side of the ask (Fork B)

let ASK = null;               // the figure the USER wants compared. Never computed.
let ASK_TERMS = '';           // the seller's words, verbatim: "5 for $40" (D12)
let GRADE = '';               // the user's attestation. ADVISORY ONLY (rule 2).
let ASK_SHOWN = '';           // which phase the inputs were rendered for

function askSetPrice(raw) {
  const s = String(raw == null ? '' : raw).replace(/[^0-9.]/g, '');
  const n = Number(s);
  ASK = (s === '' || !(n > 0)) ? null : n;
  renderAskLive();
  renderComps();              // safe: the scatter holds no inputs (see renderAsk)
  return { ok: true, ask: ASK };
}
// D12: the terms are TEXT, kept verbatim. Nothing parses them, nothing divides
// them. They exist to say where the user's figure came from.
function askSetTerms(raw) { ASK_TERMS = String(raw == null ? '' : raw).trim(); renderAskLive(); renderComps(); return { ok: true, terms: ASK_TERMS }; }
// Rule 2 as amended: grade is ADVISORY. It deliberately does NOT call
// renderComps -- it must not touch a comp, an order or a count, and the surest
// way to guarantee that is to give it no path to the scatter at all.
function askSetGrade(raw) {
  const s = String(raw == null ? '' : raw);
  GRADE = (GRADES.indexOf(s) >= 0) ? s : '';
  renderAskLive();
  return { ok: true, grade: GRADE };
}
function askClear() { ASK = null; ASK_TERMS = ''; GRADE = ''; ASK_SHOWN = ''; }
function askState() { return { ask: ASK, terms: ASK_TERMS, grade: GRADE }; }

// D11: where the cap cuts a group that shares a price, say what it cut. A
// cluster at one price is the densest fact on the surface; hiding it behind
// three arbitrary examples loses the finding, not an edge case.
function askNearest(list, cap) {
  const shown = list.slice(0, cap), rest = list.slice(cap);
  let truncated = null;
  if (shown.length && rest.length) {
    const edge = shown[shown.length - 1].soldPrice;
    const more = rest.filter(function (r) { return r.soldPrice === edge; }).length;
    if (more > 0) {
      const here = shown.filter(function (r) { return r.soldPrice === edge; }).length;
      truncated = { price: edge, shown: here, total: here + more };
    }
  }
  return { shown: shown, truncated: truncated };
}

function askComparison() {
  if (!COMPS || COMPS.phase !== 'done' || ASK === null) return null;
  const rows = COMPS.rows;
  if (!rows.length) return null;
  const curs = [];
  rows.forEach(function (r) { if (curs.indexOf(r.soldCurrency) < 0) curs.push(r.soldCurrency); });
  // Fork F: a scatter in two currencies is already incomparable, so placing an
  // ask in it would invent a comparison. D10's shape, applied to currency:
  // where the thing that would make the numbers comparable is absent, say so.
  if (curs.length > 1) return { mixed: true, currencies: curs.slice() };
  const recent = function (a, b) { return String(b.endedAt).localeCompare(String(a.endedAt)); };
  const below = rows.filter(function (r) { return r.soldPrice < ASK; })
                    .sort(function (a, b) { return (b.soldPrice - a.soldPrice) || recent(a, b); });
  const above = rows.filter(function (r) { return r.soldPrice > ASK; })
                    .sort(function (a, b) { return (a.soldPrice - b.soldPrice) || recent(a, b); });
  const at = rows.filter(function (r) { return r.soldPrice === ASK; });
  // below + at + above === total, always. Asserted, because an off-by-one at a
  // tie boundary is invisible on a surface and wrong in the only number here.
  return { mixed: false, currency: curs[0], ask: ASK, total: rows.length,
           below: below.length, at: at.length, above: above.length,
           nearestBelow: askNearest(below, ASK_NEAREST),
           nearestAbove: askNearest(above, ASK_NEAREST) };
}

// The ONE number on this surface that is not a sale (CQ7 as extended), and it
// carries its own label so it cannot be read as one.
function askMarkerHTML() {
  const c = askComparison();
  if (!c || c.mixed) return '';
  const src = ASK_TERMS ? 'your figure, from: ' + ASK_TERMS : 'the price you were quoted';
  return `<div class="cmprow askrow">` +
    `<span class="cmpprice">${esc(compsMoney(ASK, c.currency))}</span>` +
    `<span class="cmpmeta askmark">YOUR ASK</span>` +
    `<span class="cmptitle">${esc(src)}${GRADE ? ' · you graded it ' + esc(GRADE) : ''}</span>` +
    `</div>`;
}

// THE INPUTS ARE RENDERED ONCE AND NEVER REBUILT WHILE TYPING. renderComps
// rebuilds #compsBox on every keystroke; if the inputs lived there, each
// character would destroy and recreate the field and the caret would jump to
// the end. renderConfirmQuery already exists for exactly this reason. Here the
// separation is structural: the inputs are in #askBox, which renderComps never
// touches, and this function rebuilds only when the PHASE changes.
function renderAsk() {
  const el = document.getElementById('askBox');
  if (!el) return;
  const phase = (COMPS && COMPS.phase === 'done' && COMPS.rows.length) ? 'done' : 'none';
  if (phase === ASK_SHOWN) { renderAskLive(); return; }
  ASK_SHOWN = phase;
  if (phase === 'none') { el.innerHTML = ''; return; }
  const opts = ['<option value="">not graded</option>'].concat(GRADES.map(function (g) {
    return `<option value="${esc(g)}"${g === GRADE ? ' selected' : ''}>${esc(g)}</option>`;
  })).join('');
  el.innerHTML = `<div class="askbox">` +
    `<div class="row"><div><label for="askPrice">Asking price <small>(theirs, not the cover price)</small></label>` +
    `<input id="askPrice" type="text" inputmode="decimal" placeholder="what they want for it" ` +
    `value="${esc(ASK === null ? '' : String(ASK))}" oninput="askSetPrice(this.value)"></div>` +
    `<div><label for="askGrade">Your grade <small>(advisory)</small></label>` +
    `<select id="askGrade" onchange="askSetGrade(this.value)">${opts}</select></div></div>` +
    `<label for="askTerms">If it's a bulk rate, their words</label>` +
    `<input id="askTerms" type="text" placeholder="e.g. 5 for $40 — typed as they said it" ` +
    `value="${esc(ASK_TERMS)}" oninput="askSetTerms(this.value)">` +
    `<div class="note">The price above is <b>yours to decide</b>. This app never divides a bulk rate into a per-book figure — ` +
    `that would be a number the seller never said (D12).</div>` +
    `<div id="askLive"></div></div>`;
  renderAskLive();
}

// D13: COUNTS, never percentiles. A count is checkable by pointing at rows; a
// ratio is a verdict the user cannot verify and reads as a score out of a
// hundred -- which invites "so it's about average", the one inference D8 refuses.
function renderAskLive() {
  const el = document.getElementById('askLive');
  if (!el) return;
  const c = askComparison();
  if (!c) { el.innerHTML = ''; return; }
  if (c.mixed) {
    el.innerHTML = `<div class="note warnline">These sales are in more than one currency (` +
      `${esc(c.currencies.join(', '))}), so there is nothing to place your price against. ` +
      `Narrow the search to one marketplace and look again.</div>`;
    return;
  }
  const side = function (label, near) {
    if (!near.shown.length) return '';
    const rows = near.shown.map(compsRowHTML).join('');
    const cut = near.truncated
      ? `<div class="note">${near.truncated.shown} of ${near.truncated.total} at ` +
        `${esc(compsMoney(near.truncated.price, c.currency))} shown — the rest sold at that same price (D11).</div>`
      : '';
    return `<div class="asknear"><div class="asknearh">${esc(label)}</div>${rows}${cut}</div>`;
  };
  el.innerHTML =
    `<div class="askcount"><b>${c.below}</b> sold below · <b>${c.at}</b> at your price · <b>${c.above}</b> above` +
    `<span class="fine"> — of ${c.total} in the last ${COMPS_WINDOW_DAYS} days</span></div>` +
    side('Nearest below', c.nearestBelow) +
    side('Nearest above', c.nearestAbove);
}
// ---- BUILD IDENTITY: which version is running, and what changed -------------
// D1's service-worker deferral was SPLIT (2026-09-14). This is the legibility
// half and it is ENTIRELY page-side -- no worker, no cache, no manifest, no
// icons. The worker follows as its own slice if offline is ever wanted for its
// own sake; the premise "if installability is wanted" was asked and answered no.
//
// D14 -- THE GATE SHIPS BEFORE THE MECHANISM. HealthTracker shipped the worker
// first with a hand-bumped version integer, missed it on every slice after Phase
// 0, and served a frozen first-deploy shell with nothing to say so. Here the
// drift gate exists while there is still no cache that could serve one, so the
// failure class is closed before the mechanism that makes it dangerous arrives.
//
// WHY A NOTICE WORKS WITH NO WORKER: there is no app-controlled cache, so a load
// fetches current bytes and the notice fires on it. The worker is what would
// CREATE the stale-shell problem it then solves.
const APP_VERSION = '0.9.1';
const VERSION_KEY = 'collectibles-version';   // PFX1: every storage key is prefixed

// One line per release, newest LAST. The newest entry's `v` must equal
// APP_VERSION, and EVERY entry carries `d` -- both enforced by check-version.sh.
// HealthTracker exempts entries predating its date convention; there are none
// here, so the exemption would protect nobody and the field is mandatory from
// the first line.
//
// R1, R2b AND R3 SHIPPED UNVERSIONED, and no entries are invented for them.
// Guessing dates or writing notes for releases nobody stamped is the same
// fabrication this app refuses everywhere else -- D8 will not synthesise a price
// the data does not contain, D12 will not divide a quote the seller did not give.
// The record says they shipped unversioned and stops.
const VERSION_LOG = [
  { v: '0.1.0', d: '2026-09-14', note: 'Version numbers. The app now says which build it is running, and tells you what changed when a new one arrives. Identification, sold comps and the asking-price comparison all shipped before this, unversioned; nothing about them changes here.' },
  { v: '0.2.0', d: '2026-09-14', note: 'A want list. Type the books you are hunting into Settings, one per line, and the draft tells you when the book in your hand is one of them. Matching forgives spelling and format — "The Amazing Spider-Man #129" and "Amazing Spider-Man 129" are the same want — but the issue must match, because a different issue is a different book. It is a prompt to look, never a claim, and nothing is recorded before you confirm the reading. This is also the first thing the app saves to your device besides your keys, so the storage line in Settings now matters to more than a capture.' },
  { v: '0.3.0', d: '2026-09-14', note: 'Sold comps are now drawn, not just listed. Every sale is one mark, spaced by price — and spaced by RATIO rather than difference, because grade bands multiply: $9 to $29 is the same step as $90 to $290. Clusters with gaps between them are different markets, and the gaps are the grade boundaries this data refuses to state; your eye finds them, the app does not guess at them. Mark shapes show how each sale closed — auction, Buy It Now, or a type the provider did not state — and a ring means a best offer was accepted. Tap any mark for the seller\'s own words. Nothing is fitted, smoothed or averaged: 98 sales are enough to SEE the shape and not enough to characterise it. The full list and the explanations now fold away, so the numbers stop competing with the prose for the same screen.' },
  { v: '0.4.0', d: '2026-09-15', note: 'Bigger, clearer type. The app declared a readable 16px base and then opted out of it almost everywhere — eleven different text sizes, eight of them smaller than that base, and the very smallest were the plot’s own axis labels. There are now four sizes and a floor: nothing is smaller than 12px. Two numbers moved up to where they belong — the count of sales above and below your price, which is the whole answer this app exists to give, and the line stating how many sales and over what window. Form fields are 16px, which also stops the phone zooming in every time you tap one. And the plot now says “Tap any mark to see that sale” in its own line under the marks, instead of hiding that at the end of a paragraph about spacing.' },
  { v: '0.5.0', d: '2026-09-15', note: 'The list of every sale has stopped sitting under the plot. The plot IS the list now: tap a mark for that sale, and the nearest sales to your price stay beside it as before. When you do want to read all of them, the button says how many it is about to show — “List all 84 sales” — and you can put it away again. Nothing was removed: the sellers’ own words are still the only grade signal there is, so they stay one tap away rather than filling the screen by default.' },
  { v: '0.6.0', d: '2026-09-15', note: 'A way to save one sold-comps response and replay it instead of calling the provider. This is TEST MACHINERY rather than an offline mode, and it is built to stay that way: a lookup costs about $0.40 and returns the same sales every time, so checking a layout change should not cost money. It replays ONLY when you arm it, and arming lasts one session — a saved response sitting in Settings is never on its own a reason to skip a call, because a testing aid that fires without being asked would make every measurement taken afterwards untrustworthy while nothing looked wrong. A replayed result SAYS SO where the numbers are, with the date it was captured, because those sales were a 90-day window on that date and the window has moved since. The cost line reads “no charge” rather than billing you for a call that never happened, and the saved response is kept outside your data, so an export cannot carry it.' },
  { v: '0.7.0', d: '2026-09-15', note: 'The sales the app filtered out were never actually hidden. One line of styling overrode the mark that closes them, so every excluded listing — lots, reprints, collections — sat open on the page beneath a button offering to show them, and tapping that button changed nothing but its own label. On a real lookup that was 1332 pixels of it: more than two thirds of the whole sold-comps panel, with the chart squeezed into a seventh of the space. It is closed now until you ask for it, the button does what it says in both directions, and the repair is written so that anything else in this app marked hidden stays hidden. Found by loading a real 100-sale response for the first time; on the small test data it was a strip too short to notice.' },
  { v: '0.8.0', d: '2026-09-15', note: 'Sales that ended in an accepted offer are drawn correctly. eBay reports those as their own listing type, which this app had never seen before and so drew as “type not recognised” — a fifth of the sales on a real lookup, marked as an unknown when the app could in fact tell exactly what they were: a Buy It Now whose price was negotiated. They now draw as Buy It Now with the ring that has always meant an accepted offer, so the shape says how it sold and the ring says how the price was reached, without saying it twice. The listing types the app does not recognise still name themselves on the surface rather than being quietly folded into a default — that is the point of showing them at all, and it is now checked on the drawn mark rather than only in the data underneath.' },
  { v: '0.9.0', d: '2026-09-15', note: 'Filters, for narrowing the list to the sales you care about. Buttons appear for what the sellers actually wrote — “title mentions CGC”, “title mentions a letter grade”, and so on — and a button only appears if some sale matches it, with the count beside it. Tap more than one and you get all of them, not the overlap. The labels say what was MATCHED rather than what it might mean: a title saying “CGC READY” is usually a raw book hoping to be graded, so the app tells you the words are there and leaves the reading to you. The chart itself never changes. Filtering the list does not remove a single mark from it, because the interesting thing about these sales is where the expensive ones sit against the cheap ones, and that is only visible with all of them on screen at once.' },
  { v: '0.9.1', d: '2026-09-16', note: 'Saving a response for replay now always answers. Each tap on Save gets its own line on the card, stamped with the time, so a second tap that ends the same way no longer looks like a button that does nothing. A paste that was cut short now says so, instead of blaming the provider for text you pasted. And if storage is running in memory only this session (the badge at the top says so), the save refuses and tells you why, instead of appearing to do nothing.' },
];

// Numeric per segment, so 0.2.0 < 0.10.0 -- a string compare gets that backwards
// and would silently stop showing notices after the ninth release.
function cmpVersion(a, b) {
  const pa = String(a).split('.').map((n) => parseInt(n, 10) || 0);
  const pb = String(b).split('.').map((n) => parseInt(n, 10) || 0);
  for (let i = 0; i < Math.max(pa.length, pb.length); i++) {
    const x = pa[i] || 0, y = pb[i] || 0;
    if (x < y) return -1;
    if (x > y) return 1;
  }
  return 0;
}
// Every version in (from, to] -- a returning user who skipped releases gets the
// ACCUMULATED changelog, not just the newest line.
// The optional `log` is what makes accumulation TESTABLE TODAY. With one entry
// shipped, a multi-version jump is unreachable against the real log, and an
// assertion on it would be vacuous -- HT-D60 Clause 4, the same shape as a
// fixture with no ties in it. D14's argument applied to a helper: exercise the
// accumulation before there is anything to accumulate, because the first real
// multi-version jump is the one that would silently show only the newest line.
function versionNotesBetween(fromV, toV, log) {
  log = log || VERSION_LOG;
  return log.filter((e) =>
    (fromV ? cmpVersion(e.v, fromV) > 0 : e.v === toV) && cmpVersion(e.v, toV) <= 0);
}
function versionNotice(stored) {
  stored = stored || null;
  if (stored && cmpVersion(stored, APP_VERSION) >= 0) return null;   // unchanged, or a downgrade
  return { from: stored, to: APP_VERSION, notes: versionNotesBetween(stored, APP_VERSION) };
}
function versionLine(version, log) {
  version = version || APP_VERSION;
  log = log || VERSION_LOG;
  const entry = (log || []).filter((e) => e && e.v === version)[0];
  const d = (entry && typeof entry.d === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(entry.d)) ? entry.d : null;
  return 'collectibles v' + version + (d ? ' · released ' + d : '');
}

// Fires ONCE per version change. The write happens before the render, so a throw
// in rendering cannot make the notice repeat on every load.
function checkVersionNotice() {
  let stored = null;
  try { stored = Store.readRaw(VERSION_KEY); } catch (e) {}
  const notice = versionNotice(stored);
  Store.writeAux(VERSION_KEY, APP_VERSION);
  if (!notice) return null;
  // A GENUINE first run shows no "updated" notice. APP_SOURCE is a truer test than
  // "nothing stored": it separates a fresh install ('empty') from a RESTORE onto a
  // new device ('restored'), and from the people already running the unversioned
  // builds ('store') -- who SHOULD see it, because for them this is an update.
  if (!stored && APP_SOURCE === 'empty') return null;
  renderVersionNotice(notice);
  return notice;
}
function renderVersionNotice(notice) {
  const el = document.getElementById('versionNotice');
  if (!el || !notice) return;
  const head = notice.from
    ? 'Updated from v' + esc(notice.from) + ' to v' + esc(notice.to)
    : 'Updated to v' + esc(notice.to);
  const notes = (notice.notes || []).map(function (e) {
    return `<div class="vnrow"><b>v${esc(e.v)}</b> — ${esc(e.note)}</div>`;
  }).join('');
  el.innerHTML = `<div class="vnhead">${esc(head)}</div>${notes}` +
    `<button class="btn" onclick="dismissVersionNotice()">Dismiss</button>`;
  el.style.display = 'block';
}
function dismissVersionNotice() {
  const el = document.getElementById('versionNotice');
  if (el) { el.style.display = 'none'; el.innerHTML = ''; }
  return { ok: true };
}
// Reference information, not a control -- so it lives in `.about` and NOWHERE
// else. Settings already carries the schema version and the load source, and a
// second copy of one value is a pair that can disagree.
function renderBuildLine() {
  const el = document.getElementById('buildLine');
  if (el) el.textContent = versionLine();
}

// ---- the no-key floor (D2 Fork G1) ------------------------------------------
// Copy the prompt into your own assistant, paste the reply back. HT-D63 is the
// warning this is built against: HealthTracker's floor sat DEAD for weeks because
// its gate asserted that a box EXISTED rather than that it held the prompt, and
// the app told users to copy from an empty box. So: every box is filled by
// attribute (a third card would be filled too, not silently join the dead one),
// filled UNCONDITIONALLY before any copy is attempted, and a rejected clipboard
// write is REPORTED rather than swallowed.
function promptBoxes() { return Array.prototype.slice.call(document.querySelectorAll('[data-prompt-box]')); }
function renderPromptCard() {
  promptBoxes().forEach(function (box) { box.value = ID_PROMPT; });
  Array.prototype.forEach.call(document.querySelectorAll('[data-prompt-version]'),
    function (v) { v.textContent = 'template v' + ID_TEMPLATE_VERSION; });
}
// The box the FINGER was on, not the first in the document: from Settings, the
// first box may sit in a hidden pane, and a hidden textarea cannot be selected.
function promptBoxFor(from) {
  const boxes = promptBoxes();
  let n = (from && from.parentElement) ? from.parentElement : null;
  while (n) {
    const own = n.querySelector ? n.querySelector('[data-prompt-box]') : null;
    if (own) return own;
    n = n.parentElement;
  }
  const visible = boxes.filter(function (b) { return b.offsetParent !== null; });
  return visible[0] || boxes[0] || null;
}
function copyPrompt(from) {
  const text = ID_PROMPT;
  const box = promptBoxFor(from);
  if (box) box.value = text;                     // FILL FIRST, whatever the clipboard does
  let done = false;
  if (box && box.offsetParent !== null) {
    try {
      box.focus(); box.select();
      try { box.setSelectionRange(0, text.length); } catch (e) {}
      done = document.execCommand('copy');
    } catch (e) { done = false; }
  }
  if (done) { toast('Prompt copied'); return { ok: true, via: 'selection', chars: text.length }; }
  if (navigator.clipboard && navigator.clipboard.writeText) {
    navigator.clipboard.writeText(text).then(
      function () { toast('Prompt copied'); },
      function () { toast('Copy did not work — the prompt is in the box, select it and copy'); });
    return { ok: true, via: 'clipboard', chars: text.length };
  }
  toast('The prompt is in the box — select it and copy');
  return { ok: true, via: 'manual', chars: text.length };
}

// The contract itself, and the seam filled (R1/D2). `setVisionContract` stays a
// test seam; the gates clear it to prove the no-contract guard still holds.
const IDENTITY_CONTRACT = {
  version: ID_TEMPLATE_VERSION,
  prompt: ID_PROMPT,
  parse: parseIdentity,
  render: renderIdentityHTML,
  accept: identityAccept,
  acceptLabel: 'Confirm',
};
VISION = IDENTITY_CONTRACT;

// ---- observation surfaces ----------------------------------------------------
function renderBadge() {
  const el = document.getElementById('storeBadge');
  if (!el) return;
  const s = Store.status();
  el.textContent = s.message;
  el.style.color = s.ok ? 'var(--good)' : 'var(--warn)';
}
// D9: a credential field exists only where a call exists that uses it.
//
// The PRICES role keeps all of its machinery -- the provider row, pacing, the
// `auth: 'none'` server-move proof, the credential store -- but it has NO
// settings card, because no price lookup is built. An empty input for a
// provider we are not using is a dead end that sends the person testing off to
// buy a credential (reported from the device 2026-09-13: "I went looking for
// how to get a PriceCharting token because the app asked for one").
//
// The exception is a token ALREADY SAVED by an earlier build. Removing the card
// must not STRAND it somewhere it cannot be seen or deleted, so it appears here
// with a way out -- and only when it exists.
function renderDataStatus() {
  const el = document.getElementById('dataStatus');
  if (!el || !APP_STATE) return;
  const rows = [
    ['storage tier',   Store.tier],
    ['schema version', APP_STATE.version],
    ['load source',    APP_SOURCE],
    ['vision key',     credConfigured('vision') ? 'saved (not in your data)' : 'none'],
  ];
  let html = rows.map(([k, v]) =>
    `<div class="kv"><span class="k">${esc(k)}</span><span class="v">${esc(v)}</span></div>`).join('');
  if (credConfigured('prices')) {
    html += `<div class="kv"><span class="k">price-guide token</span><span class="v">saved by an earlier build ` +
      `<button type="button" class="linklike" onclick="credClear('prices')">remove it</button></span></div>` +
      `<div class="note">No price lookup is built, so nothing uses this token. It is shown only so you can delete it.</div>`;
  }
  el.innerHTML = html;
}
function refresh() {
  renderBadge(); renderDataStatus();
  ROLES.forEach(function (r) { renderCred(r); });
  // HT-D63: the prompt boxes are filled on EVERY render, unconditionally. The
  // no-key floor died in HealthTracker because filling them was a step that
  // quietly stopped happening, while the app went on telling people to copy from
  // a box that was empty.
  renderPromptCard();
  renderConfirmed();
  renderComps();
  renderAsk();
  renderBuildLine();
  renderWantsCard();
  renderReplayCard();
  renderCaptureBtn(); renderCaptureOutcome();
}
function openSettings() {
  const p = document.getElementById('settingsPanel'), s = document.getElementById('settingsScrim');
  if (p) p.style.display = 'flex';
  if (s) s.style.display = 'block';
  return { ok: true };
}
function closeSettings() {
  const p = document.getElementById('settingsPanel'), s = document.getElementById('settingsScrim');
  if (p) p.style.display = 'none';
  if (s) s.style.display = 'none';
  return { ok: true };
}
function paceReset() { Object.keys(PACE).forEach(function (k) { delete PACE[k]; }); }   // test seam

function main() {
  boot();
  requestPersistentStorage();
  refresh();
  // AFTER boot(), which is what sets APP_SOURCE -- the first-run suppression
  // reads it, so calling this earlier would make every load look like a fresh
  // install and show nobody the notice.
  checkVersionNotice();
}

// Console seam for review and testing.
window.CT = {
  Store, boot, refresh, exportJSON, parseImport, restore, normalizeState, emptyState, cleanJSON, esc,
  STATE_KIND, SCHEMA_VERSION, keys: { STORE_KEY, PRERESTORE_KEY, CRED_PREFIX },
  setClock, nowMs, todayKey, localDate,
  // D1 -- providers, credentials, egress
  PROVIDERS, ROLES, ROLE_DEFAULT, egress, pace, paceReset, redact, providerMessage,
  credRead, credPatch, credClear, credSettings, credKeyIssue, credSetStatus, credConfigured, credStatusLine,
  credMask, credSave, credCap, credCount, credTest, credPaint, renderCred, saveCred,
  setCallTimeout, setTestTimeout,
  // the vision contract seam (unruled) and the one door
  setVisionContract, visionReady, visionPrefix, openCaptureResult, doReplyPaste, captureResult,
  captureDiscard, captureAccept, resultReadoutHTML, renderCaptureResult,
  // HT-D51 -- the outcome modal
  captureOutcomeState, renderCaptureOutcome, captureOutcomeDismiss, captureRetry, capturePasteInstead,
  // the capture chain (HT-D47/D48/D58/D64/D65)
  byokCapture, byokFallback, onCaptureFile, captureSourceOf, byokBusyState, byokBusyClear, byokCancel,
  byokTrace, byokTraceReset, byokTraceLine, byokTimeouts, byokNoteVerdict, BYOK_RETRY_MIN_MS,
  byokDownscale, byokDecodeBitmap, byokDecodeImage, byokEncode, byokBounds, byokHeicMessage,
  setByokBitmapLease, setByokDecodeTimeout, BYOK_MAX_EDGE, BYOK_JPEG_Q, BYOK_MIN_DATAURL,
  visionCaps, visionBody, visionCall, BYOK_MAX_TOKENS, pricesPing, PRICES_PING_QUERY,
  renderCaptureBtn, openSettings, closeSettings,
  // R1 / D2 -- the identification contract, the confirm surface and the floor
  IDENTITY_CONTRACT, ID_TEMPLATE_VERSION, ID_PROMPT, ID_SAMPLE, ID_FIELDS, ID_FIELD_KEYS, ID_MARKERS,
  // D15 -- the want-list: a capture-time filter, and the app's FIRST persistence
  WANT_MAX, wantNormTitle, wantNormIssue, parseWantLine, parseWants, wantsList,
  wantsSave, wantMatch, wantFlagHTML, renderWantFlag, renderWantsCard,
  ID_REFUSED_KEYS, parseIdentity, identityQuery, identitySetField, identityToggleMarker,
  identityAccept, renderIdentityHTML, confirmedIdentity, clearConfirmed, renderConfirmed, copyQuery,
  // R2b / D10 -- sold comps: one scatter, no groups, no range
  COMPS_WINDOW_DAYS, COMPS_COUNT, COMPS_MIN_SHOWN, COMPS_EXCLUDE, COMPS_NEVER_SENT, COMP_KEYS,
  // R5 -- the row contract is DERIVED from this, so used-but-undeclared cannot occur
  COMP_FIELDS, COMP_TYPES, compTypeOf,
  compsDefaultQuery, compsQuery, compsSetQuery, compsResetQuery, compsBody, compsBound,
  parseComps, compsFilter, compsBodyIsClean, compsLookup, compsClear, renderComps, compsPing,
  compsRowHTML, compsShowDropped, compsMoney, compsDate, compsListHTML, __setComps,
  // R6 -- the list is summoned, never permanent
  compsListShown, compsListToggle, compsListBlockHTML,
  // R6b -- the filters COUNT AND LIST; the plot carries no selection state,
  // because at 5.31px no channel could carry one (see COMPS_CATS' comment).
  COMPS_CATS, compsFilterCats, compsFiltersActive, compsFilterToggle,
  compsFilterClear, compsFilterMatch, compsSelected, compsFilterHTML,
  // C1 -- response replay, TEST MACHINERY. Held outside the state object so an
  // export cannot carry it, and armed in memory so it cannot outlive a reload.
  REPLAY_KEY, replayRead, replaySave, replayClear, replayArmed, replaySetArmed,
  replayNoticeHTML, renderReplayCard, replaySaveFromBox, replayArmFromBox, replayForget,
  // R5 -- the distribution, drawn. Pure emitters, so the markup is gateable
  // without a surface; the tap repaints in place.
  PLOT_W, PLOT_H, PLOT_MAX_STACK, compsScale, compsTicks, compsMarks, compsMarkSVG,
  compsPlotHTML, compsPick, compsPickClear, compsPickRow, renderCompsPick, compsTypeCensus,
  compsState: () => COMPS,
  // R3 / D11-D13 -- the triage surface: an ask against a scatter
  GRADES, ASK_NEAREST, askSetPrice, askSetTerms, askSetGrade, askClear, askState,
  askNearest, askComparison, askMarkerHTML, renderAsk, renderAskLive,
  promptBoxes, promptBoxFor, renderPromptCard, copyPrompt,
  // D1-split / D14 -- build identity: which version is running, and what changed
  APP_VERSION, VERSION_LOG, VERSION_KEY, cmpVersion, versionNotesBetween,
  versionNotice, versionLine, checkVersionNotice, renderVersionNotice,
  dismissVersionNotice, renderBuildLine,
  state: () => APP_STATE,
  // Read-only seam. checkVersionNotice suppresses the notice on a GENUINE first
  // run, and APP_SOURCE is what distinguishes that from a restore or from the
  // people already running the unversioned builds -- so a gate cannot tell those
  // three apart without being able to read it.
  appSource: () => APP_SOURCE,
  resave: () => Store.saveState(APP_STATE),
};

if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', main);
else main();
