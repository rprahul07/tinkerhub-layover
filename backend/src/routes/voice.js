// Plivo webhooks + the Pipecat agent's private API.
import crypto from 'node:crypto';
import { Router } from 'express';
import express from 'express';

const OUTCOME = {
  type: 'object',
  properties: {
    interested: { type: 'boolean' },
    destination: { type: 'string' },
    travelDate: { type: 'string' },
    travelers: { type: 'integer' },
    interests: { type: 'string' },
    probability: { type: 'string', enum: ['high', 'medium', 'low'] },
    summary: { type: 'string' },
  },
  required: ['interested', 'probability', 'summary'],
};

export function voiceRouter(store, { llm, agentKey, publicUrl }) {
  const r = Router();
  r.use(express.urlencoded({ extended: false }));

  const agentOnly = (req, res, next) => {
    const given = String(req.get('x-agent-key') ?? '');
    const ok = given.length === agentKey.length && crypto.timingSafeEqual(Buffer.from(given), Buffer.from(agentKey));
    return ok ? next() : res.status(401).json({ error: 'agent key required' });
  };

  // Plivo asks what to do when the traveller answers: stream audio to the agent.
  r.all('/voice/answer/:leadId', (req, res) => {
    const lead = store.lead(req.params.leadId);
    if (lead) store.updateLead(lead.id, { call: { ...lead.call, status: 'in_progress', callUuid: req.body?.CallUUID } });
    const http = publicUrl || `https://${req.get('host')}`;
    const id = encodeURIComponent(req.params.leadId);
    // Record the whole call in the background (for the dashboard), then stream audio to the agent.
    res.type('application/xml').send(
      `<?xml version="1.0" encoding="UTF-8"?><Response>` +
        `<Record recordSession="true" redirect="false" maxLength="3600" fileFormat="mp3" callbackUrl="${http}/voice/recording/${id}" callbackMethod="POST"/>` +
        `<Stream bidirectional="true" keepCallAlive="true" contentType="audio/x-mulaw;rate=8000">${http.replace(/^http/, 'ws')}/voice/ws/${id}</Stream>` +
        `</Response>`,
    );
  });

  r.all('/voice/hangup/:leadId', (req, res) => {
    const lead = store.lead(req.params.leadId);
    const b = req.body ?? {};
    if (lead) {
      const answered = Boolean(b.AnswerTime) || Number(b.Duration) > 0 || lead.call?.status === 'in_progress' || lead.call?.status === 'completed';
      const cause = b.HangupCauseName || b.HangupCause || '';
      store.updateLead(lead.id, {
        call: answered
          ? { ...lead.call, status: lead.call?.status === 'completed' ? 'completed' : 'completed', duration: Number(b.Duration) || lead.call?.duration, hangupBy: b.HangupSource }
          : { ...lead.call, status: 'failed', note: `Didn't connect: ${cause || 'no answer'}${b.HangupSource ? ` (${b.HangupSource})` : ''}` },
      });
    }
    res.sendStatus(200);
  });

  // Plivo posts the call recording when it's ready.
  r.all('/voice/recording/:leadId', (req, res) => {
    const lead = store.lead(req.params.leadId);
    const url = req.body?.RecordUrl || req.body?.record_url;
    if (lead && url) store.updateLead(lead.id, { recording: { url, seconds: Number(req.body?.RecordingDuration) || undefined } });
    res.type('application/xml').send('<Response/>');
  });

  // The agent streams each turn as it happens, for the live call view.
  r.post('/api/voice/live/:id', agentOnly, (req, res) => {
    const l = store.lead(req.params.id);
    if (!l) return res.status(404).json({ error: 'no such lead' });
    const text = String(req.body?.text ?? '').slice(0, 1000);
    if (text) store.updateLead(l.id, { live: [...(l.live ?? []), { role: req.body?.role === 'user' ? 'user' : 'assistant', text, at: new Date().toISOString() }].slice(-200), call: l.call?.status === 'completed' ? l.call : { ...l.call, status: 'in_progress' } });
    res.json({ ok: true });
  });

  // The agent fetches who it's calling...
  r.get('/api/voice/lead/:id', agentOnly, (req, res) => {
    const l = store.lead(req.params.id);
    if (!l) return res.status(404).json({ error: 'no such lead' });
    res.json({ id: l.id, name: l.name, destination: l.destination, month: l.month, travelers: l.travelers, docScore: l.docScore, lang: l.lang === 'en' ? 'en' : 'ml' });
  });

  // ...and reports the conversation when the call ends.
  r.post('/api/voice/result/:id', agentOnly, async (req, res) => {
    const l = store.lead(req.params.id);
    if (!l) return res.status(404).json({ error: 'no such lead' });
    const transcript = (req.body?.transcript ?? []).filter((m) => m?.text).slice(-60);
    const text = transcript.map((m) => `${m.role === 'user' ? 'Traveller' : 'Agent'}: ${m.text}`).join('\n');
    const spoke = transcript.some((m) => m.role === 'user');
    let outcome = spoke
      ? { interested: true, probability: 'medium', summary: 'Call completed.' }
      : { interested: false, probability: 'low', summary: 'The customer hung up before saying anything — try again later or WhatsApp them.' };
    if (llm && spoke) {
      try {
        outcome = await llm.json({
          system: 'Extract the outcome of a sales call from a UAE visa & travel consultancy. probability = likelihood the traveller books with us: high if they gave a destination, dates and group size and sounded keen; low if not interested.',
          prompt: text,
          schema: OUTCOME,
        });
      } catch (err) {
        console.warn('Call outcome extraction failed:', err.message);
      }
    }
    store.updateLead(l.id, {
      call: { ...l.call, status: 'completed', endedAt: new Date().toISOString(), audio: req.body?.audio },
      outcome,
      transcript,
      destination: outcome.destination || l.destination,
      // Ignore implausible group sizes from a garbled transcript.
      travelers: outcome.travelers >= 1 && outcome.travelers <= 20 ? outcome.travelers : l.travelers,
      travelDate: outcome.travelDate || l.travelDate,
    });
    res.json({ ok: true, outcome });
  });

  return r;
}
