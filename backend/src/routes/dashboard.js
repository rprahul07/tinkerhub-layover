// Partner dashboard: GET /dashboard?key=…&view=crm|users|bookings (HTML) and
// /dashboard/leads.csv. It shows phone numbers, so it needs a key: DASHBOARD_KEY
// from .env, or one generated once into data/dashboard-key.txt.
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { Router } from 'express';
import express from 'express';
import { formatMoney } from '../currency.js';
import { STAGES, stageOf } from '../leads.js';

const MONTHS = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const DOC_LABEL = { passport: 'Passport', residence: 'Residence visa', bank: 'Bank statement', photo: 'Photo' };

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
const slug = (s) => s.toLowerCase().replace(/\s+/g, '-');
const SOURCE = { planner: 'Budget plan', going: '"I\'m going"', documents: 'Document check', ammachi: 'Ammachi chat' };
const CALL = { simulated: 'Call simulated', ringing: 'Ringing…', in_progress: 'On call now', completed: 'Call completed', failed: 'Call failed', no_phone: 'No phone' };

export function dashboardRouter(store, key, voice) {
  const r = Router();
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

  // "Call now" from the CRM: the AI agent phones the lead.
  r.post('/call/:id', async (req, res) => {
    const lead = store.lead(req.params.id);
    if (lead && voice) await voice.callLead(lead);
    res.redirect(303, lead ? `/dashboard/call/${encodeURIComponent(lead.id)}?key=${encodeURIComponent(key)}` : `/dashboard?key=${encodeURIComponent(key)}`);
  });

  // One call: recording, audio log and the conversation, refreshed live.
  r.get('/call/:id.json', (req, res) => {
    const l = store.lead(req.params.id);
    if (!l) return res.status(404).json({ error: 'not found' });
    res.json({ name: l.name, phone: l.phone, stage: stageOf(l), call: l.call ?? null, live: l.live ?? [], transcript: l.transcript ?? [], outcome: l.outcome ?? null, recording: l.recording ?? null });
  });

  r.get('/call/:id', (req, res) => {
    const l = store.lead(req.params.id);
    if (!l) return res.status(404).type('text').send('No such lead');
    const k = encodeURIComponent(key);
    res.type('html').send(`<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Call · ${esc(l.name)}</title>
<style>
body{margin:0;font:14px/1.5 system-ui,-apple-system,"Segoe UI",Roboto,sans-serif;background:#fafaf9;color:#1c1917}
header{display:flex;align-items:center;gap:14px;padding:14px 24px;background:#fff;border-bottom:1px solid #e7e5e4}
header a{color:#78716c;text-decoration:none;font-weight:600}h1{font-size:17px;margin:0}
main{max-width:860px;margin:0 auto;padding:20px 16px 60px}
.card{background:#fff;border:1px solid #e7e5e4;border-radius:12px;padding:14px 16px;margin-bottom:14px}
.row{display:flex;flex-wrap:wrap;gap:18px;align-items:center}.k{color:#78716c;font-size:11.5px;text-transform:uppercase;letter-spacing:.06em}.v{font-weight:650}
.live{display:inline-flex;align-items:center;gap:6px;color:#dc2626;font-weight:700}.live i{width:9px;height:9px;border-radius:50%;background:#dc2626;animation:p 1s infinite}@keyframes p{50%{opacity:.25}}
.msgs{display:flex;flex-direction:column;gap:8px}.m{max-width:78%;padding:9px 13px;border-radius:14px;white-space:pre-wrap}
.m.assistant{background:#f5f5f4;align-self:flex-start;border-top-left-radius:4px}.m.user{background:#0f766e;color:#fff;align-self:flex-end;border-top-right-radius:4px}
.m small{display:block;opacity:.6;font-size:11px;margin-top:3px}
.out{background:#dcfce7;border-color:#bbf7d0}.bad{background:#fef2f2;border-color:#fecaca;color:#991b1b}
audio{width:100%;margin-top:6px}.muted{color:#78716c}
</style></head><body>
<header><a href="/dashboard?key=${k}">← CRM</a><h1>${esc(l.name)} · ${esc(l.phone ?? '')}</h1><span id="state"></span></header>
<main>
<div class="card row" id="stats"></div>
<div class="card" id="rec" hidden></div>
<div class="card" id="outcome" hidden></div>
<div class="card"><div class="k" style="margin-bottom:10px">Conversation</div><div class="msgs" id="msgs"><span class="muted">Waiting for the call to connect…</span></div></div>
</main>
<script>
const url = location.pathname + '.json' + location.search;
const LABEL = { ringing: 'Ringing…', in_progress: 'On call', completed: 'Call ended', failed: 'Call failed', simulated: 'Simulated' };
const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);
let lastLen = -1, lastRec = '';
async function tick() {
  try {
    const d = await (await fetch(url)).json();
    const st = d.call?.status;
    document.getElementById('state').innerHTML = st === 'in_progress' ? '<span class="live"><i></i>LIVE</span>' : esc(LABEL[st] ?? st ?? '');
    const a = d.call?.audio;
    document.getElementById('stats').innerHTML =
      '<div><div class="k">Stage</div><div class="v">' + esc(d.stage) + '</div></div>' +
      '<div><div class="k">Call</div><div class="v">' + esc(LABEL[st] ?? st ?? '—') + (d.call?.duration ? ' · ' + d.call.duration + ' s' : '') + '</div></div>' +
      (a ? '<div><div class="k">Audio log</div><div class="v">Agent spoke ' + a.agentSeconds + ' s · heard caller ' + a.callerSeconds + ' s</div></div>' : '') +
      (d.call?.note ? '<div class="bad" style="padding:4px 10px;border-radius:8px">' + esc(d.call.note) + '</div>' : '');
    if (d.recording?.url && d.recording.url !== lastRec) {
      lastRec = d.recording.url;
      const rec = document.getElementById('rec');
      rec.hidden = false;
      rec.innerHTML = '<div class="k">Recording</div><audio controls preload="none" src="' + esc(d.recording.url) + '"></audio>';
    }
    if (d.outcome) {
      const o = document.getElementById('outcome');
      o.hidden = false;
      o.className = 'card out';
      o.innerHTML = '<b style="text-transform:capitalize">' + esc(d.outcome.probability) + ' probability</b> · ' + esc(d.outcome.summary) +
        (d.outcome.destination ? '<br>Destination: ' + esc(d.outcome.destination) : '') + (d.outcome.travelDate ? ' · Date: ' + esc(d.outcome.travelDate) : '') +
        (d.outcome.travelers ? ' · People: ' + esc(d.outcome.travelers) : '') + (d.outcome.interests ? '<br>Interests: ' + esc(d.outcome.interests) : '');
    }
    const msgs = d.live.length ? d.live : d.transcript;
    if (msgs.length !== lastLen) {
      lastLen = msgs.length;
      document.getElementById('msgs').innerHTML = msgs.length
        ? msgs.map((m) => '<div class="m ' + (m.role === 'user' ? 'user' : 'assistant') + '">' + esc(m.text) + '<small>' + (m.role === 'user' ? 'Customer' : 'Ammachi') + (m.at ? ' · ' + new Date(m.at).toLocaleTimeString() : '') + '</small></div>').join('')
        : '<span class="muted">' + (st === 'failed' ? 'The call did not connect.' : 'Waiting for the call to connect…') + '</span>';
      window.scrollTo(0, document.body.scrollHeight);
    }
  } catch {}
  setTimeout(tick, 1500);
}
tick();
</script></body></html>`);
  });

  r.get('/', (req, res) => {
    const k = encodeURIComponent(key);
    const view = ['users', 'bookings'].includes(req.query.view) ? req.query.view : 'crm';
    const leads = store.leads();
    const users = store.creators().filter((c) => c.joinedAt); // real sign-ups, not seeded creators
    const bookings = store.bookings();
    const revenue = bookings.reduce((s, b) => s + b.commissionAed, 0);
    const gmv = bookings.reduce((s, b) => s + b.amountAed, 0);
    const count = (s) => leads.filter((l) => stageOf(l) === s).length;
    const nav = (v, label, n) => `<a class="tab ${view === v ? 'on' : ''}" href="?key=${k}${v === 'crm' ? '' : `&view=${v}`}">${label} <b>${n}</b></a>`;

    let body = '';
    if (view === 'crm') {
      const stage = STAGES.includes(req.query.stage) ? req.query.stage : null;
      const list = stage ? leads.filter((l) => stageOf(l) === stage) : leads;
      const chip = (s) => `<a class="chip ${stage === s ? 'on' : ''}" href="?key=${k}${s ? `&stage=${encodeURIComponent(s)}` : ''}">${s ?? 'All'} <b>${s ? count(s) : leads.length}</b></a>`;
      const rows = list
        .map((l) => {
          const st = stageOf(l);
          const docs = l.docChecks
            ? `<div class="docs">${l.docChecks.map((c) => `<span class="d ${c.status}" title="${esc(c.note)}">${esc(DOC_LABEL[c.doc] ?? c.doc)}</span>`).join('')}</div>`
            : '';
          const out = l.outcome
            ? `<div class="out"><b>${esc(l.outcome.probability)} probability</b> · ${esc(l.outcome.summary)}${l.outcome.travelDate ? `<br><span class="muted">Date: ${esc(l.outcome.travelDate)}</span>` : ''}${l.outcome.interests ? `<br><span class="muted">Interests: ${esc(l.outcome.interests)}</span>` : ''}</div>`
            : l.call?.note
              ? `<div class="muted">${esc(l.call.note)}</div>`
              : '';
          const wa = l.phone ? `<a class="wa" href="https://wa.me/${esc(l.phone.replace(/^\+/, ''))}" target="_blank" rel="noopener">${esc(l.phone)}</a>` : '<span class="muted">No consent</span>';
          const canCall = l.phone && !['ringing', 'in_progress'].includes(l.call?.status);
          return `<tr>
            <td><div class="name">${esc(l.name || 'Anonymous')}${l.testDocs ? ' <span class="test">TEST DOCS</span>' : ''}</div><div class="muted">${l.handle ? '@' + esc(l.handle) : ''} · ${date(l.updatedAt)}</div></td>
            <td><div>${esc(l.title || '—')}</div><div class="muted">${esc(SOURCE[l.source] ?? l.source)}${l.destination ? ' · ' + esc(l.destination) : ''}</div></td>
            <td>${l.travelers ? esc(l.travelers) + ' ppl' : '—'}<div class="muted">${l.travelDate ? esc(l.travelDate) : l.month ? MONTHS[l.month] : ''}</div>${l.budgetAed ? `<div class="muted">${esc(formatMoney(l.budgetAed, 'AED'))}</div>` : ''}</td>
            <td><div class="score"><i style="width:${Number(l.score) || 0}%"></i></div><div class="muted">${esc(l.score)} / 100</div>${docs}</td>
            <td><span class="badge ${slug(st)}">${st}</span><div class="muted src">${esc(CALL[l.call?.status] ?? '')}</div>${out}</td>
            <td>${wa}</td>
            <td>${canCall ? `<form method="post" action="/dashboard/call/${esc(l.id)}?key=${k}"><button class="call">📞 AI call</button></form>` : ''}${l.call && l.call.status !== 'simulated' ? `<a class="conv" href="/dashboard/call/${esc(l.id)}?key=${k}">${l.call.status === 'in_progress' ? '🔴 Live' : 'Conversation'} →</a>` : ''}</td>
          </tr>`;
        })
        .join('');
      body = `<nav class="chips">${[null, ...STAGES].map(chip).join('')}</nav>
${list.length ? `<table><thead><tr><th>Traveller</th><th>Source</th><th>Group / date</th><th>Score</th><th>Stage</th><th>Phone</th><th></th></tr></thead><tbody>${rows}</tbody></table>` : '<div class="empty">No leads here yet. They arrive from document checks, budget plans and "I\'m going".</div>'}`;
    } else if (view === 'users') {
      const rows = users
        .slice()
        .reverse()
        .map((u) => {
          const mine = leads.filter((l) => l.userId === u.id);
          const best = mine.sort((a, b) => (b.score ?? 0) - (a.score ?? 0))[0];
          const docs = mine.find((l) => l.docScore != null);
          const ub = bookings.filter((b) => b.userId === u.id);
          return `<tr>
            <td><div class="name">${esc(u.name)}</div><div class="muted">@${esc(u.handle)}</div></td>
            <td>${u.phone ? `<a class="wa" href="https://wa.me/${esc(u.phone.replace(/^\+/, ''))}" target="_blank" rel="noopener">${esc(u.phone)}</a>` : '—'}<div class="muted">${u.consent ? 'Agreed to calls' : 'No call consent'}</div></td>
            <td>${esc(u.home || '—')}</td>
            <td>${date(u.joinedAt)}</td>
            <td>${store.journeys().filter((j) => j.creatorId === u.id).length}</td>
            <td>${store.goingIds(u.id).length}</td>
            <td>${store.plansOf(u.id).length}</td>
            <td>${docs ? `${esc(docs.docScore)} / 100` : '—'}</td>
            <td>${ub.length}${ub.length ? `<div class="muted">${esc(formatMoney(ub.reduce((s, b) => s + b.amountAed, 0), 'AED'))}</div>` : ''}</td>
            <td>${best ? `<span class="badge ${slug(stageOf(best))}">${stageOf(best)}</span>` : '<span class="muted">—</span>'}</td>
          </tr>`;
        })
        .join('');
      body = users.length
        ? `<table><thead><tr><th>User</th><th>Phone</th><th>Home</th><th>Joined</th><th>Trips</th><th>Going</th><th>Plans</th><th>Docs</th><th>Bookings</th><th>CRM stage</th></tr></thead><tbody>${rows}</tbody></table>`
        : '<div class="empty">No sign-ups yet.</div>';
    } else {
      const rows = bookings
        .map(
          (b) => `<tr><td><b>${esc(b.ref)}</b><div class="muted">${date(b.createdAt)}</div></td><td>${esc(b.name)}<div class="muted">@${esc(b.handle)}</div></td>
          <td>${esc(b.item)}<div class="muted">${esc(b.journeyTitle)}</div></td><td>${esc(b.date || '—')}<div class="muted">${esc(b.guests)} guests</div></td>
          <td>${esc(formatMoney(b.total, b.currency))}<div class="muted">≈ ${esc(formatMoney(b.amountAed, 'AED'))}</div></td><td class="rev">${esc(formatMoney(b.commissionAed, 'AED'))}</td><td><span class="badge called">Paid (demo)</span></td></tr>`,
        )
        .join('');
      body = bookings.length
        ? `<table><thead><tr><th>Ref</th><th>Customer</th><th>Item</th><th>Date</th><th>Total</th><th>Our 10%</th><th>Status</th></tr></thead><tbody>${rows}</tbody></table>`
        : '<div class="empty">No bookings yet. Travellers can book stays and activities from any trip in the app.</div>';
    }

    res.type('html').send(`<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Travelgram · CRM</title><meta http-equiv="refresh" content="15">
<style>
:root{--bg:#fafaf9;--card:#fff;--line:#e7e5e4;--ink:#1c1917;--muted:#78716c;--accent:#d9481f;--teal:#0f766e;--green:#15803d}
*{box-sizing:border-box}body{margin:0;font:14px/1.45 system-ui,-apple-system,"Segoe UI",Roboto,sans-serif;background:var(--bg);color:var(--ink)}
header{display:flex;align-items:center;gap:24px;padding:16px 32px;border-bottom:1px solid var(--line);background:var(--card)}
h1{font-size:18px;margin:0;letter-spacing:-.01em}.sp{flex:1}
.tab{padding:8px 14px;border-radius:8px;color:var(--muted);text-decoration:none;font-weight:600}.tab.on{background:var(--ink);color:#fff}.tab b{opacity:.7;margin-left:4px;font-weight:600}
main{padding:24px 32px;max-width:1500px;margin:0 auto}
.kpis{display:grid;grid-template-columns:repeat(5,1fr);gap:14px;margin-bottom:20px}
.kpi{background:var(--card);border:1px solid var(--line);border-radius:12px;padding:14px 16px}.kpi b{display:block;font-size:24px;letter-spacing:-.02em}.kpi span{color:var(--muted);font-size:11.5px;text-transform:uppercase;letter-spacing:.06em}
.kpi.hot b{color:var(--green)}
.panel{background:var(--card);border:1px solid var(--line);border-radius:12px;overflow:auto}
.chips{display:flex;flex-wrap:wrap;gap:6px;padding:12px;border-bottom:1px solid var(--line)}.chip{padding:5px 11px;border-radius:999px;border:1px solid var(--line);color:var(--ink);text-decoration:none;font-size:13px}.chip.on{background:var(--ink);border-color:var(--ink);color:#fff}.chip b{opacity:.6;margin-left:3px}
table{width:100%;border-collapse:collapse}th{text-align:left;font-size:11px;text-transform:uppercase;letter-spacing:.06em;color:var(--muted);font-weight:600;padding:10px 14px;border-bottom:1px solid var(--line);white-space:nowrap}
td{padding:12px 14px;border-bottom:1px solid var(--line);vertical-align:top}tr:last-child td{border-bottom:0}
.name{font-weight:600}.muted{color:var(--muted);font-size:12px}.src{margin-top:4px}
.score{width:90px;height:6px;background:#f0efee;border-radius:3px;overflow:hidden;margin:6px 0 4px}.score i{display:block;height:100%;background:var(--teal)}
.docs{display:flex;flex-wrap:wrap;gap:3px;margin-top:6px;max-width:200px}.d{font-size:10.5px;padding:1px 6px;border-radius:4px;cursor:help}.d.ok{background:#dcfce7;color:#166534}.d.warning{background:#fef3c7;color:#92400e}.d.missing{background:#f0efee;color:#a8a29e;text-decoration:line-through}
.badge{display:inline-block;padding:2px 9px;border-radius:999px;font-size:12px;font-weight:600;white-space:nowrap;background:#f0efee;color:var(--muted)}
.badge.high-probability{background:#dcfce7;color:var(--green)}.badge.called{background:#e3f2f0;color:var(--teal)}.badge.calling{background:#dbeafe;color:#1d4ed8}.badge.qualified{background:#fcede7;color:var(--accent)}.badge.contactable{background:#fef3c7;color:#92400e}
.out{margin-top:6px;max-width:300px;font-size:12.5px}.out b{text-transform:capitalize;color:var(--green)}
.test{font-size:10px;font-weight:700;letter-spacing:.04em;color:#92400e;background:#fef3c7;border-radius:4px;padding:1px 5px;vertical-align:middle}
.conv{display:inline-block;margin-top:6px;font-weight:600;color:var(--ink);text-decoration:none;white-space:nowrap}
.wa{color:var(--teal);text-decoration:none;font-weight:600;white-space:nowrap}.rev{color:var(--green);font-weight:700}
.call{border:0;background:var(--green);color:#fff;border-radius:8px;padding:7px 11px;font:inherit;font-weight:600;cursor:pointer;white-space:nowrap}
.btn{border:1px solid var(--line);border-radius:8px;padding:7px 12px;color:var(--ink);text-decoration:none;font-weight:600;background:var(--card)}
.note{margin:0 0 16px;padding:10px 14px;border-radius:10px;background:${voice?.configured ? '#dcfce7' : '#fef3c7'};font-size:13px}
.empty{padding:48px;text-align:center;color:var(--muted)}
@media(max-width:1000px){.kpis{grid-template-columns:repeat(2,1fr)}main,header{padding-left:16px;padding-right:16px}header{flex-wrap:wrap;gap:8px}}
</style></head><body>
<header><h1>Travelgram</h1>${nav('crm', 'CRM', leads.length)}${nav('users', 'All users', users.length)}${nav('bookings', 'Bookings', bookings.length)}<span class="sp"></span><a class="btn" href="/dashboard/leads.csv?key=${k}">Export CSV</a></header>
<main>
<p class="note">${voice?.configured ? '📞 AI calling is live: leads scoring ≥ 70 on the document check are called automatically by the voice agent (Plivo + Pipecat).' : '📞 AI calling is in demo mode: qualified leads are marked "Call simulated". Add PLIVO_* to backend/.env and start voice-agent/ to place real calls.'}</p>
<section class="kpis">
<div class="kpi"><b>${users.length}</b><span>Users</span></div>
<div class="kpi"><b>${leads.length}</b><span>Leads</span></div>
<div class="kpi"><b>${leads.filter((l) => l.qualified).length}</b><span>Qualified (≥ 70)</span></div>
<div class="kpi hot"><b>${count('High probability')}</b><span>High conversion probability</span></div>
<div class="kpi hot"><b>${esc(formatMoney(revenue, 'AED'))}</b><span>Revenue · GMV ${esc(formatMoney(gmv, 'AED'))}</span></div>
</section>
<section class="panel">${body}</section>
</main></body></html>`);
  });

  return r;
}
