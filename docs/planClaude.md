# 🤖 Claude Implementation Log

> This document records what has been implemented so the next AI agent can continue without re-reading the entire plan.
> Last updated: after Phase 3 (Flutter frontend) complete.

---

## ✅ Current State

**Backend: Phases 0, 1, 2 COMPLETE. `tsc --noEmit` passes with 0 TypeScript errors.**
**Frontend: Phase 3 COMPLETE. `flutter analyze --no-fatal-infos` passes with 0 issues.**
**Remaining: Phase 4 (Supabase setup + deploy) — needs real .env credentials.**

---

## 📁 Files Created

### Project root
- `Makefile` — `make check-be`, `make seed-db`, `make smoke-test` targets

### `backend/`
- `package.json` — `"type": "module"`, scripts: `dev`, `build`, `start`, `seed`, `typecheck`
- `tsconfig.json` — `target: ES2022`, `module: ESNext`, `moduleResolution: bundler`
- `.env.example` — template for required env vars

### `backend/src/config/`
- `logger.ts` — `pino` + `pino-pretty` logger
- `supabase.ts` — service-role Supabase client + `broadcastToRoom()` via REST API

### `backend/src/domain/`
- `types.ts` — copied from `data-set/types.ts` (canonical types)

### `backend/src/data/repositories/`
- `QuestionRepository.ts` — `getRandomQuestions`, `getQuestionsByIds`, `getSubjectCounts`
- `RoomRepository.ts` — `createRoom`, `getRoom`, `updateRoom`, `deleteRoom`, `getPlayers`, `addPlayer`, `incrementPlayerScore`

### `backend/src/scripts/`
- `seed.ts` — upserts 3,595 questions to Supabase in batches of 500

### `backend/src/services/`
- `CodeGenerator.ts` — `generateUniqueCode()` via `nanoid`, 3-char alphanumeric
- `NameGenerator.ts` — `assignName(roomCode)` → funny Ukrainian name + color; `clearRoom()`
- `GameEngine.ts` — **full game engine** (see details below)

### `backend/src/presentation/`
- `validators/requestSchemas.ts` — Zod schemas, subjects derived from `SUBJECTS` (no hardcoding)
- `controllers/SubjectController.ts` — `GET /api/subjects` → camelCase JSON response
- `controllers/RoomController.ts` — room creation, state read, player join
- `controllers/GameController.ts` — game start + answer submit
- `routes/index.ts` — all routes, rate-limit on POST /rooms, `validateRoomCode` middleware on all `:code` routes

### `backend/src/main.ts`
- Express + CORS + Helmet entry point

### `frontend/`
- `pubspec.yaml` — packages: flutter_bloc, fpdart, go_router, supabase_flutter, flutter_animate, percent_indicator, confetti, logger, equatable, url_launcher, http
- `lib/main.dart` — app entry, Supabase init, BlocProviders (RoomCubit, QuizCubit, GameCubit)
- `lib/config/router.dart` — go_router v17 routes: `/`, `/create`, `/room/:code`, `/room/:code/game`, `/room/:code/reveal`, `/room/:code/results`
- `lib/services/supabase_service.dart` — Realtime Broadcast subscription, typed `RealtimeEvent` stream
- `lib/services/api_service.dart` — HTTP calls to Node.js REST (createRoom, joinRoom, startGame, submitAnswer, getSubjects)
- `lib/core/failures.dart` + `typedefs.dart` — fpdart Either error handling
- `lib/data/models/question_model.dart` — `ClientQuestion.fromJson()`
- `lib/data/models/player_model.dart` — `PlayerModel.fromJson()`
- `lib/presentation/cubits/game_cubit/` — `createRoom` REST call
- `lib/presentation/cubits/room_cubit/` — lobby state, joinRoom (subscribe before REST), startGame, player disconnect handler
- `lib/presentation/cubits/quiz_cubit/` — in-game state: question, 5-min timer, answers, reveal, game:end
- `lib/presentation/pages/home_screen.dart` — two buttons + join dialog
- `lib/presentation/pages/create_room_screen.dart` — subject picker + player count
- `lib/presentation/pages/room_lobby_screen.dart` — auto-join on init, player list, start button for creator
- `lib/presentation/pages/gameplay_screen.dart` — TimerBar + question + AnswerButton grid + PlayerChip row
- `lib/presentation/pages/round_reveal_screen.dart` — correct/wrong highlight, scoreboard, 4s auto-advance
- `lib/presentation/pages/results_screen.dart` — scoreboard, confetti, creator gets "Нова гра" button
- `lib/presentation/widgets/timer_bar.dart` — LinearPercentIndicator, green→orange→red
- `lib/presentation/widgets/answer_button.dart` — AnimatedContainer + flutter_animate scale bounce
- `lib/presentation/widgets/player_chip.dart` — colored avatar chip with answered checkmark

