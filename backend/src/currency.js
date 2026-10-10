// Fixed reference rates (AED per unit of each currency). Good enough to compare
// and filter trips priced in different currencies — not for real money.
export const AED_PER = {
  AED: 1,
  USD: 3.6725,
  EUR: 4.0,
  GBP: 4.65,
  INR: 0.0435,
  OMR: 9.55,
  SAR: 0.98,
  QAR: 1.01,
  BHD: 9.74,
  KWD: 11.95,
  GEL: 1.35,
  TRY: 0.107,
};

export const CURRENCIES = Object.keys(AED_PER);

// The currency people usually budget in for each country.
export const COUNTRY_CURRENCY = {
  'United Arab Emirates': 'AED',
  UAE: 'AED',
  Oman: 'OMR',
  'Saudi Arabia': 'SAR',
  Qatar: 'QAR',
  Bahrain: 'BHD',
  Kuwait: 'KWD',
  India: 'INR',
  Georgia: 'GEL',
  Türkiye: 'TRY',
  Turkey: 'TRY',
  'United States': 'USD',
  'United Kingdom': 'GBP',
};

export function toAed(amount, currency) {
  return Math.round(amount * (AED_PER[currency] ?? 1));
}

export function fromAed(amountAed, currency) {
  return Math.round(amountAed / (AED_PER[currency] ?? 1));
}

const SYMBOL = { INR: '₹', USD: '$', EUR: '€', GBP: '£' };

function groupIndian(n) {
  const s = String(Math.abs(n));
  if (s.length <= 3) return s;
  const last3 = s.slice(-3);
  const rest = s.slice(0, -3).replace(/\B(?=(\d{2})+(?!\d))/g, ',');
  return `${rest},${last3}`;
}

export function formatMoney(amount, currency = 'AED') {
  const n = Math.round(amount);
  const digits = currency === 'INR' ? groupIndian(n) : Math.abs(n).toLocaleString('en-US');
  const sign = n < 0 ? '-' : '';
  return SYMBOL[currency] ? `${sign}${SYMBOL[currency]}${digits}` : `${sign}${currency} ${digits}`;
}
