// Outbound AI calls. Plivo dials the traveller; when they answer, Plivo opens
// a bidirectional audio stream to /voice/ws/:leadId, which we proxy to the
// Pipecat agent (voice-agent/bot.py). Without Plivo credentials, calls are
// simulated so the flow can still be demoed end to end.

export function createVoice(cfg, store) {
  const configured = Boolean(cfg.plivoAuthId && cfg.plivoAuthToken && cfg.plivoFrom && cfg.publicUrl);

  async function callLead(lead) {
    if (!lead?.phone) return { status: 'no_phone' };
    const at = new Date().toISOString();
    if (!configured) {
      store.updateLead(lead.id, { call: { status: 'simulated', at, note: 'Plivo not configured — set PLIVO_* and PUBLIC_URL in backend/.env' } });
      return { status: 'simulated' };
    }
    // Let the agent render the greeting while the phone rings (no dead air on pickup).
    fetch(`${cfg.agentUrl}/prepare/${lead.id}`, { method: 'POST', headers: { 'x-agent-key': cfg.agentKey ?? '' }, signal: AbortSignal.timeout(15000) }).catch((err) =>
      console.warn('Voice agent not reachable to prepare the greeting:', err.message),
    );
    const auth = Buffer.from(`${cfg.plivoAuthId}:${cfg.plivoAuthToken}`).toString('base64');
    try {
      const res = await fetch(`https://api.plivo.com/v1/Account/${cfg.plivoAuthId}/Call/`, {
        method: 'POST',
        headers: { Authorization: `Basic ${auth}`, 'Content-Type': 'application/json' },
        body: JSON.stringify({
          from: cfg.plivoFrom.replace(/^\+/, ''),
          to: lead.phone.replace(/^\+/, ''),
          answer_url: `${cfg.publicUrl}/voice/answer/${lead.id}`,
          answer_method: 'POST',
          hangup_url: `${cfg.publicUrl}/voice/hangup/${lead.id}`,
          hangup_method: 'POST',
          time_limit: 600,
        }),
        signal: AbortSignal.timeout(15000),
      });
      const body = await res.json().catch(() => ({}));
      if (!res.ok) throw new Error(body.error || `Plivo ${res.status}`);
      store.updateLead(lead.id, { call: { status: 'ringing', at, requestUuid: body.request_uuid }, live: [], outcome: null, recording: null });
      return { status: 'ringing' };
    } catch (err) {
      store.updateLead(lead.id, { call: { status: 'failed', at, note: err.message } });
      return { status: 'failed', error: err.message };
    }
  }

  return { configured, callLead };
}
