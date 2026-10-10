// Smart document check: up to four travel documents, scored 0–100 for visa
// readiness. Gemini reads the images/PDFs; without it we fall back to a basic
// presence check. Files are only held in memory for the check, never stored.

export const DOCS = [
  { id: 'passport', label: 'Passport (photo page)', weight: 35 },
  { id: 'residence', label: 'UAE residence visa / Emirates ID', weight: 25 },
  { id: 'bank', label: 'Bank statement (last 3 months)', weight: 25 },
  { id: 'photo', label: 'Passport-size photo', weight: 15 },
];

const SCHEMA = {
  type: 'object',
  properties: {
    score: { type: 'integer', minimum: 0, maximum: 100 },
    specimen: { type: 'boolean' },
    summary: { type: 'string' },
    checks: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          doc: { type: 'string', enum: DOCS.map((d) => d.id) },
          status: { type: 'string', enum: ['ok', 'warning', 'missing'] },
          note: { type: 'string' },
        },
        required: ['doc', 'status', 'note'],
      },
    },
  },
  required: ['score', 'summary', 'checks'],
};

const system = `You are a careful visa-readiness checker for a UAE travel and visa consultancy.
You receive up to four documents from a UAE resident planning a trip. Score how ready they are to apply for a tourist visa (0–100).
Weights: passport ${DOCS[0].weight}, residence visa/Emirates ID ${DOCS[1].weight}, bank statement ${DOCS[2].weight}, photo ${DOCS[3].weight}.
Minimal conditions:
- Passport: readable photo page, valid at least 6 months after the travel month.
- Residence visa / Emirates ID: valid at least 3 months after the travel month.
- Bank statement: recent (last 3 months), roughly AED 5,000 or more available per traveller.
- Photo: clear face, plain light background.
Give full weight when a condition is clearly met, partial weight when unclear or borderline, zero when missing, unreadable or not the right document.
For each of the four documents return status ok / warning / missing with one short, friendly note (no personal numbers — never repeat passport or ID numbers).
summary: one or two sentences for the traveller. Never invent details you cannot see.`;

// Demo mode: documents openly marked SPECIMEN / TEST are scored on the details
// they show, and flagged so the CRM can tell test leads from real ones.
const SPECIMENS_ON = `
Demo mode: some documents may be openly marked SPECIMEN / TEST DATA (fictional person or bank). Treat them as test fixtures: score them on the details they show as if genuine, and set specimen=true. Set specimen=false only if no document is marked that way.`;
const SPECIMENS_OFF = `
Documents marked SPECIMEN, SAMPLE or TEST are not genuine: give them zero and say so. Set specimen=true if any document is marked that way.`;

/// files: { [docId]: { buffer, mimetype, size } }
export async function checkDocuments({ llm, files, destination, month, travelers, signal, allowSpecimens = false }) {
  const present = DOCS.filter((d) => files[d.id]);
  if (llm && present.length) {
    try {
      const parts = [
        { text: `Destination: ${destination || 'not given'}. Travel month: ${month || 'not given'}. Travellers: ${travelers || 1}. Today: ${new Date().toISOString().slice(0, 10)}.` },
      ];
      for (const d of present) {
        parts.push({ text: `Document "${d.id}" (${d.label}):` });
        parts.push({ inlineData: { mimeType: files[d.id].mimetype, data: files[d.id].buffer.toString('base64') } });
      }
      for (const d of DOCS.filter((x) => !files[x.id])) parts.push({ text: `Document "${d.id}" was not uploaded.` });
      const out = await llm.json({ system: system + (allowSpecimens ? SPECIMENS_ON : SPECIMENS_OFF), parts, schema: SCHEMA, signal });
      const checks = DOCS.map((d) => out.checks?.find((c) => c.doc === d.id) ?? { doc: d.id, status: files[d.id] ? 'warning' : 'missing', note: files[d.id] ? 'Could not read this clearly.' : 'Not uploaded.' });
      return { score: Math.max(0, Math.min(100, Math.round(out.score))), summary: out.summary, checks, specimen: out.specimen === true, source: 'ai' };
    } catch (err) {
      if (err.name === 'AbortError') throw err;
      console.warn('Document check fell back to basic scoring:', err.message);
    }
  }
  return basicCheck(files);
}

export function basicCheck(files) {
  let score = 0;
  const checks = DOCS.map((d) => {
    const f = files[d.id];
    if (!f) return { doc: d.id, status: 'missing', note: 'Not uploaded.' };
    const ok = f.size > 30_000; // a readable scan is rarely tiny
    score += ok ? d.weight : Math.round(d.weight / 2);
    return { doc: d.id, status: ok ? 'ok' : 'warning', note: ok ? 'Received.' : 'Looks low quality — upload a clearer copy.' };
  });
  return { score, summary: 'Checked which documents are present (AI review unavailable).', checks, source: 'basic' };
}
