"""Generates two SPECIMEN test documents for demoing the document checker.

They describe a fictional person and a fictional bank, carry a SPECIMEN
watermark, and are only accepted when DOC_CHECK_ALLOW_SPECIMENS=true.
Run with Pillow:  python scripts/make-specimens.py
"""

from datetime import date, timedelta
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

OUT = Path(__file__).resolve().parent.parent / "public" / "samples"
OUT.mkdir(parents=True, exist_ok=True)
F = "C:/Windows/Fonts/"


def font(name, size):
    return ImageFont.truetype(F + name, size)


def watermark(img, text="SPECIMEN · TEST DATA · NOT A VALID DOCUMENT"):
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    f = font("arialbd.ttf", 34)
    for y in range(-200, img.size[1] + 200, 180):
        d.text((-100, y), text, font=f, fill=(200, 30, 30, 70))
    layer = layer.rotate(18, center=(img.size[0] / 2, img.size[1] / 2))
    return Image.alpha_composite(img.convert("RGBA"), layer).convert("RGB")


today = date.today()

# ---- residence permit specimen -------------------------------------------------
W, H = 1400, 880
img = Image.new("RGB", (W, H), (244, 247, 245))
d = ImageDraw.Draw(img)
d.rectangle([0, 0, W, 110], fill=(20, 83, 45))
d.text((40, 24), "RESIDENCE PERMIT — SPECIMEN", font=font("arialbd.ttf", 40), fill="white")
d.text((40, 72), "Test document for Travelgram's document checker. Fictional person.", font=font("arial.ttf", 22), fill=(220, 240, 225))
d.rectangle([40, 150, 330, 520], outline=(120, 130, 125), width=3)
d.text((95, 315), "PHOTO", font=font("arialbd.ttf", 40), fill=(150, 160, 155))
issue = today - timedelta(days=400)
expiry = today + timedelta(days=3 * 365)
rows = [
    ("Name", "TEST TRAVELLER, ASHA"),
    ("Nationality", "Utopia (specimen)"),
    ("Profession", "Software Engineer"),
    ("Sponsor", "Example Tech LLC (fictional)"),
    ("Place of issue", "Dubai"),
    ("File number", "000/0000/0/000000 (specimen)"),
    ("Issue date", issue.strftime("%d/%m/%Y")),
    ("Expiry date", expiry.strftime("%d/%m/%Y")),
]
y = 150
for k, v in rows:
    d.text((380, y), k.upper(), font=font("arial.ttf", 20), fill=(90, 100, 95))
    d.text((380, y + 24), v, font=font("arialbd.ttf", 30), fill=(20, 30, 25))
    y += 82
d.text((40, H - 60), f"SPECIMEN · valid until {expiry.strftime('%d %b %Y')} · not issued by any authority", font=font("arial.ttf", 22), fill=(120, 30, 30))
watermark(img).save(OUT / "specimen-residence-visa.jpg", quality=92)

# ---- bank statement specimen ---------------------------------------------------
W, H = 1240, 1754
img = Image.new("RGB", (W, H), "white")
d = ImageDraw.Draw(img)
d.rectangle([0, 0, W, 150], fill=(30, 58, 138))
d.text((60, 36), "EXAMPLE BANK (FICTIONAL)", font=font("arialbd.ttf", 46), fill="white")
d.text((60, 96), "Account statement — SPECIMEN for software testing", font=font("arial.ttf", 26), fill=(210, 220, 245))
start = (today.replace(day=1) - timedelta(days=85)).replace(day=1)
info = [
    ("Account holder", "Asha Test Traveller"),
    ("Account", "XXXX XXXX 0000 (specimen)"),
    ("Currency", "AED"),
    ("Period", f"{start.strftime('%d %b %Y')} – {today.strftime('%d %b %Y')}"),
]
y = 190
for k, v in info:
    d.text((60, y), k, font=font("arial.ttf", 24), fill=(100, 100, 110))
    d.text((380, y), v, font=font("arialbd.ttf", 26), fill=(20, 20, 30))
    y += 44

y += 30
d.rectangle([60, y, W - 60, y + 50], fill=(238, 242, 255))
cols = [(75, "Date"), (300, "Description"), (760, "Debit"), (900, "Credit"), (1060, "Balance")]
for x, t in cols:
    d.text((x, y + 12), t, font=font("arialbd.ttf", 22), fill=(30, 58, 138))
y += 60

balance = 18450
tx = []
m = start
for month in range(3):
    m1 = (start.replace(day=1) + timedelta(days=32 * month)).replace(day=1)
    tx += [
        (m1.replace(day=1), "Salary — Example Tech LLC", 0, 14000),
        (m1.replace(day=3), "Rent transfer", 6500, 0),
        (m1.replace(day=8), "Supermarket", 820, 0),
        (m1.replace(day=14), "DEWA utilities", 540, 0),
        (m1.replace(day=20), "Restaurants", 610, 0),
        (m1.replace(day=26), "Savings interest", 0, 35),
    ]
