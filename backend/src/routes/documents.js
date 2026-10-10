import { Router } from 'express';
import multer from 'multer';
import fs from 'node:fs';
import path from 'node:path';
import { DOCS, checkDocuments } from '../documents.js';
import { viewerOf } from '../present.js';
import { HttpError } from './journeys.js';

const upload = multer({
  storage: multer.memoryStorage(), // held in memory only during check
  limits: { fileSize: 8 * 1024 * 1024, files: 4 },
  fileFilter: (_req, file, cb) => cb(null, Boolean(EXT[file.mimetype])),
});

// Only formats a reviewer can view safely; the extension comes from the type, never the client's file name.
const EXT = { 'image/jpeg': '.jpg', 'image/png': '.png', 'image/webp': '.webp', 'application/pdf': '.pdf' };

export function documentsRouter(store, { llm, voice, autoCallScore = 70, allowSpecimens = false, docsDir }) {
  const r = Router();

  r.get('/documents', (_req, res) => res.json({ documents: DOCS.map(({ id, label }) => ({ id, label })), passScore: autoCallScore }));

  // The signed-in user's most recent check, for the travel desk.
  r.get('/me/documents', (req, res) => {
    const { userId } = viewerOf(req, store);
    const l = userId ? store.leads().find((x) => x.userId === userId && x.source === 'documents') : null;
    res.json({
      check: l
        ? { score: l.docScore, passScore: autoCallScore, summary: '', checks: l.docChecks ?? [], qualified: Boolean(l.qualified), call: { status: l.call?.status ?? 'not_triggered' }, source: 'ai', destination: l.destination, at: l.updatedAt }
        : null,
    });
  });

  r.post('/documents/check', upload.fields(DOCS.map((d) => ({ name: d.id, maxCount: 1 }))), async (req, res, next) => {
    try {
      const { userId } = viewerOf(req, store);
      const user = userId && store.creator(userId);
      if (!user) throw new HttpError(401, 'Create your profile first.');
      const files = Object.fromEntries(Object.entries(req.files ?? {}).map(([k, v]) => [k, v[0]]));
      if (!Object.keys(files).length) throw new HttpError(400, 'Add at least one document.');

      const destination = String(req.body.destination ?? '').slice(0, 60);
      const month = Number(req.body.month) || null;
      const travelers = Math.max(1, Math.min(20, Number(req.body.travelers) || 1));
      const consent = req.body.consent === 'true' || user.consent === true;

      const result = await checkDocuments({ llm, files, destination, month, travelers, allowSpecimens });
      const qualified = Boolean(user.phone) && consent && result.score >= autoCallScore;
      const lead = store.upsertLead({
        userId,
        name: user.name,
        handle: user.handle,
        phone: consent ? user.phone : null,
        consent,
        lang: req.body.lang === 'en' ? 'en' : 'ml',
        source: 'documents',
        title: `Visa check${destination ? ` · ${destination}` : ''}`,
        destination,
        month,
        travelers,
        docScore: result.score,
        docChecks: result.checks,
        testDocs: result.specimen === true,
        score: result.score,
        qualified,
        journeyId: req.body.journeyId || undefined,
        planId: 'docs',
        hasDocs: true,
      });

      // Persist uploaded documents to disk so the CRM can view them later.
      // Each lead gets its own folder: <docsDir>/<leadId>/
      // Re-submissions overwrite the previous files for the same doc slot.
      if (docsDir) {
        try {
          const leadDir = path.join(docsDir, lead.id);
          fs.mkdirSync(leadDir, { recursive: true });
          for (const [docId, f] of Object.entries(files)) {
            // Replace any earlier upload for this slot, whatever its format.
            for (const old of fs.readdirSync(leadDir)) if (old.startsWith(`${docId}.`)) fs.rmSync(path.join(leadDir, old));
            fs.writeFileSync(path.join(leadDir, `${docId}${EXT[f.mimetype]}`), f.buffer);
          }
        } catch (saveErr) {
          console.warn('Could not save documents to disk:', saveErr.message);
        }
      }

      const call = qualified ? await voice.callLead(lead) : { status: 'not_triggered' };
      res.json({ ...result, passScore: autoCallScore, qualified, call, leadId: lead.id });
    } catch (err) {
      next(err);
    }
  });

  return r;
}