---

## 🔧 Key Design Decisions & Fixes Applied

### GameEngine.ts architecture
- `roundState` Map stores `{ answers, timer, questions, questionIndex }` — questions are stored in memory so `submitAnswer` can validate `answerIndex` inline without a DB query.
- `cleanupTimeouts` Map tracks room cleanup handles so they can be cancelled (e.g. if game restarts).
- `roundState.delete(roomCode)` is called at the **start** of `revealRound` (after the null guard) — this prevents double-reveal in the race condition where a timer fires and `submitAnswer` both trigger reveal in the same async tick.
- `safeBroadcast()` wraps all `broadcastToRoom` calls — Supabase outages log an error instead of crashing the game loop.
- `ROUND_TIMER_MS` and `REVEAL_DELAY_MS` are overridable via env vars for testing (e.g. `ROUND_TIMER_MS=10000`).
- `answerIndex` is validated against `currentQuestion.choices.length` (not just max 4) to handle questions with 2–4 choices.

### requestSchemas.ts
- `CreateRoomSchema` derives subject enum from `SUBJECTS` array in `domain/types.ts` — no manual sync needed.

### SubjectController.ts
- Returns clean camelCase response: `{ key, displayName, questionCount, enabled }` — live `questionCount` from DB, no static duplicate `question_count`.

### routes/index.ts
- `validateRoomCode` middleware: rejects any `:code` param that isn't exactly 3 uppercase alphanumeric chars before the request hits the controller.

### tsconfig.json
- Uses `"moduleResolution": "bundler"` (not `"nodenext"`) — required because pino v8 types are incompatible with strict `nodenext` module resolution.

### @types/express
- Downgraded to `^4.17` to match the `express@4` runtime (avoids type/runtime mismatch where `req.params.code` was typed as `string | string[]`).

---

## ⚠️ Known Remaining Issues (Low Priority / Future Work)

| Issue | Severity | Notes |
|---|---|---|
| Non-atomic score increment | LOW | `incrementPlayerScore` does read-then-write. The double-reveal guard makes concurrent scoring impossible (only one `revealRound` per round), so in practice this is safe. Fix with Supabase RPC if needed. |
| No disconnect detection | MEDIUM | Supabase Realtime doesn't report disconnects to the server. `player:disconnected` event is never broadcast. Fix: add a `/api/rooms/:code/heartbeat` endpoint that clients ping every 30s; server removes players that miss 2+ heartbeats. |
| No creator reassignment | MEDIUM | If creator disconnects, no fallback. Fix: in `joinRoom` / heartbeat logic, reassign `is_creator` to the oldest remaining player. |
| No duplicate join prevention | MEDIUM | Client can call `POST /join` twice and get two player slots. Fix: require a client-provided `sessionId` header, store it in `players` table with a unique constraint. |
| No "play again" endpoint | LOW | Frontend design assumes users create a new room. Add `POST /api/rooms/:code/restart` later. |

---

## 🔴 What Still Needs to Be Done Before Running

### 1. Supabase setup (one-time)

Create a Supabase project (free tier) and run this SQL in the SQL editor:

```sql
CREATE TABLE questions (
  id                   TEXT PRIMARY KEY,
  subject              TEXT NOT NULL,
  text                 TEXT NOT NULL,
  choices              TEXT[] NOT NULL,
  correct_answer_index INTEGER NOT NULL,
  exam_type            TEXT
);
CREATE INDEX idx_questions_subject ON questions (subject);

CREATE TABLE rooms (
  code                    TEXT PRIMARY KEY,
  subject                 TEXT NOT NULL,
  status                  TEXT NOT NULL DEFAULT 'waiting'
                            CHECK (status IN ('waiting', 'playing', 'finished')),
  max_players             INTEGER NOT NULL,
  question_ids            TEXT[] DEFAULT '{}',
  current_question_index  INTEGER DEFAULT 0,
  round_started_at        TIMESTAMPTZ,
  created_at              TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE players (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  room_code   TEXT NOT NULL REFERENCES rooms(code) ON DELETE CASCADE,
  name        TEXT NOT NULL,
  color       TEXT NOT NULL,
  score       INTEGER DEFAULT 0,
  is_creator  BOOLEAN DEFAULT false,
  joined_at   TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX idx_players_room ON players (room_code);
```

### 2. `.env` setup