tx = [t for t in tx if t[0] <= today]
d.text((75, y), start.strftime("%d/%m/%Y"), font=font("consola.ttf", 22), fill=(60, 60, 70))
d.text((300, y), "Opening balance", font=font("arial.ttf", 22), fill=(60, 60, 70))
d.text((1060, y), f"{balance:,.2f}", font=font("consola.ttf", 22), fill=(20, 20, 30))
y += 40
for when, what, debit, credit in tx:
    balance += credit - debit
    d.text((75, y), when.strftime("%d/%m/%Y"), font=font("consola.ttf", 22), fill=(60, 60, 70))
    d.text((300, y), what, font=font("arial.ttf", 22), fill=(30, 30, 40))
    if debit:
        d.text((760, y), f"{debit:,.2f}", font=font("consola.ttf", 22), fill=(170, 30, 30))
    if credit:
        d.text((900, y), f"{credit:,.2f}", font=font("consola.ttf", 22), fill=(20, 120, 50))
    d.text((1060, y), f"{balance:,.2f}", font=font("consola.ttf", 22), fill=(20, 20, 30))
    y += 40
    d.line([60, y - 6, W - 60, y - 6], fill=(235, 235, 240))

y += 30
d.rectangle([60, y, W - 60, y + 90], fill=(240, 253, 244))
d.text((80, y + 14), "Closing balance", font=font("arial.ttf", 26), fill=(60, 60, 70))
d.text((80, y + 48), f"AED {balance:,.2f}", font=font("arialbd.ttf", 34), fill=(20, 110, 50))
d.text((60, H - 80), "SPECIMEN · fictional bank and account holder · generated for testing only", font=font("arial.ttf", 22), fill=(120, 30, 30))
watermark(img).save(OUT / "specimen-bank-statement.jpg", quality=92)

# ---- passport data page specimen (ICAO's fictional "Utopia") -------------------
W, H = 1400, 980
img = Image.new("RGB", (W, H), (236, 241, 248))
d = ImageDraw.Draw(img)
d.rectangle([0, 0, W, 120], fill=(30, 41, 99))
d.text((40, 22), "PASSPORT — SPECIMEN", font=font("arialbd.ttf", 44), fill="white")
d.text((40, 76), "Republic of Utopia (fictional state used for sample documents) · Test data", font=font("arial.ttf", 22), fill=(205, 215, 240))
# photo placeholder: a plain silhouette, no real face
d.rectangle([40, 160, 360, 560], fill=(214, 222, 235), outline=(110, 120, 140), width=3)
d.ellipse([140, 210, 260, 340], fill=(150, 160, 180))
d.rounded_rectangle([95, 350, 305, 560], radius=60, fill=(150, 160, 180))
p_issue = today - timedelta(days=2 * 365)
p_expiry = today + timedelta(days=8 * 365)
born = date(1994, 4, 12)
prow = [
    ("Type / Code", "P  /  UTO"),
    ("Passport No.", "SPEC00000"),
    ("Surname", "TEST TRAVELLER"),
    ("Given names", "ASHA"),
    ("Nationality", "UTOPIAN (specimen)"),
    ("Date of birth", born.strftime("%d %b %Y").upper()),
    ("Sex", "F"),
    ("Date of issue", p_issue.strftime("%d %b %Y").upper()),
    ("Date of expiry", p_expiry.strftime("%d %b %Y").upper()),
]
x1, x2, y = 410, 880, 160
for i, (k, v) in enumerate(prow):
    x = x1 if i % 2 == 0 else x2
    d.text((x, y), k.upper(), font=font("arial.ttf", 19), fill=(90, 100, 120))
    d.text((x, y + 24), v, font=font("arialbd.ttf", 28), fill=(20, 25, 40))
    if i % 2 == 1:
        y += 84
y += 84
d.rectangle([0, H - 190, W, H], fill=(250, 251, 253))
mrz1 = "P<UTOTEST<TRAVELLER<<ASHA<<<<<<<<<<<<<<<<<<<"
mrz2 = f"SPEC00000<0UTO{born.strftime('%y%m%d')}0F{p_expiry.strftime('%y%m%d')}0<<<<<<<<<<<<<<00"
d.text((40, H - 160), mrz1, font=font("consola.ttf", 38), fill=(30, 30, 40))
d.text((40, H - 100), mrz2, font=font("consola.ttf", 38), fill=(30, 30, 40))
d.text((40, H - 230), f"SPECIMEN · valid until {p_expiry.strftime('%d %b %Y')} · not issued by any authority", font=font("arial.ttf", 22), fill=(120, 30, 30))
watermark(img).save(OUT / "specimen-passport.jpg", quality=92)

print("Closing balance AED", balance)
print("Saved to", OUT)
