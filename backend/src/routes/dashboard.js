// Admin dashboard: GET /dashboard?key=… (HTML)
// Views: overview | crm | creators | journeys | bookings, plus per-lead call and
// document pages. Everything needs the key: it shows phone numbers and IDs.
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { Router } from 'express';
import express from 'express';
import { formatMoney } from '../currency.js';
import { STAGES, stageOf } from '../leads.js';
import { DOCS } from '../documents.js';

const MONTHS = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const DOC_LABEL = { passport: 'Passport', residence: 'Residence visa', bank: 'Bank statement', photo: 'Photo' };
const SOURCE_LABEL = { planner: 'Budget plan', going: 'I’m going', documents: 'Document check', ammachi: 'Ammachi chat' };
const SOURCES = Object.keys(SOURCE_LABEL);
const CALL_LABEL = { simulated: 'Call simulated', ringing: 'Ringing', in_progress: 'On call', completed: 'Call completed', failed: 'Call failed', no_phone: 'No phone' };
const STAGE_TONE = { 'High probability': 'green', Called: 'blue', Calling: 'blue', Qualified: 'amber', Contactable: 'gray', Interested: 'gray' };

export function dashboardKey(dataDir) {
  if (process.env.DASHBOARD_KEY?.trim()) return process.env.DASHBOARD_KEY.trim();
  const file = path.join(dataDir, 'dashboard-key.txt');
  if (fs.existsSync(file)) return fs.readFileSync(file, 'utf8').trim();
  const key = crypto.randomBytes(9).toString('base64url');
  fs.writeFileSync(file, key);
  return key;
}

