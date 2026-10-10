import { Router } from 'express';
import multer from 'multer';
import { DOCS, checkDocuments } from '../documents.js';
import { viewerOf } from '../present.js';
import { HttpError } from './journeys.js';

const upload = multer({
  storage: multer.memoryStorage(), // never written to disk
  limits: { fileSize: 8 * 1024 * 1024, files: 4 },
  fileFilter: (_req, file, cb) => cb(null, /^image\/|^application\/pdf$/.test(file.mimetype)),
});

export function documentsRouter(store, { llm, voice, autoCallScore = 70, allowSpecimens = false }) {
  const r = Router();

  r.get('/documents', (_req, res) => res.json({ documents: DOCS.map(({ id, label }) => ({ id, label })), passScore: autoCallScore }));

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
      });
      const call = qualified ? await voice.callLead(lead) : { status: 'not_triggered' };
      res.json({ ...result, passScore: autoCallScore, qualified, call, leadId: lead.id });
    } catch (err) {
      next(err);
    }
  });

  return r;
}
