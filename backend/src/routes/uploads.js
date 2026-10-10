import { Router } from 'express';
import multer from 'multer';
import path from 'node:path';
import crypto from 'node:crypto';
import fs from 'node:fs';
import { absolutize } from '../present.js';
import { HttpError } from './journeys.js';

const IMAGE_EXT = /\.(jpe?g|png|webp|heic|heif)$/i;

export function uploadsRouter(uploadsDir) {
  fs.mkdirSync(uploadsDir, { recursive: true });
  const upload = multer({
    storage: multer.diskStorage({
      destination: uploadsDir,
      filename: (_req, file, cb) => {
        const ext = (path.extname(file.originalname) || '.jpg').toLowerCase();
        cb(null, `${Date.now()}-${crypto.randomUUID().slice(0, 8)}${IMAGE_EXT.test(ext) ? ext : '.jpg'}`);
      },
    }),
    limits: { fileSize: 12 * 1024 * 1024, files: 1 },
    fileFilter: (_req, file, cb) => cb(null, file.mimetype.startsWith('image/') || IMAGE_EXT.test(file.originalname)),
  });

  const r = Router();
  r.post('/uploads', upload.single('photo'), (req, res) => {
    if (!req.file) throw new HttpError(400, 'Attach an image in the "photo" field.');
    res.status(201).json({ url: absolutize(req, `/static/uploads/${req.file.filename}`) });
  });
  return r;
}
