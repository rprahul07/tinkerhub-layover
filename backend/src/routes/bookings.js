// Demo bookings: hotels, activities and transport from a trip's itinerary.
// "Payment" is simulated — no card data is taken and nothing is charged.
import { Router } from 'express';
import { formatMoney, toAed } from '../currency.js';
import { viewerOf } from '../present.js';
import { HttpError } from './journeys.js';

export const COMMISSION = 0.1;

export function bookingsRouter(store) {
  const r = Router();

  r.post('/bookings', (req, res) => {
    const { userId } = viewerOf(req, store);
    if (!userId) throw new HttpError(401, 'Create your profile first.');
    const b = req.body ?? {};
    const journey = store.journey(String(b.journeyId ?? ''));
    if (!journey) throw new HttpError(404, 'Trip not found.');
    const amount = Math.round(Number(b.amount));
    if (!(amount > 0)) throw new HttpError(400, 'Nothing to pay.');
    const guests = Math.max(1, Math.min(20, Number(b.guests) || 1));
    const currency = journey.currency ?? 'AED';
    const total = amount * (b.category === 'stay' ? 1 : guests);
    const amountAed = toAed(total, currency);
    const user = store.creator(userId);
    const booking = store.addBooking({
      userId,
      name: user.name,
      handle: user.handle,
      journeyId: journey.id,
      journeyTitle: journey.title,
      item: String(b.item ?? 'Booking').slice(0, 80),
      category: String(b.category ?? 'other'),
      date: String(b.date ?? '').slice(0, 10),
      guests,
      total,
      currency,
      amountAed,
      commissionAed: Math.round(amountAed * COMMISSION),
      status: 'confirmed',
      payment: 'demo',
    });
    res.status(201).json({ booking: { ...booking, totalLabel: formatMoney(total, currency) } });
  });

  r.get('/me/bookings', (req, res) => {
    const { userId } = viewerOf(req, store);
    res.json({ bookings: userId ? store.bookings().filter((b) => b.userId === userId).map((b) => ({ ...b, totalLabel: formatMoney(b.total, b.currency) })) : [] });
  });

  return r;
}