const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);
const date = (iso) => (iso ? new Date(iso).toLocaleString('en-GB', { day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' }) : '—');
const dateShort = (iso) => (iso ? new Date(iso).toLocaleDateString('en-GB', { day: 'numeric', month: 'short', year: 'numeric' }) : '—');
const num = (n) => Number(n || 0).toLocaleString('en');
const aed = (n) => esc(formatMoney(Math.round(n || 0), 'AED'));
const badge = (text, tone = 'gray') => `<span class="badge ${tone}">${esc(text)}</span>`;
const stageBadge = (l) => badge(stageOf(l), STAGE_TONE[stageOf(l)] ?? 'gray');
const scoreCell = (n) => {
  const v = Math.max(0, Math.min(100, Number(n) || 0));
  return `<div class="score"><span class="track"><span class="fill ${v >= 70 ? 'ok' : v >= 40 ? 'mid' : 'low'}" style="width:${v}%"></span></span><span class="num">${v}</span></div>`;
};

// Monoline 16px icons (no emoji).
const ICON = {
  overview: '<path d="M3 13h4v8H3zM10 9h4v12h-4zM17 4h4v17h-4z"/>',
  crm: '<path d="M4 4h16v4H4zM4 10h16v4H4zM4 16h10v4H4z"/>',
  creators: '<circle cx="9" cy="8" r="3.5"/><path d="M2.5 20c.8-3.6 3.4-5.5 6.5-5.5s5.7 1.9 6.5 5.5"/><path d="M16 4.5a3.5 3.5 0 0 1 0 7M18.5 14.8c1.7.8 2.7 2.6 3 5.2"/>',
  journeys: '<path d="M9 4 3 6v14l6-2 6 2 6-2V4l-6 2-6-2z"/><path d="M9 4v14M15 6v14"/>',
  bookings: '<path d="M6 3h12v18l-3-2-3 2-3-2-3 2z"/><path d="M9 8h6M9 12h6"/>',
  download: '<path d="M12 4v11M7 10l5 5 5-5M5 20h14"/>',
  back: '<path d="M15 5l-7 7 7 7"/>',
};
const icon = (name) => `<svg viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${ICON[name]}</svg>`;

const CSS = `
:root{--bg:#f7f7f8;--surface:#fff;--line:#e4e4e7;--line2:#f0f0f2;--ink:#18181b;--ink2:#3f3f46;--muted:#71717a;--faint:#a1a1aa;
--green:#15803d;--green-bg:#f0fdf4;--amber:#b45309;--amber-bg:#fffbeb;--red:#b91c1c;--red-bg:#fef2f2;--blue:#1d4ed8;--blue-bg:#eff6ff}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--ink);font:13.5px/1.5 ui-sans-serif,system-ui,-apple-system,"Segoe UI",Roboto,"Helvetica Neue",Arial,sans-serif;-webkit-font-smoothing:antialiased}
a{color:inherit}
.layout{display:grid;grid-template-columns:224px 1fr;min-height:100vh}
.side{background:var(--surface);border-right:1px solid var(--line);padding:18px 12px;position:sticky;top:0;height:100vh;display:flex;flex-direction:column}
.brand{display:flex;align-items:center;gap:10px;padding:4px 10px 18px;font-weight:650;font-size:14.5px}
.brand i{width:24px;height:24px;border-radius:6px;background:var(--ink);display:inline-block}
.brand small{display:block;color:var(--muted);font-weight:400;font-size:12px;margin-top:-2px}
.nav a{display:flex;align-items:center;gap:10px;padding:7px 10px;border-radius:6px;text-decoration:none;color:var(--ink2);margin-bottom:1px}
.nav a:hover{background:var(--line2)}
.nav a.on{background:#f4f4f5;color:var(--ink);font-weight:600}
.nav a svg{color:var(--muted)}.nav a.on svg{color:var(--ink)}
.nav .count{margin-left:auto;color:var(--faint);font-size:12px;font-variant-numeric:tabular-nums}
.side .foot{margin-top:auto;padding:10px;color:var(--muted);font-size:12px;border-top:1px solid var(--line2)}
.status{display:flex;align-items:center;gap:7px;margin-top:6px}.dot{width:7px;height:7px;border-radius:50%;background:var(--faint)}.dot.on{background:var(--green)}.dot.warn{background:#d97706}
main{min-width:0}
.head{display:flex;align-items:flex-end;justify-content:space-between;gap:16px;padding:26px 32px 18px}
.head h1{margin:0;font-size:20px;font-weight:650;letter-spacing:-.01em}
.head p{margin:3px 0 0;color:var(--muted)}
.btn{display:inline-flex;align-items:center;gap:6px;height:32px;padding:0 12px;border:1px solid var(--line);border-radius:6px;background:var(--surface);color:var(--ink);font:inherit;font-weight:550;text-decoration:none;cursor:pointer;white-space:nowrap}
.btn:hover{background:var(--line2)}
.btn.primary{background:var(--ink);border-color:var(--ink);color:#fff}.btn.primary:hover{background:#27272a}
.btn.sm{height:28px;padding:0 10px;font-size:12.5px}
.content{padding:0 32px 40px}
.kpis{display:grid;grid-template-columns:repeat(5,minmax(0,1fr));gap:12px;margin-bottom:20px}
.kpi{background:var(--surface);border:1px solid var(--line);border-radius:8px;padding:14px 16px}
.kpi .label{color:var(--muted);font-size:12.5px}
.kpi .value{font-size:22px;font-weight:650;letter-spacing:-.01em;margin-top:4px;font-variant-numeric:tabular-nums}
.kpi .sub{color:var(--muted);font-size:12px;margin-top:2px}
.card{background:var(--surface);border:1px solid var(--line);border-radius:8px;margin-bottom:16px;overflow:hidden}
.card-head{display:flex;align-items:center;justify-content:space-between;gap:12px;padding:12px 16px;border-bottom:1px solid var(--line)}
.card-head h2{margin:0;font-size:14px;font-weight:600}
.card-body{padding:14px 16px}
.grid2{display:grid;grid-template-columns:minmax(0,2fr) minmax(0,1fr);gap:16px}
table{width:100%;border-collapse:collapse}
th{text-align:left;font-weight:550;color:var(--muted);font-size:12px;padding:9px 16px;border-bottom:1px solid var(--line);background:#fafafa;white-space:nowrap}
td{padding:11px 16px;border-bottom:1px solid var(--line2);vertical-align:top}
tr:last-child td{border-bottom:0}tbody tr:hover td{background:#fcfcfd}
.r{text-align:right;font-variant-numeric:tabular-nums}
.strong{font-weight:600}.sub{color:var(--muted);font-size:12px;margin-top:1px}
.badge{display:inline-block;padding:1px 8px;border-radius:4px;font-size:12px;font-weight:550;white-space:nowrap;background:#f4f4f5;color:var(--ink2);border:1px solid #e4e4e7}
.badge.green{background:var(--green-bg);color:var(--green);border-color:#bbf7d0}.badge.amber{background:var(--amber-bg);color:var(--amber);border-color:#fde68a}
.badge.red{background:var(--red-bg);color:var(--red);border-color:#fecaca}.badge.blue{background:var(--blue-bg);color:var(--blue);border-color:#bfdbfe}
.score{display:flex;align-items:center;gap:8px}.track{width:64px;height:4px;border-radius:2px;background:#ececee;overflow:hidden}.fill{display:block;height:100%}
.fill.ok{background:var(--green)}.fill.mid{background:#d97706}.fill.low{background:var(--red)}.score .num{font-variant-numeric:tabular-nums;color:var(--ink2)}
.docs{display:flex;flex-wrap:wrap;gap:4px;margin-top:6px}
.doc{font-size:11px;padding:0 6px;border-radius:3px;border:1px solid var(--line);color:var(--ink2);cursor:help}
.doc.ok{border-color:#bbf7d0;color:var(--green)}.doc.warning{border-color:#fde68a;color:var(--amber)}.doc.missing{color:var(--faint);text-decoration:line-through}
.tag{font-size:11px;font-weight:600;color:var(--amber);border:1px solid #fde68a;background:var(--amber-bg);border-radius:3px;padding:0 5px;margin-left:6px;vertical-align:1px}
.note{font-size:12.5px;color:var(--ink2);margin-top:6px;max-width:320px}.note.bad{color:var(--red)}
.actions{display:flex;flex-direction:column;align-items:flex-start;gap:6px}
.actions form{margin:0}.link{color:var(--ink2);text-decoration:none;font-size:12.5px;font-weight:550}.link:hover{text-decoration:underline}
.filters{display:flex;flex-wrap:wrap;align-items:center;gap:6px;padding:12px 16px;border-bottom:1px solid var(--line)}
.seg{display:inline-flex;flex-wrap:wrap;border:1px solid var(--line);border-radius:6px;overflow:hidden}
.seg a{padding:5px 10px;text-decoration:none;color:var(--ink2);border-right:1px solid var(--line);font-size:12.5px;white-space:nowrap}
.seg a:last-child{border-right:0}.seg a.on{background:var(--ink);color:#fff}.seg a span{color:var(--faint);margin-left:4px}.seg a.on span{color:#a1a1aa}
.filters .label{color:var(--muted);font-size:12px;margin:0 2px 0 8px}
.funnel td{padding:9px 16px}.bar{height:6px;border-radius:3px;background:#ececee;overflow:hidden;min-width:100px}.bar span{display:block;height:100%;background:var(--ink2)}
dl{margin:0;display:grid;grid-template-columns:auto 1fr;gap:9px 16px}dt{color:var(--muted)}dd{margin:0;display:flex;align-items:center;gap:7px}
.thumb{width:40px;height:40px;border-radius:6px;object-fit:cover;background:#f4f4f5;flex:none;display:inline-block}
.who{display:flex;align-items:center;gap:10px}.avatar{width:28px;height:28px;border-radius:50%;display:grid;place-items:center;font-size:11.5px;font-weight:650;flex:none}
.empty{padding:40px 16px;text-align:center;color:var(--muted)}
.wa{color:var(--ink);text-decoration:none;font-variant-numeric:tabular-nums}.wa:hover{text-decoration:underline}
.transcript{padding:6px 16px 16px}.turn{display:grid;grid-template-columns:84px 1fr;gap:12px;padding:9px 0;border-bottom:1px solid var(--line2)}
.turn:last-child{border-bottom:0}.turn .speaker{font-size:12px;color:var(--muted);font-weight:600}.turn .speaker small{display:block;font-weight:400;color:var(--faint)}
.turn.user .speaker{color:var(--blue)}.turn .text{white-space:pre-wrap}
.live{display:inline-flex;align-items:center;gap:6px;color:var(--red);font-weight:600}.live:before{content:"";width:7px;height:7px;border-radius:50%;background:var(--red);animation:blink 1.2s infinite}
@keyframes blink{50%{opacity:.3}}
.docgrid{display:grid;grid-template-columns:repeat(auto-fill,minmax(240px,1fr));gap:16px}
.docgrid img{display:block;width:100%;aspect-ratio:4/3;object-fit:cover;border-bottom:1px solid var(--line);background:#f4f4f5}
.placeholder{aspect-ratio:4/3;display:grid;place-items:center;border-bottom:1px solid var(--line);color:var(--muted);background:#fafafa}
audio{width:100%}
@media(max-width:1100px){.kpis{grid-template-columns:repeat(3,minmax(0,1fr))}.grid2{grid-template-columns:1fr}}
@media(max-width:800px){.layout{grid-template-columns:1fr}.side{display:none}.head,.content{padding-left:16px;padding-right:16px}.kpis{grid-template-columns:repeat(2,minmax(0,1fr))}.card{overflow-x:auto}}
`;

function page({ title, k, active, counts, voice, head, body, refresh }) {
  const nav = (v, label) =>
    `<a class="${active === v ? 'on' : ''}" href="/dashboard?key=${k}${v === 'overview' ? '' : `&view=${v}`}">${icon(v)}${label}${counts?.[v] != null ? `<span class="count">${num(counts[v])}</span>` : ''}</a>`;
  return `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>${esc(title)} · Travelgram Admin</title>${refresh ? `<meta http-equiv="refresh" content="${refresh}">` : ''}<style>${CSS}</style></head><body>
<div class="layout">
<aside class="side">
  <div class="brand"><i></i><div>Travelgram<small>Admin</small></div></div>
  <nav class="nav">${nav('overview', 'Overview')}${nav('crm', 'Leads')}${nav('creators', 'Users')}${nav('journeys', 'Journeys')}${nav('bookings', 'Bookings')}</nav>
  <div class="foot">
    <div class="status"><span class="dot ${voice?.configured ? 'on' : 'warn'}"></span>AI calling ${voice?.configured ? 'live' : 'in demo mode'}</div>
    <div class="status"><span class="dot on"></span>Documents stored privately</div>
  </div>
</aside>
<main>${head}<div class="content">${body}</div></main>
</div></body></html>`;
}

const header = (title, sub, actions = '') => `<div class="head"><div><h1>${title}</h1>${sub ? `<p>${sub}</p>` : ''}</div><div>${actions}</div></div>`;

export function dashboardRouter(store, key, voice, docsDir) {
  const r = Router();
  // Seeded demo creators vs people who actually signed up (older sign-ups have no joinedAt).
  let seedIds = new Set();
  try {
    seedIds = new Set(JSON.parse(fs.readFileSync(store.seedFile, 'utf8')).creators.map((c) => c.id));
  } catch {
    // No seed file: treat everyone as a sign-up.
  }
  const isSignup = (u) => Boolean(u.joinedAt) || !seedIds.has(u.id);
  r.use(express.urlencoded({ extended: false }));

  r.use((req, res, next) => {
    const given = String(req.query.key ?? '');
    const ok = given.length === key.length && crypto.timingSafeEqual(Buffer.from(given), Buffer.from(key));
    if (!ok) return res.status(401).type('text').send('Add ?key=… (printed in the server log when it starts).');
    next();
  });

  r.get('/leads.csv', (_req, res) => {
    const cols = ['createdAt', 'stage', 'score', 'docScore', 'name', 'handle', 'phone', 'title', 'destination', 'travelDate', 'month', 'travelers', 'budgetAed', 'source', 'probability', 'summary'];
    const val = (l, c) => (c === 'stage' ? stageOf(l) : c === 'probability' ? l.outcome?.probability : c === 'summary' ? l.outcome?.summary : l[c]) ?? '';
    const rows = store.leads().map((l) => cols.map((c) => `"${String(val(l, c)).replace(/"/g, '""')}"`).join(','));
    res.type('text/csv').attachment('travelgram-leads.csv').send([cols.join(','), ...rows].join('\n'));
  });

  // Document files: key-protected, never under /static.
  r.get('/docs/:leadId/:file', (req, res) => {
    const l = store.lead(req.params.leadId);
    const file = String(req.params.file);
    if (!l || !docsDir || !/^(passport|residence|bank|photo)\.(jpg|png|webp|pdf)$/.test(file)) return res.status(404).type('text').send('Not found');
    const full = path.join(docsDir, l.id, file);
    if (!fs.existsSync(full)) return res.status(404).type('text').send('Not found');
    res.set({ 'Cache-Control': 'no-store, private', 'X-Content-Type-Options': 'nosniff', 'Content-Disposition': 'inline' });
    res.sendFile(full);
  });

  const counts = () => ({ crm: store.leads().length, creators: store.creators().length, journeys: store.journeys().length, bookings: store.bookings().length });

  r.get('/docs/:leadId', (req, res) => {
    const l = store.lead(req.params.leadId);
    if (!l) return res.status(404).type('text').send('No such lead');
    const k = encodeURIComponent(key);
    const dir = docsDir ? path.join(docsDir, l.id) : null;
    const files = dir && fs.existsSync(dir) ? fs.readdirSync(dir).filter((f) => /^(passport|residence|bank|photo)\.(jpg|png|webp|pdf)$/.test(f)) : [];
    const tone = { ok: 'green', warning: 'amber', missing: 'gray' };
    const cards = DOCS.map((d) => {
      const file = files.find((f) => f.startsWith(`${d.id}.`));
      const check = l.docChecks?.find((c) => c.doc === d.id);
      const url = file ? `/dashboard/docs/${encodeURIComponent(l.id)}/${encodeURIComponent(file)}?key=${k}` : null;
      const preview = !url
        ? '<div class="placeholder">Not uploaded</div>'
        : file.endsWith('.pdf')
          ? `<div class="placeholder"><a class="btn" href="${url}" target="_blank" rel="noopener">Open PDF</a></div>`
          : `<a href="${url}" target="_blank" rel="noopener"><img src="${url}" alt="${esc(d.label)}" loading="lazy"></a>`;
      const status = check ? badge(check.status === 'ok' ? 'OK' : check.status === 'warning' ? 'Review' : 'Missing', tone[check.status] ?? 'gray') : '';
      return `<div class="card" style="margin:0">${preview}<div class="card-body"><div style="display:flex;justify-content:space-between;align-items:center;gap:8px"><span class="strong">${esc(d.label)}</span>${status}</div>${check?.note ? `<div class="sub" style="margin-top:6px">${esc(check.note)}</div>` : ''}</div></div>`;
    }).join('');
    const head = header(
      `Documents · ${esc(l.name || 'Anonymous')}`,
      `${l.handle ? '@' + esc(l.handle) + ' · ' : ''}Score ${Number(l.docScore) || 0}/100${l.destination ? ' · ' + esc(l.destination) : ''}${l.testDocs ? ' · Specimen documents' : ''}`,
      `<a class="btn" href="/dashboard?key=${k}&view=crm">${icon('back')}Back to leads</a>`,
    );
    res.type('html').send(page({ title: `Documents · ${l.name}`, k, active: 'crm', counts: counts(), voice, head, body: `<div class="docgrid">${cards}</div>` }));
  });

  r.post('/call/:id', async (req, res) => {
    const lead = store.lead(req.params.id);
    if (lead && voice) await voice.callLead(lead);
    res.redirect(303, lead ? `/dashboard/call/${encodeURIComponent(lead.id)}?key=${encodeURIComponent(key)}` : `/dashboard?key=${encodeURIComponent(key)}`);
  });

  r.get('/call/:id.json', (req, res) => {
    const l = store.lead(req.params.id);
    if (!l) return res.status(404).json({ error: 'not found' });
    res.json({ name: l.name, phone: l.phone, stage: stageOf(l), call: l.call ?? null, live: l.live ?? [], transcript: l.transcript ?? [], outcome: l.outcome ?? null, recording: l.recording ?? null });
  });

  r.get('/call/:id', (req, res) => {
    const l = store.lead(req.params.id);
    if (!l) return res.status(404).type('text').send('No such lead');
    const k = encodeURIComponent(key);
    const head = header(`Call · ${esc(l.name || 'Anonymous')}`, `${esc(l.phone ?? '')}<span id="state" style="margin-left:10px"></span>`, `<a class="btn" href="/dashboard?key=${k}&view=crm">${icon('back')}Back to leads</a>`);
    const body = `<div class="grid2">
  <div class="card"><div class="card-head"><h2>Conversation</h2><span class="sub" id="turns"></span></div><div class="transcript" id="msgs"><div class="empty">Waiting for the call to connect…</div></div></div>
  <div>
    <div class="card"><div class="card-head"><h2>Details</h2></div><div class="card-body"><dl id="details"></dl></div></div>
    <div class="card" id="outcome" hidden><div class="card-head"><h2>Outcome</h2></div><div class="card-body" id="outcomeBody"></div></div>
    <div class="card" id="rec" hidden><div class="card-head"><h2>Recording</h2></div><div class="card-body" id="recBody"></div></div>
  </div>
</div>
<script>
const url = location.pathname + '.json' + location.search;
const LABEL = ${JSON.stringify(CALL_LABEL)};
const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'})[c]);
let lastLen = -1, lastRec = '';
async function tick() {
  try {
    const d = await (await fetch(url)).json();
    const st = d.call?.status;
    document.getElementById('state').innerHTML = st === 'in_progress' ? '<span class="live">Live</span>' : esc(LABEL[st] ?? '');
    const a = d.call?.audio;
    const row = (k, v) => '<dt>' + k + '</dt><dd>' + v + '</dd>';
    document.getElementById('details').innerHTML =
      row('Stage', esc(d.stage)) +
      row('Status', esc(LABEL[st] ?? st ?? '—')) +
      (d.call?.duration ? row('Duration', esc(d.call.duration) + ' s') : '') +
      (a ? row('Agent spoke', esc(a.agentSeconds) + ' s') + row('Caller audio', esc(a.callerSeconds) + ' s') : '') +
      (a && a.noiseDropped != null ? row('Noise filtered', esc(a.noiseDropped) + ' fragments') : '') +
      (d.call?.note ? row('Note', '<span style="color:var(--red)">' + esc(d.call.note) + '</span>') : '');
    if (d.outcome) {
      document.getElementById('outcome').hidden = false;
      const o = d.outcome;
      document.getElementById('outcomeBody').innerHTML = '<dl>' +
        row('Probability', '<span class="badge ' + (o.probability === 'high' ? 'green' : o.probability === 'medium' ? 'amber' : 'gray') + '">' + esc(String(o.probability ?? '').replace(/^./, (c) => c.toUpperCase())) + '</span>') +
        (o.destination ? row('Destination', esc(o.destination)) : '') + (o.travelDate ? row('Dates', esc(o.travelDate)) : '') +
        (o.travelers ? row('Travellers', esc(o.travelers)) : '') + (o.interests ? row('Interests', esc(o.interests)) : '') +
        '</dl><p class="sub" style="margin:12px 0 0">' + esc(o.summary) + '</p>';
    }
    if (d.recording?.url && d.recording.url !== lastRec) {
      lastRec = d.recording.url;
      document.getElementById('rec').hidden = false;
      document.getElementById('recBody').innerHTML = '<audio controls preload="none" src="' + esc(d.recording.url) + '"></audio>';
    }
    const msgs = d.live.length ? d.live : d.transcript;
    if (msgs.length !== lastLen) {
      lastLen = msgs.length;
      document.getElementById('turns').textContent = msgs.length ? msgs.length + (msgs.length === 1 ? ' turn' : ' turns') : '';
      document.getElementById('msgs').innerHTML = msgs.length
        ? msgs.map((m) => '<div class="turn ' + (m.role === 'user' ? 'user' : '') + '"><span class="speaker">' + (m.role === 'user' ? 'Customer' : 'Agent') + (m.at ? '<small>' + new Date(m.at).toLocaleTimeString() + '</small>' : '') + '</span><div class="text">' + esc(m.text) + '</div></div>').join('')
        : '<div class="empty">' + (st === 'failed' ? 'The call did not connect.' : 'Waiting for the call to connect…') + '</div>';
    }
  } catch {}
  setTimeout(tick, 1500);
}
tick();
</script>`;
    res.type('html').send(page({ title: `Call · ${l.name}`, k, active: 'crm', counts: counts(), voice, head, body }));
  });

  r.get('/', (req, res) => {
    const k = encodeURIComponent(key);
    let view = req.query.view === 'users' ? 'creators' : req.query.view;
    if (!view && (req.query.stage || req.query.src)) view = 'crm';
    if (!['overview', 'crm', 'creators', 'journeys', 'bookings'].includes(view)) view = 'overview';

    const leads = store.leads();
    const users = store.creators();
    const realUsers = users.filter(isSignup);
    const journeys = store.journeys();
    const bookings = store.bookings();
    const revenue = bookings.reduce((s, b) => s + b.commissionAed, 0);
    const gmv = bookings.reduce((s, b) => s + b.amountAed, 0);
    const count = (s) => leads.filter((l) => stageOf(l) === s).length;
    const qualified = leads.filter((l) => l.qualified).length;
    const csv = `<a class="btn" href="/dashboard/leads.csv?key=${k}">${icon('download')}Export CSV</a>`;

    const leadRow = (l, full) => {
      const call = l.call?.status ? `<div class="sub">${esc(CALL_LABEL[l.call.status] ?? l.call.status)}</div>` : '';
      const name = `<div class="strong">${esc(l.name || 'Anonymous')}${l.testDocs ? '<span class="tag">Test docs</span>' : ''}</div><div class="sub">${l.handle ? '@' + esc(l.handle) + ' · ' : ''}${date(l.updatedAt)}</div>`;
      if (!full) return `<tr><td>${name}</td><td>${esc(SOURCE_LABEL[l.source] ?? l.source)}</td><td>${scoreCell(l.score)}</td><td>${stageBadge(l)}${call}</td></tr>`;
      const docs = l.docChecks ? `<div class="docs">${l.docChecks.map((c) => `<span class="doc ${esc(c.status)}" title="${esc(c.note)}">${esc(DOC_LABEL[c.doc] ?? c.doc)}</span>`).join('')}</div>` : '';
      const note = l.outcome
        ? `<div class="note"><span class="strong">${esc(String(l.outcome.probability ?? '').replace(/^./, (c) => c.toUpperCase()))} probability.</span> ${esc(l.outcome.summary)}</div>`
        : l.call?.note
          ? `<div class="note bad">${esc(l.call.note)}</div>`
          : '';
      const canCall = l.phone && !['ringing', 'in_progress'].includes(l.call?.status);
      const actions = [
        canCall ? `<form method="post" action="/dashboard/call/${esc(l.id)}?key=${k}"><button class="btn sm primary">AI call</button></form>` : '',
        l.call && l.call.status !== 'simulated' ? `<a class="link" href="/dashboard/call/${esc(l.id)}?key=${k}">${l.call.status === 'in_progress' ? '<span class="live">Live call</span>' : 'View call'}</a>` : '',
        l.hasDocs ? `<a class="link" href="/dashboard/docs/${esc(l.id)}?key=${k}">Documents</a>` : '',
      ].join('');
      return `<tr>
        <td>${name}</td>
        <td><div>${esc(l.title || '—')}</div><div class="sub">${esc(SOURCE_LABEL[l.source] ?? l.source)}${l.destination ? ' · ' + esc(l.destination) : ''}</div></td>
        <td>${l.travelers ? esc(l.travelers) + (Number(l.travelers) === 1 ? ' traveller' : ' travellers') : '—'}<div class="sub">${l.travelDate ? esc(l.travelDate) : l.month ? MONTHS[l.month] : ''}${l.budgetAed ? (l.travelDate || l.month ? ' · ' : '') + aed(l.budgetAed) : ''}</div></td>
        <td>${scoreCell(l.score)}${docs}</td>
        <td>${stageBadge(l)}${call}${note}</td>
        <td>${l.phone ? `<a class="wa" href="https://wa.me/${esc(l.phone.replace(/^\+/, ''))}" target="_blank" rel="noopener">${esc(l.phone)}</a>` : '<span class="sub">No consent</span>'}</td>
        <td><div class="actions">${actions}</div></td>
      </tr>`;
    };

    let head = '';
    let body = '';
    if (view === 'overview') {
      const docLeads = leads.filter((l) => l.source === 'documents');
      const avg = docLeads.length ? Math.round(docLeads.reduce((s, l) => s + (l.docScore ?? 0), 0) / docLeads.length) : 0;
      head = header('Overview', `${num(realUsers.length)} sign-ups · ${num(leads.length)} leads · ${num(bookings.length)} bookings`, csv);
      const funnel = STAGES.map((s) => {
        const n = count(s);
        const pct = leads.length ? Math.round((n / leads.length) * 100) : 0;
        return `<tr><td>${badge(s, STAGE_TONE[s])}</td><td class="r">${num(n)}</td><td style="width:45%"><div class="bar"><span style="width:${pct}%"></span></div></td><td class="r sub">${pct}%</td></tr>`;
      }).join('');
      body = `
<section class="kpis">
  <div class="kpi"><div class="label">Sign-ups</div><div class="value">${num(realUsers.length)}</div><div class="sub">${num(users.length - realUsers.length)} seeded creators</div></div>
  <div class="kpi"><div class="label">Leads</div><div class="value">${num(leads.length)}</div><div class="sub">${num(qualified)} qualified (score ≥ 70)</div></div>
  <div class="kpi"><div class="label">High probability</div><div class="value">${num(count('High probability'))}</div><div class="sub">${num(count('Called'))} called</div></div>
  <div class="kpi"><div class="label">Document checks</div><div class="value">${num(docLeads.length)}</div><div class="sub">Average score ${avg}/100</div></div>
  <div class="kpi"><div class="label">Revenue</div><div class="value">${aed(revenue)}</div><div class="sub">10% of ${aed(gmv)} booked</div></div>
</section>
<div class="grid2">
  <div class="card"><div class="card-head"><h2>Recent leads</h2><a class="link" href="/dashboard?key=${k}&view=crm">View all</a></div>
    ${leads.length ? `<table><thead><tr><th>Lead</th><th>Source</th><th>Score</th><th>Stage</th></tr></thead><tbody>${leads.slice(0, 8).map((l) => leadRow(l, false)).join('')}</tbody></table>` : '<div class="empty">No leads yet.</div>'}
  </div>
  <div>
    <div class="card"><div class="card-head"><h2>Pipeline</h2></div><table class="funnel"><tbody>${funnel}</tbody></table></div>
    <div class="card"><div class="card-head"><h2>System</h2></div><div class="card-body"><dl>
      <dt>Assistant</dt><dd><span class="dot on"></span>Gemini</dd>
      <dt>AI calling</dt><dd><span class="dot ${voice?.configured ? 'on' : 'warn'}"></span>${voice?.configured ? 'Plivo + Pipecat' : 'Demo mode (simulated)'}</dd>
      <dt>Documents</dt><dd><span class="dot on"></span>Private storage</dd>
      <dt>Journeys</dt><dd>${num(journeys.length)} published</dd>
    </dl></div></div>
  </div>
</div>`;
    } else if (view === 'crm') {
      const stage = STAGES.includes(req.query.stage) ? req.query.stage : null;
      const src = SOURCES.includes(req.query.src) ? req.query.src : null;
      let list = stage ? leads.filter((l) => stageOf(l) === stage) : leads;
      if (src) list = list.filter((l) => l.source === src);
      const q = (s, o) => `/dashboard?key=${k}&view=crm${s ? `&stage=${encodeURIComponent(s)}` : ''}${o ? `&src=${o}` : ''}`;
      head = header('Leads', `${num(leads.length)} total · ${num(qualified)} qualified`, csv);
      body = `<div class="card">
  <div class="filters">
    <div class="seg"><a class="${!stage ? 'on' : ''}" href="${q(null, src)}">All<span>${num(leads.length)}</span></a>${STAGES.map((s) => `<a class="${stage === s ? 'on' : ''}" href="${q(s, src)}">${esc(s)}<span>${count(s)}</span></a>`).join('')}</div>
    <span class="label">Source</span>
    <div class="seg"><a class="${!src ? 'on' : ''}" href="${q(stage, null)}">Any</a>${SOURCES.map((s) => `<a class="${src === s ? 'on' : ''}" href="${q(stage, s)}">${esc(SOURCE_LABEL[s])}</a>`).join('')}</div>
  </div>
  ${list.length ? `<table><thead><tr><th>Lead</th><th>Source</th><th>Group</th><th>Score</th><th>Stage</th><th>Phone</th><th></th></tr></thead><tbody>${list.map((l) => leadRow(l, true)).join('')}</tbody></table>` : '<div class="empty">No leads match these filters.</div>'}
</div>`;
    } else if (view === 'creators') {
      head = header('Users', `${num(realUsers.length)} sign-ups · ${num(users.length - realUsers.length)} seeded creators`);
      const rows = [...users]
        .sort((a, b) => (isSignup(a) && !isSignup(b) ? -1 : !isSignup(a) && isSignup(b) ? 1 : (b.joinedAt ?? '').localeCompare(a.joinedAt ?? '') || store.followerCount(b.id) - store.followerCount(a.id)))
        .map((u) => {
          const mine = leads.filter((l) => l.userId === u.id);
          const best = [...mine].sort((a, b) => (b.score ?? 0) - (a.score ?? 0))[0];
          const doc = mine.find((l) => l.docScore != null);
          const ub = bookings.filter((b) => b.userId === u.id);
          const hue = u.hue ?? 200;
          const initials = (u.name || '?').split(/[^\p{L}\p{N}]+/u).filter(Boolean).map((w) => w[0]).join('').slice(0, 2).toUpperCase();
          return `<tr>
            <td><div class="who"><span class="avatar" style="background:hsl(${hue},40%,92%);color:hsl(${hue},45%,30%)">${esc(initials)}</span><div><div class="strong">${esc(u.name)}</div><div class="sub">@${esc(u.handle)}${u.home ? ' · ' + esc(u.home) : ''}</div></div></div></td>
            <td>${isSignup(u) ? badge('Sign-up', 'blue') : badge('Seeded')}</td>
            <td>${u.phone ? `<a class="wa" href="https://wa.me/${esc(u.phone.replace(/^\+/, ''))}" target="_blank" rel="noopener">${esc(u.phone)}</a><div class="sub">${u.consent ? 'Agreed to calls' : 'No call consent'}</div>` : '<span class="sub">—</span>'}</td>
            <td class="r">${num(store.followerCount(u.id))}</td>
            <td class="r">${num(journeys.filter((j) => j.creatorId === u.id).length)}</td>
            <td class="r">${num(store.goingIds(u.id).length)}</td>
            <td>${doc ? scoreCell(doc.docScore) : '<span class="sub">—</span>'}</td>
            <td class="r">${ub.length ? `${ub.length}<div class="sub">${aed(ub.reduce((s, b) => s + b.amountAed, 0))}</div>` : '<span class="sub">—</span>'}</td>
            <td>${u.joinedAt ? dateShort(u.joinedAt) : '<span class="sub">—</span>'}</td>
            <td>${best ? stageBadge(best) : '<span class="sub">—</span>'}</td>
          </tr>`;
        })
        .join('');
      body = `<div class="card"><table><thead><tr><th>User</th><th>Type</th><th>Phone</th><th class="r">Followers</th><th class="r">Trips</th><th class="r">Going</th><th>Doc score</th><th class="r">Bookings</th><th>Joined</th><th>Lead stage</th></tr></thead><tbody>${rows || '<tr><td colspan="10" class="empty">No users yet.</td></tr>'}</tbody></table></div>`;
    } else if (view === 'journeys') {
      head = header('Journeys', `${num(journeys.length)} published`);
      const rows = [...journeys]
        .sort((a, b) => (b.likes ?? 0) - (a.likes ?? 0))
        .map((j) => {
          const c = users.find((u) => u.id === j.creatorId);
          const budget = (j.budget ?? []).reduce((s, b) => s + b.amount, 0);
          const cover = j.coverPhoto?.url ?? j.stops?.find((s) => s.photos?.length)?.photos[0]?.url;
          return `<tr>
            <td><div class="who">${cover ? `<img class="thumb" src="${esc(cover)}" alt="" loading="lazy">` : '<span class="thumb"></span>'}<div><div class="strong">${esc(j.title)}</div><div class="sub">${esc(j.region)}${j.country ? ', ' + esc(j.country) : ''}</div></div></div></td>
            <td>${c ? `${esc(c.name)}<div class="sub">@${esc(c.handle)}</div>` : '—'}</td>
            <td>${(j.tags ?? []).slice(0, 3).map((t) => badge(t)).join(' ')}</td>
            <td class="r">${num(j.durationDays)} d<div class="sub">${num(j.travelers)} ppl</div></td>
            <td class="r">${num(j.likes)}<div class="sub">${num(store.goingCount(j.id))} going</div></td>
            <td class="r">${budget ? esc(formatMoney(budget, j.currency ?? 'AED')) : '—'}<div class="sub">${num(j.stops?.length ?? 0)} places</div></td>
            <td>${dateShort(j.createdAt)}</td>
          </tr>`;
        })
        .join('');
      body = `<div class="card"><table><thead><tr><th>Journey</th><th>Creator</th><th>Tags</th><th class="r">Length</th><th class="r">Likes</th><th class="r">Budget</th><th>Posted</th></tr></thead><tbody>${rows || '<tr><td colspan="7" class="empty">No journeys yet.</td></tr>'}</tbody></table></div>`;
    } else {
      head = header('Bookings', `${num(bookings.length)} bookings · ${aed(gmv)} booked · ${aed(revenue)} revenue`);
      const rows = bookings
        .map(
          (b) => `<tr>
            <td><span class="strong" style="font-variant-numeric:tabular-nums">${esc(b.ref)}</span><div class="sub">${date(b.createdAt)}</div></td>
            <td>${esc(b.name)}<div class="sub">@${esc(b.handle)}</div></td>
            <td>${esc(b.item)}<div class="sub">${esc(b.journeyTitle)}</div></td>
            <td>${esc(b.date || '—')}<div class="sub">${num(b.guests)} guests</div></td>
            <td class="r">${esc(formatMoney(b.total, b.currency))}<div class="sub">≈ ${aed(b.amountAed)}</div></td>
            <td class="r strong">${aed(b.commissionAed)}</td>
            <td>${badge('Paid · demo', 'green')}</td>
          </tr>`,
        )
        .join('');
      body = bookings.length
        ? `<div class="card"><table><thead><tr><th>Reference</th><th>Customer</th><th>Item</th><th>Date</th><th class="r">Total</th><th class="r">Commission</th><th>Status</th></tr></thead><tbody>${rows}</tbody></table></div>`
        : '<div class="card"><div class="empty">No bookings yet. Travellers can book stays and activities from any trip in the app.</div></div>';
    }

    const titles = { overview: 'Overview', crm: 'Leads', creators: 'Users', journeys: 'Journeys', bookings: 'Bookings' };
    res.type('html').send(page({ title: titles[view], k, active: view, counts: counts(), voice, head, body, refresh: 30 }));
  });

  return r;
}
