# 🎮 NMT Quiz — Architecture Reference

> **This document describes the application as it is built.** It is the authoritative architecture reference for the NMT Quiz Multiplayer project.
>
> For setup and running instructions, see [`planImplementation.md`](planImplementation.md).
> For a quick AI-agent reference, see [`AGENTS.md`](../AGENTS.md).

---

## 🧠 Context

Ukrainian students (16 yo) need to pass the **NMT (НМТ)** national exam. This app makes studying fun by turning it into a real-time multiplayer quiz game — like **QuizUp** but for Ukrainian exam prep.

### Language Rules

| Layer | Language |
|---|---|
| All UI text, labels, buttons, messages | 🇺🇦 **Ukrainian** |
| Code (variables, functions, classes, comments) | 🇬🇧 **English** |
| Server logs (BE) | 🇬🇧 **English** |
| Flutter logs (FE) | 🇬🇧 **English** |

Logs are structured JSON so they can be pasted directly to an AI for debugging. See [Logging Strategy](#-logging-strategy) below.

**Dataset is already done and READ-ONLY.** See [`data-set/README.md`](../data-set/README.md).

---

## 📦 Available Subjects (from `data-set/questions/`)

| Subject key | Display name | Questions |
|---|---|---|
| `ukrainian_language` | Українська мова та література | 1,923 |
| `history` | Історія України | 1,138 |
| `geography` | Географія | 476 |
| `math` | Математика | 58 (demo only) |

> Language and Literature are combined — the source dataset does not distinguish them.

---

## 🏗️ Tech Stack

### Backend
- **Node.js + Express v4 + TypeScript** — thin REST API + server-authoritative game engine
- **Supabase PostgreSQL** (free tier) — `questions`, `rooms`, `players`, `round_answers` tables
  - Backend uses **service-role key** (full access, never exposed to clients)
  - Frontend uses **anon key** (RLS blocks access to `correct_answer_index`)
- **Supabase Realtime** (Broadcast) — server→client event bus
  - Backend broadcasts via HTTP API with service-role key (`channel.httpSend()`)
  - Flutter clients subscribe directly to channels
- Architecture: `domain / data / presentation` layers

> **Why keep Node.js?** Supabase Realtime is a dumb pub/sub bus with no server-side logic. The 5-minute round timer, answer validation, scoring, and `correct_answer_index` security all require a real server process.

### Frontend
- **Flutter Web** — cross-platform, runs in browser (and mobile via LAN mode)
- **flutter_bloc** (Cubits) — state management
- **fpdart** — functional error handling (`Either<Failure, T>`)
- **go_router v17** — web-aware navigation (handles deep links like `/room/A9X`)
- **flutter_animate** — bouncy animations, staggered reveals
- **Material3 dark theme** — seed color `#4ECDC4`, background `#0D1117`

> `shadcn_flutter` is **NOT installed**. Material3 dark theme is used instead.

---

## 📦 Package Versions (Locked)

### Backend (`backend/package.json`)

| Package | Version | Purpose |
|---|---|---|
| `express` | `^4.22.1` | HTTP server |
| `@supabase/supabase-js` | `^2.98.0` | Supabase client (DB queries + Realtime broadcast) |
| `nanoid` | `^5.1.6` | 3-char room code generation |
| `zod` | `^3.25.76` | Request payload validation |
| `pino` | `^8.21.0` | Structured JSON logger |
| `pino-pretty` | `^10.3.1` | Dev-friendly log formatting |
| `express-rate-limit` | `^7.5.1` | Rate-limit room creation |
| `cors` | `^2.8` | CORS middleware |
| `helmet` | `^7.2.0` | Security headers |
| `dotenv` | `^16.3` | Environment variables |
| `uuid` | `^9.0.1` | UUID generation for player IDs |
| `tsx` (dev) | `^4.6` | Run TypeScript directly (replaces ts-node) |
| `typescript` (dev) | `^5.3` | TypeScript compiler |

**`tsconfig.json`** uses `"moduleResolution": "bundler"` — do NOT change to `nodenext` (pino v8 types incompatible).

### Frontend (`frontend/pubspec.yaml`)

| Package | Version | Purpose |
|---|---|---|
| `flutter_bloc` | `^9.1.1` | State management (Cubits) |
| `go_router` | `^17.1.0` | Web-aware navigation |
| `supabase_flutter` | `^2.12.0` | Realtime subscriptions + Auth |
| `fpdart` | `^1.2.0` | Functional error handling |
| `flutter_animate` | `^4.5.2` | Animations |
| `percent_indicator` | `^4.2.5` | Timer progress bar |
| `confetti` | `^0.8.0` | Winner celebration effect |
| `logger` | `^2.6.2` | Structured logging |
| `uuid` | `^4.5.3` | Session ID generation |
| `http` | `^1.6.0` | REST API calls |
| `google_fonts` | `^8.0.2` | Inter font family |
| `qr_flutter` | `^4.1.0` | QR code for room sharing |
| `url_launcher` | `^6.3.2` | Open AI explanation links |
| `equatable` | `^2.0.8` | State equality |

---

## 🗄️ Supabase PostgreSQL Schema

Three migrations in `/supabase/migrations/`. Apply with `make supabase-push`.

```sql
-- Migration 1: Initial schema
CREATE TABLE questions (
  id                   TEXT PRIMARY KEY,
  subject              TEXT NOT NULL,
  text                 TEXT NOT NULL,
  choices              TEXT[] NOT NULL,
  correct_answer_index INTEGER NOT NULL,   -- SECURITY: never send to clients
  exam_type            TEXT
);
CREATE INDEX idx_questions_subject ON questions (subject);

CREATE TABLE rooms (
  code                   TEXT PRIMARY KEY,
  subject                TEXT NOT NULL,
  status                 TEXT NOT NULL DEFAULT 'waiting'
                           CHECK (status IN ('waiting', 'playing', 'finished')),
  max_players            INTEGER NOT NULL,
  question_ids           TEXT[] DEFAULT '{}',
  current_question_index INTEGER DEFAULT 0,
  round_started_at       TIMESTAMPTZ,
  created_at             TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE players (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  room_code  TEXT NOT NULL REFERENCES rooms(code) ON DELETE CASCADE,
  name       TEXT NOT NULL,
  color      TEXT NOT NULL,
  score      INTEGER DEFAULT 0,
  is_creator BOOLEAN DEFAULT false,
  joined_at  TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX idx_players_room ON players (room_code);

-- Migration 2: Atomic score update
CREATE OR REPLACE FUNCTION increment_player_score(player_id uuid, delta int, r_code text)
RETURNS void AS $$
  UPDATE players SET score = score + delta
  WHERE id = player_id AND room_code = r_code;
$$ LANGUAGE sql;

-- Migration 3: Answer persistence
CREATE TABLE round_answers (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  room_code    TEXT NOT NULL REFERENCES rooms(code) ON DELETE CASCADE,
  round_number INTEGER NOT NULL,
  player_id    UUID NOT NULL REFERENCES players(id) ON DELETE CASCADE,
  question_id  TEXT NOT NULL,
  answer_index INTEGER NOT NULL,
  is_correct   BOOLEAN NOT NULL,
  created_at   TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX idx_round_answers_room   ON round_answers (room_code, round_number);
CREATE INDEX idx_round_answers_player ON round_answers (player_id);
```

---

## 🌐 REST API

All endpoints prefixed `/api`. `:code` = 3-char uppercase alphanumeric.

| Method | Path | Auth | Body / Returns |
|--------|------|------|----------------|
| `GET` | `/api/subjects` | — | `{ subjects: [{key, displayName, questionCount, enabled}] }` |
| `POST` | `/api/rooms` | — | Body: `{subject, maxPlayers}` → `{code}` (rate-limited: 10/15min/IP) |
| `GET` | `/api/rooms/:code` | — | Room + players + `currentQuestion?` (no `correct_answer_index`) |
| `POST` | `/api/rooms/:code/join` | — | Body: `{sessionId?}` → `{playerId, name, color, isCreator, status}` |
| `POST` | `/api/rooms/:code/start` | playerId | Body: `{playerId}` → `{ok: true}` (creator only) |
| `POST` | `/api/rooms/:code/answer` | playerId | Body: `{playerId, questionId, answerIndex: 0–4}` |
| `POST` | `/api/rooms/:code/heartbeat` | playerId | Body: `{playerId}` → `{ok: true}` (every 30s) |
| `POST` | `/api/rooms/:code/restart` | playerId | Body: `{playerId}` → creator only, `status=finished` |
| `POST` | `/api/rooms/:code/next-question` | playerId | Body: `{playerId}` → creator only |
| `GET` | `/api/rooms/:code/round-state` | — | `{playerAnswers, pendingReveal}` — polling fallback |

All request bodies are validated with Zod schemas (`backend/src/presentation/validators/requestSchemas.ts`).

---

## 📡 Real-time Architecture

```
Client → Server : REST POST (answer submit, heartbeat, start, next-question, restart)
Server → Client : Supabase Realtime Broadcast (all game events)
Fallback        : Client polls REST every 1s for missed events
```

### Supabase Broadcast Events (channel `room:{CODE}`)

| Event | Direction | Payload |
|-------|-----------|---------|
| `game:start` | S→C | `{ totalQuestions: 5, timerMs: 300000 }` |
| `question:new` | S→C | `{ id, subject, text, choices }` |
| `round:update` | S→C | `{ playerAnswers: { playerId: index\|null } }` |
| `round:reveal` | S→C | `{ correctIndex, playerAnswers, scores: {playerId: total}, scoreDeltas: {playerId: delta} }` |
| `game:end` | S→C | `{ scoreboard: [{ rank, id, name, color, score }] }` |
| `room:state` | S→C | `{ code, subject, status, maxPlayers, currentQuestionIndex, players: [...] }` |
| `player:disconnected` | S→C | `{ playerId }` |

> `question:new` **never** includes `correct_answer_index`. The frontend `SupabaseService` logs a `security.violation` event if it ever appears.
>
> Timing and progress metadata for reconnect/bootstrap are not part of the broadcast payload. They are provided by the REST room snapshot (`currentQuestion`) returned by `GET /api/rooms/:code` and rejoin responses. That snapshot may include `questionIndex`, `totalQuestions`, `roundStartedAt`, and `timerMs`.

---

## 🎮 Game Constants & Environment Overrides

| Constant | Default | Env Var Override |
|----------|---------|-----------------|
| Questions per game | `5` | — (hardcoded in `GameEngine.ts`) |
| Round timer | `300000 ms` (5 min) | `ROUND_TIMER_MS` |
| Auto-advance after reveal | `300000 ms` (5 min) | `PENDING_ROUND_TIMEOUT_MS` |
| Points per correct answer | `10` | — |
| Player disconnect timeout | `60000 ms` (60s) | — |
| Heartbeat check interval | `30000 ms` (30s) | — |
| Room cleanup delay (post-game) | `3600000 ms` (1 hr) | — |
| Rate limit | `10 rooms / 15 min / IP` | — |

For fast local testing: `ROUND_TIMER_MS=10000 PENDING_ROUND_TIMEOUT_MS=30000`.

---

## 👾 Game Flow (State Machine)

```
HomeScreen
  │ create room                          join room (enter code)
  ▼                                               │
CreateRoomScreen → POST /api/rooms                │
  │                                               │
  └───────────────► RoomLobbyScreen ◄─────────────┘
                      POST /api/rooms/:code/join
                      Supabase subscription starts
                      │ creator clicks "Start"
                      │ POST /api/rooms/:code/start
                      │ game:start broadcast
                      ▼
                    GameplayScreen
                      question:new broadcast
                      5-min countdown timer
                      │ answer submitted (or timer expires)
                      │ POST /api/rooms/:code/answer
                      │ round:reveal broadcast
                      ▼
                    RoundRevealScreen
                      show correct answer + scores
                      AI explanation buttons (ChatGPT/Gemini/Perplexity)
                      │ creator clicks "Next Question"
                      │ POST /api/rooms/:code/next-question
                      │ question:new broadcast (next round)
                      ▼
                    ... (5 rounds total) ...
                      │ game:end broadcast
                      ▼
                    ResultsScreen
                      final scoreboard + confetti (winner)
                      │ creator: "Грати знову" → POST /api/rooms/:code/restart
                      │          "Нова тема"   → navigate to /create
                      │ others:  "Нова гра"    → /create
                      │          "Приєднатися" → /
```

---

## 🧱 Backend Architecture

### Service Layer (`backend/src/services/`)

**`GameEngine.ts`** — core game logic:
- `startGame(roomCode)` → acquires mutex, calls `runGame()`
- `runGame(roomCode, subject, label)` → fetches 5 questions, broadcasts `game:start`, calls `startRound(0)`
- `startRound(roomCode, index, questions)` → broadcasts `question:new` (no `correct_answer_index`), sets round timer
- `submitAnswer(roomCode, playerId, questionId, answerIndex)` → records answer, broadcasts `round:update`, triggers early reveal if all answered
- `revealRound(roomCode)` → **deletes from `roundState` first** (race condition fix), scores players, persists answers, broadcasts `round:reveal`
- `nextQuestion(roomCode, playerId)` → validates creator, calls `advanceToNextRound()`
- `restartGame(roomCode)` → resets scores, calls `runGame()`
- `endGame(roomCode)` → updates status `finished`, broadcasts `game:end`, schedules 1h cleanup

**`PlayerManager.ts`** — connection lifecycle:
- Heartbeat tracking: 60s timeout, 30s check interval
- On disconnect: removes from DB (only if `waiting`), reassigns creator, broadcasts `room:state` + `player:disconnected`

**`CodeGenerator.ts`** — `generateUniqueCode()`: nanoid customAlphabet `A-Z0-9`, 3 chars, retries up to 10x

**`NameGenerator.ts`** — 50 Ukrainian animal-adjective pairs ("Веселий Кит"), 8 hex colors, per-room tracking, fallback "Гравець N"

### In-Memory State

All state is in Node.js process memory (not persisted). See `GameEngine.ts`:

| Map/Set | Contents |
|---------|---------|
| `roundState` | `{ answers: Map<playerId, index\|null>, timer, questions, questionIndex, roundStartedAt }` |
| `pendingNextRound` | `{ nextIndex, questions, fallbackTimer }` |
| `pendingRevealCache` | `{ correctIndex, playerAnswers, scores, scoreDeltas }` |
| `cleanupTimeouts` | Timeout handle per room |
| `startingMutex` | Set of room codes currently starting |

---

## 📱 Frontend Architecture

### Cubit Hierarchy

```
GameCubit        — subject list + room creation (used on home/create screens)
  └─ RoomCubit  — join, lobby state, players, heartbeat, rejoin recovery
       └─ QuizCubit — in-game: question, answers, timer, reveal, polling fallback
```

### File Structure (`frontend/lib/`)

```
main.dart             — Boot: Supabase init, multi-BlocProvider, stream coordinator
config/router.dart    — 6 routes: /, /create, /room/:code, .../game, .../reveal, .../results
core/
  app_logger.dart     — StructuredLogPrinter: 1 JSON line per log call
  failures.dart       — ServerFailure, NetworkFailure, ValidationFailure
  typedefs.dart       — FutureEither<T>, EitherT<T>
data/models/
  player_model.dart   — PlayerModel (id, name, color, score, isCreator)
  question_model.dart — ClientQuestion (id, subject, text, choices — no correct_answer_index)
services/
  api_service.dart    — REST client; all calls wrapped in _traced() for structured logging
  supabase_service.dart — Realtime subscription → broadcast StreamController
presentation/
  cubits/room_cubit/  — RoomCubit + RoomState
  cubits/quiz_cubit/  — QuizCubit + QuizState (QuizInitial|QuizQuestion|QuizReveal|QuizGameEnded|QuizError)
  cubits/game_cubit/  — GameCubit + GameState
  pages/              — 6 StatefulWidget pages
  widgets/
    answer_button.dart — AnswerState: idle | selected | correct | wrong
    timer_bar.dart     — M:SS display, color changes at 50%/25% thresholds
    player_chip.dart   — Avatar + name + answered checkmark
```

### Critical `main.dart` Wiring

```dart
// roomCubit stream coordinator — ensures QuizCubit always has context before game events
roomCubit.stream.listen((roomState) {
  if (roomState.myPlayerId != null) {
    quizCubit.setContext(roomState.myPlayerId!, roomState.code);
  }
  // Consume pending snapshot on rejoin (bootstrap timer + question state)
  if (roomCubit.hasPendingSnapshot && !quizCubit.isActiveGameState) {
    quizCubit.bootstrapFromSnapshot(roomCubit.consumePendingSnapshot());
  }
});
```

### Polling Fallback Strategy

All game screens start `QuizCubit.startPolling()` which polls `GET /api/rooms/:code/round-state` every 1s. This catches:
- Missed `round:reveal` → `pendingReveal` field is populated
- Missed `question:new` after creator advances → next round detected
- Game restart detection on results screen

---

## 🛡️ Security Model

| Rule | Enforcement |
|------|-------------|
| `correct_answer_index` never sent to clients | Stripped in `GameEngine.startRound()` before `question:new` broadcast |
| Backend uses service-role key | Configured in `backend/src/config/supabase.ts`; key in `SUPABASE_SERVICE_KEY` env var |
| Flutter uses anon key | `SUPABASE_ANON_KEY` passed as `--dart-define`; RLS blocks `correct_answer_index` reads |
| All REST bodies validated | Zod schemas in `backend/src/presentation/validators/requestSchemas.ts` |
| Client-side tripwire | `SupabaseService` logs `security.violation` if `correct_answer_index` appears in `question:new` |
| Rate limiting | `express-rate-limit`: 10 room creations per 15 min per IP |
| Helmet | Security headers on all responses |

---

## 📊 Implemented UI Features

All screens are dark-mode Material3. Key UI features beyond basic gameplay:

- **Room sharing** (RoomLobbyScreen): QR code modal (`qr_flutter`), copy link, share link
- **Fun facts carousel** (RoomLobbyScreen): NMT education tips in Ukrainian, rotates every 5s
- **Game start countdown** (RoomLobbyScreen): 3→2→1 animation when creator starts game
- **Optimistic answer UI** (GameplayScreen): Answer button locks immediately on tap; unlocks if server returns error
- **Player status chips** (GameplayScreen): Green checkmark appears as each player answers (via `round:update`)
- **AI explanation buttons** (RoundRevealScreen): ChatGPT, Gemini (copy prompt + open URL), Perplexity (auto-submit via `?q=`)
- **Score deltas** (RoundRevealScreen): Shows `+10` per player for this round
- **Confetti** (ResultsScreen): `confetti` package fires for 5s if current player is rank 1
- **Staggered animations**: All lists/grids use 80–100ms stagger via `flutter_animate`
- **Rejoin recovery**: `GET /api/rooms/:code` returns `currentQuestion` snapshot; frontend reconstructs correct timer state

---

## 🔊 Logging Strategy

### Backend Format

Every pino log has base fields `{ "service": "backend", "ts": "..." }` plus structured domain fields:

```json
{
  "service": "backend",
  "ts": "2026-03-06T10:30:45.123Z",
  "level": "info",
  "event": "game.round.start",
  "roomCode": "A9X",
  "questionIndex": 0,
  "totalQuestions": 5,
  "timerMs": 300000
}
```

HTTP requests include `requestId` (UUID, from `x-request-id` header or generated):
```json
{
  "event": "http.request.finish",
  "requestId": "a1b2-...",
  "method": "POST",
  "path": "/api/rooms/A9X/answer",
  "statusCode": 200,
  "durationMs": 12,
  "outcome": "success"
}
```

### Frontend Format

`createAppLogger()` from `core/app_logger.dart` outputs one JSON line per call:
```json
{
  "ts": "2026-03-06T10:30:45.123Z",
  "level": "INFO",
  "service": "frontend",
  "feature": "ApiService",
  "event": "api.request.finish",
  "requestId": "abc-123",
  "durationMs": 145,
  "outcome": "success"
}
```

All API calls are wrapped in `ApiService._traced()` which logs `api.request.start` + `api.request.finish`.

---

## 🚀 Deployment

### Backend (Render / Railway)

```
Build command : npm run build
Start command : npm start
Environment   : SUPABASE_URL, SUPABASE_SERVICE_KEY, SUPABASE_ANON_KEY,
                PORT, CORS_ORIGIN, NODE_ENV=production,
                LOG_LEVEL (optional), ROUND_TIMER_MS (optional)
```

### Frontend (Firebase Hosting)

```bash
flutter build web --release \
  --dart-define=SUPABASE_URL=https://xxx.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=eyJ... \
  --dart-define=API_URL=https://your-backend.onrender.com

firebase deploy
```

### Supabase

- Free tier supports 200 concurrent Realtime connections, 100 msg/sec.
- Channel name per room: `room:{CODE}` (e.g. `room:A9X`).
- Apply schema to cloud project: `supabase db push` or via Supabase MCP server.
- Seed questions: `make seed` (points at `SUPABASE_URL` + `SUPABASE_SERVICE_KEY` from `backend/.env`).
