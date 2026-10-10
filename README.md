# Travelgram

Travel dispatches from Kerala, written by people who went. Every journey has a route, postcards, a story and an exact budget, and is signed by the traveller who wrote it. **Ammachi**, a Malayali grandmother, recommends journeys out loud in Malayalam (or English), crediting each writer by name.

- `backend/`: Express 5 API: journeys, uploads, place search, saves/likes, and Ammachi (Gemini + Sarvam Bulbul voice).
- `app/`: Flutter app (Android, iOS and web).

## Run it

### 1. Backend

```bash
cd backend
npm install
npm start          # http://localhost:4000 (also prints your LAN address for a phone)
```

Put your keys in `backend/.env` (already created; `.env.example` documents every setting):

```
GEMINI_API_KEY=...      # Ammachi's brain  (https://aistudio.google.com/apikey)
SARVAM_API_KEY=...      # Ammachi's voice, Bulbul TTS (https://dashboard.sarvam.ai)
```

Restart after editing. Without keys everything still works, honestly labelled:
- **No Gemini key:** Ammachi answers from the journey catalogue with fixed templates. The app shows "Offline catalogue" and marks each reply "OFFLINE MODE".
- **No Sarvam key:** replies are text only ("text only" in the status line).

The model defaults to `gemini-flash-latest` (Google's alias for the current Flash model) with `GEMINI_THINKING_LEVEL=LOW` to keep voice replies quick. The voice defaults to `bulbul:v3`, speaker `kavitha`. All of these can be changed in `.env`.

### 2. App

```bash
cd app
flutter pub get
flutter run                 # Android emulator: talks to http://10.0.2.2:4000 automatically
flutter run -d chrome       # web: talks to http://<same host>:4000
```

**On a physical phone:** keep the phone on the same Wi-Fi as the laptop, then **long-press the "Travelgram" wordmark** on the front page and enter the address the backend printed (e.g. `http://192.168.1.20:4000`). You can also bake it in at build time with `--dart-define=API_BASE=http://...`.

**Malayalam voice input** uses the phone's speech recogniser. On Android that's Google's speech service with Malayalam (`ml-IN`) available; if Ammachi can't hear you, check Settings → Google → Voice / speech languages. Typing always works.

### Reset the demo data

```bash
cd backend && npm run reset    # back to the 10 seed journeys; drops test posts, saves and likes
```

## A 3-minute demo

1. **Front page (Issue tab).** It opens like a magazine: "The October Dispatch". The cover story is whatever is in season this month. Every photo is mounted as a stamp, and every card is signed. Tap a mood ticket (Monsoon, Food, Under ₹10k) to filter.
2. **Open the cover story.** The hero photo leads into a torn-paper page. Scroll through the telegram strip (days, stops, people, total), then **The route**: an ink line that draws itself between numbered stops. Tap **Maps** to open the real route in Google Maps. Each stop is a postcard: **tap one to turn it over** for the story and a handwritten tip. Then **What it cost**, laid out as a perforated route ticket with a per-person-per-day figure. Tap the bookmark: a red **SAVED** stamp slams onto the photo, and the journey appears in the Album.
3. **Ask Ammachi** (centre tab, or "Ask Ammachi about this trip" on any journey). Her lamp burns brighter while she thinks. Tap **മഴക്കാലത്ത് എവിടെ പോകണം?** ("Where should I go this monsoon?") or tap the gold mic and ask her out loud. She answers in Malayalam and credits each writer by name ("Joel Varghese എഴുതിയ…"); with a Sarvam key she speaks it aloud while her mouth moves. The journeys she mentions appear as stamps you can open. Switch **മല / EN** for English.
4. **Write a dispatch (Write tab).** Sign once ("Who's writing?"), add photos (they upload while you keep going), name the trip, search places (the map draws as you add stops), add stories, tap the budget chips, then **Post dispatch**: a POSTED stamp lands and the new journey opens at the top of the front page. Then ask Ammachi about that place (e.g. "Anything in Vagamon?"). New dispatches get a freshness boost, so she recommends yours, credited to you.

## Tests

```bash
cd backend && npm test     # 18 tests: API, creating a journey, Ammachi streaming/citations/fallback/voice order,
                           # and the real Gemini SDK call against a local mock of the Gemini API
cd app && flutter test     # 13 tests: formatting, the creator's draft rules, and app flows against a mocked server
```

## How Ammachi works

`POST /api/ammachi/chat` streams Server-Sent Events. For every question the backend rebuilds a catalogue from the **live** journey database, ranks it (Malayalam and Manglish keywords, budget, days, the current month, the journey you're reading), and hands it to Gemini with her persona. Gemini cites journeys as `[[journey:ID]]` markers. The server strips the markers and sends a `cite` event with the real journey card, author included. **IDs that don't exist are dropped, so she can't invent a trip.** Text is split into sentences as it streams; each sentence is voiced by Sarvam Bulbul in parallel, and audio is sent in order, so she starts speaking before she has finished thinking. If Gemini fails before saying anything, she falls back to the catalogue rather than going silent.

## Notes and known limits

- Data lives in `backend/data/db.json`, a JSON file seeded from `data/seed.json`. That's fine for a hackathon, not for production.
- Seed photos come from Wikimedia Commons; each photographer and licence is shown on the journey page and in the full-screen viewer. `npm run seed:build` regenerates them, geocoding stops with OpenStreetMap Nominatim.
- Place search checks a local gazetteer first, then Nominatim for anything else (needs internet).
- On the **web build with a screen reader running**, typing a second place into the route search can stop registering after a result is picked (a Flutter web text-field quirk). Mouse and touch users aren't affected, and neither is the Android app.
- No accounts: saves and likes are tied to an anonymous device ID, and a traveller profile is created the first time you write.