```bash
cd backend
cp .env.example .env
# Fill in: SUPABASE_URL, SUPABASE_SERVICE_KEY, SUPABASE_ANON_KEY
# For fast testing add: ROUND_TIMER_MS=15000  REVEAL_DELAY_MS=2000
```

### 3. Seed database

```bash
cd backend && npm run seed
# Expected: [Seed] Loaded 3595 questions from JSON ... [Seed] Done.
```

### 4. Verify backend works

```bash
# Terminal 1 — start server
cd backend && npm run dev

# Terminal 2 — smoke test
curl http://localhost:3000/api/subjects
# → { subjects: [{ key: "ukrainian_language", displayName: "Українська мова та література", questionCount: 1923, enabled: true }, ...] }

curl -X POST http://localhost:3000/api/rooms \
  -H 'Content-Type: application/json' \
  -d '{"subject":"history","maxPlayers":2}'
# → { code: "A9X" }

curl -X POST http://localhost:3000/api/rooms/A9X/join \
  -H 'Content-Type: application/json'
# → { playerId: "uuid", name: "Веселий Кит", color: "#FF6B6B", isCreator: true }
```

### 5. Full Phase 2 Realtime test

See `planImplementation.md` Phase 2 Gate Check section for `test_game.mjs` script.

Run with: `SUPABASE_URL=... SUPABASE_ANON_KEY=... ROUND_TIMER_MS=5000 node test_game.mjs`

---

## 🟢 Phase 3: Flutter Frontend (NEXT)

Full code templates in `planImplementation.md` Phase 3. Start with:

```bash
# From repo root
flutter create --platforms web frontend
cd frontend
flutter pub add flutter_bloc fpdart go_router supabase_flutter flutter_animate percent_indicator confetti logger equatable url_launcher shadcn_flutter http
mkdir -p lib/{config,core,services,data/{models,repositories},domain/{entities,usecases},presentation/{cubits/{room_cubit,quiz_cubit,game_cubit},pages,widgets}}
```

Key files to create (full code in `planImplementation.md`):

| File | Description |
|---|---|
| `lib/services/supabase_service.dart` | Realtime channel subscription, stream of `RealtimeEvent` |
| `lib/services/api_service.dart` | HTTP calls to Node.js REST endpoints |
| `lib/core/failures.dart` + `typedefs.dart` | Error handling with fpdart `Either` |
| `lib/data/models/question_model.dart` | `ClientQuestion.fromJson()` |
| `lib/data/models/player_model.dart` | `PlayerModel.fromJson()` |
| `lib/presentation/cubits/room_cubit/` | Room lobby state + `joinRoom`, `startGame` |
| `lib/presentation/cubits/quiz_cubit/` | In-game state: question, timer, answers, reveal |
| `lib/presentation/cubits/game_cubit/` | `createRoom` REST call |
| `lib/config/router.dart` | `go_router` routes: `/`, `/create`, `/room/:code`, `/room/:code/game`, etc. |
| `lib/main.dart` | App entry, Supabase init, BlocProviders |
| Screens × 6 | home, create_room, room_lobby, gameplay, round_reveal, results |
| Widgets × 3 | `TimerBar`, `AnswerButton`, `PlayerChip` |

**Critical:** Pass `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `API_URL` via `--dart-define` when running/building:
```bash
flutter run -d chrome \
  --dart-define=SUPABASE_URL=https://xxx.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=eyJ... \
  --dart-define=API_URL=http://localhost:3000
```

---

## 📦 Actual Package Versions Installed

```json
"dependencies": {
  "@supabase/supabase-js": "^2.98.0",
  "cors": "^2.8.6",
  "dotenv": "^16.6.1",
  "express": "^4.22.1",
  "express-rate-limit": "^7.5.1",
  "helmet": "^7.2.0",
  "nanoid": "^5.1.6",
  "pino": "^8.21.0",
  "pino-pretty": "^10.3.1",
  "uuid": "^9.0.1",
  "zod": "^3.25.76"
},
"devDependencies": {
  "@types/cors": "^2.8.19",
  "@types/express": "^4.17.x",
  "@types/node": "^25.3.3",
  "@types/uuid": "^9.0.8",
  "tsx": "^4.21.0",
  "typescript": "^5.9.3"
}
```

---

## 🛑 Hard Rules (Do NOT)

- Do not modify `data-set/` — source of truth
- Do not use Socket.io — real-time = Supabase Realtime Broadcast only
- Do not use MongoDB/Mongoose — DB = Supabase PostgreSQL only
- Do not start server without `.env` — crashes on Supabase client init
- Do not put `SUPABASE_SERVICE_KEY` in Flutter build (`--dart-define`) — server only
- Do not send `correct_answer_index` in `question:new` broadcast — security critical
