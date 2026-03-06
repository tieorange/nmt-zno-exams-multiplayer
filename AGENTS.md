# 🤖 AI Agent Instructions

Welcome! This file is your complete quick-reference for the **NMT Quiz Multiplayer** project — a real-time competitive trivia game for Ukrainian high school students preparing for the NMT (НМТ) exam.

> For deep architecture details see [`docs/plan.md`](docs/plan.md).
> For setup, running, and debugging see [`docs/planImplementation.md`](docs/planImplementation.md).

---

## 🏗️ Project Overview

- **What it is**: QuizUp-style multiplayer quiz, 2–4 players, real-time, dark-mode web app.
- **Stack**: Node.js (Express + TypeScript) backend, Flutter Web frontend, Supabase (Postgres + Realtime).
- **Core invariant**: The backend is the sole game authority — timers, scoring, answer validation, `correct_answer_index` security all live on the server.
- **Language policy**:
  - UI labels, buttons, messages → 🇺🇦 **Ukrainian**
  - Code, comments, logs → 🇬🇧 **English**

---

## 📂 Repository Structure

```
nmt-zno-exams-multiplayer/
├── backend/                  # Node.js Express game server (port 3000)
│   ├── src/
│   │   ├── config/           # logger.ts, supabase.ts (broadcastToRoom)
│   │   ├── data/repositories/# QuestionRepository.ts, RoomRepository.ts
│   │   ├── domain/types.ts   # TypeScript interfaces (Question, Room, Player)
│   │   ├── middleware/       # requestId.ts, requestLogger.ts
│   │   ├── presentation/
│   │   │   ├── controllers/  # GameController, RoomController, SubjectController
│   │   │   ├── routes/       # index.ts — all 10 routes registered here
│   │   │   └── validators/   # requestSchemas.ts — Zod schemas
│   │   ├── services/
│   │   │   ├── GameEngine.ts # Core: timers, scoring, roundState, reveals
│   │   │   ├── PlayerManager.ts # Heartbeat, disconnect, creator reassignment
│   │   │   ├── CodeGenerator.ts # nanoid 3-char room codes
│   │   │   └── NameGenerator.ts # Ukrainian animal-adjective player names
│   │   ├── utils/serializeError.ts
│   │   └── main.ts           # Express entry point
│   ├── .env.example
│   ├── package.json
│   └── tsconfig.json
├── frontend/                 # Flutter Web app
│   ├── lib/
│   │   ├── main.dart         # Boot: Supabase init, cubit wiring, stream coordinator
│   │   ├── config/router.dart# go_router: 6 routes
│   │   ├── core/             # app_logger.dart, failures.dart, typedefs.dart
│   │   ├── data/models/      # PlayerModel, ClientQuestion (no correct_answer_index)
│   │   ├── services/
│   │   │   ├── api_service.dart    # REST client (10 endpoints + _traced() wrapper)
│   │   │   └── supabase_service.dart # Realtime subscriptions → events Stream
│   │   └── presentation/
│   │       ├── cubits/       # room_cubit/, quiz_cubit/, game_cubit/
│   │       ├── pages/        # 6 screens (home → results)
│   │       └── widgets/      # answer_button, timer_bar, player_chip
│   └── pubspec.yaml
├── data-set/                 # READ-ONLY source of truth
│   ├── types.ts              # Canonical TypeScript types (copy to backend, never modify)
│   └── questions/all.json    # 3,595 questions ready to seed
├── supabase/
│   ├── config.toml           # Local Docker config
│   └── migrations/           # 3 SQL migration files
├── docs/
│   ├── plan.md               # Architecture reference (what is built)
│   └── planImplementation.md # Developer ops guide (setup, run, debug)
├── AGENTS.md                 # This file
├── CLAUDE.md                 # Identical to AGENTS.md
└── Makefile                  # All dev commands
```

---

## 🛠️ Commands (via Makefile)

| Command | Description |
|---|---|
| `make install` | Install npm deps (backend) + `flutter pub get` (frontend) |
| `make supabase-start` | Start local Supabase Docker containers |
| `make supabase-stop` | Stop local Supabase |
| `make supabase-push` | Apply `/supabase/migrations/` to local DB |
| `make seed` | Seed 3,595 questions from `data-set/questions/all.json` |
| `make all` | Start Supabase + backend + frontend together (concurrently) |
| `make backend` | Run backend in dev mode (port 3000, tsx watch) |
| `make frontend` | Run Flutter Web (Chrome, port 5000) |
| `make iphone` | Run frontend for LAN + mobile: Chrome (5000) + web-server (8080), prints QR |
| `make lint` | `tsc --noEmit` (backend) + `flutter analyze` (frontend) — must pass before commit |

---

## 🔌 MCP Server Support

### 1. `local-db` (Local Postgres)
- **Connection**: `postgresql://postgres:postgres@localhost:54322/postgres`
- **Use for**: Schema inspection, data verification, local debugging.

### 2. `supabase` (Cloud)
- **Use for**: Migrations, RLS policies, remote project management.
- **Requires**: `SUPABASE_ACCESS_TOKEN` env var.
- **Setup**: `claude mcp add supabase -- npx -y @supabase/mcp-server-supabase@latest --project-ref REF`

---

## 🌐 Backend API Reference

All endpoints are prefixed `/api`. `:code` = 3-char uppercase alphanumeric (e.g. `A9X`).

### REST Endpoints

| Method | Path | Body | Returns | Notes |
|--------|------|------|---------|-------|
| `GET` | `/api/subjects` | — | `{ subjects: [{key, displayName, questionCount, enabled}] }` | Live counts from DB |
| `POST` | `/api/rooms` | `{ subject, maxPlayers: 1–4 }` | `{ code }` | Rate-limited: 10/15min/IP |
| `GET` | `/api/rooms/:code` | — | Room + players + `currentQuestion?` | Includes question if playing |
| `POST` | `/api/rooms/:code/join` | `{ sessionId? }` | `{ playerId, name, color, isCreator, status }` | sessionId enables rejoin |
| `POST` | `/api/rooms/:code/start` | `{ playerId }` | `{ ok: true }` | Creator only |
| `POST` | `/api/rooms/:code/answer` | `{ playerId, questionId, answerIndex: 0–4 }` | `{ ok: true }` | One answer per round |
| `POST` | `/api/rooms/:code/heartbeat` | `{ playerId }` | `{ ok: true }` | Silent; call every 30s |
| `POST` | `/api/rooms/:code/restart` | `{ playerId }` | `{ ok: true }` | Creator only; status=`finished` |
| `POST` | `/api/rooms/:code/next-question` | `{ playerId }` | `{ ok: true }` | Creator only; advances round |
| `GET` | `/api/rooms/:code/round-state` | — | `{ playerAnswers, pendingReveal }` | Polling fallback |

### Supabase Broadcast Events (channel `room:{CODE}`, server → client)

| Event | Payload | When |
|-------|---------|------|
| `game:start` | `{ totalQuestions, timerMs }` | Game begins (round 0) |
| `question:new` | `{ id, subject, text, choices, questionIndex?, totalQuestions?, roundStartedAt?, timerMs? }` | New round starts; **no `correct_answer_index`** |
| `round:update` | `{ playerAnswers: { playerId: index\|null } }` | A player submits an answer |
| `round:reveal` | `{ correctIndex, playerAnswers, scores, scoreDeltas }` | Round timer expires or all answered |
| `game:end` | `{ scoreboard: [{ rank, id, name, color, score }] }` | All 5 questions done |
| `room:state` | `{ code, subject, status, maxPlayers, currentQuestionIndex, players: [...] }` | Player joins/leaves/reconnects |
| `player:disconnected` | `{ playerId }` | Player offline >60s |

---

## 🗄️ Database Schema

```sql
-- questions (seeded from data-set, READ-ONLY at runtime)
questions (id TEXT PK, subject TEXT, text TEXT, choices TEXT[], correct_answer_index INT, exam_type TEXT)

-- rooms
rooms (code TEXT PK, subject TEXT, status TEXT CHECK ('waiting'|'playing'|'finished'),
       max_players INT, question_ids TEXT[], current_question_index INT,
       round_started_at TIMESTAMPTZ, created_at TIMESTAMPTZ)

-- players
players (id UUID PK, room_code TEXT FK→rooms, name TEXT, color TEXT,
         score INT DEFAULT 0, is_creator BOOL, joined_at TIMESTAMPTZ)

-- round_answers (persisted after each reveal)
round_answers (id UUID PK, room_code TEXT FK→rooms, round_number INT,
               player_id UUID FK→players, question_id TEXT,
               answer_index INT, is_correct BOOL, created_at TIMESTAMPTZ)

-- RPC (called by GameEngine for atomic score update)
increment_player_score(player_id UUID, delta INT, r_code TEXT)
```

Migrations live in `/supabase/migrations/`. Apply with `make supabase-push`.

---

## 🧠 Backend In-Memory State (GameEngine.ts + PlayerManager.ts)

These Maps/Sets are **not persisted** — they live in the Node.js process only.

| Name | Type | Purpose |
|------|------|---------|
| `roundState` | `Map<code, RoundState>` | Active round: answers, timer, questions, questionIndex, roundStartedAt |
| `pendingNextRound` | `Map<code, PendingNextRound>` | Between reveal and "next question": nextIndex, questions, fallbackTimer |
| `pendingRevealCache` | `Map<code, RevealCache>` | Cached reveal payload for polling fallback |
| `cleanupTimeouts` | `Map<code, timeout>` | Room cleanup handle (fires 1h after game ends) |
| `startingMutex` | `Set<code>` | Prevents concurrent `startGame`/`restartGame` calls |
| `sessions` (PlayerManager) | `Map<sessionId, session>` | Duplicate-tab detection |
| `pings` (PlayerManager) | `Map<playerId, session>` | Heartbeat liveness (60s timeout, 30s check interval) |

---

## ⚛️ Frontend Architecture (Flutter)

### Three Cubits
- **`GameCubit`** — subject list loading + room creation flow
- **`RoomCubit`** — lobby state: join, players list, heartbeat (30s), rejoin recovery
- **`QuizCubit`** — in-game: question display, answer submit, round reveal, game end, 1s polling fallback

### Critical Wiring in `main.dart`

The coordinator runs on every `RoomCubit` state change. Exact code:

```dart
roomCubit.stream.listen((_) {
  // Forward identity to QuizCubit before any game events can arrive
  if (roomCubit.myPlayerId != null && roomCubit.state.code.isNotEmpty) {
    quizCubit.setContext(roomCubit.myPlayerId!, roomCubit.state.code);
  }
  // Consume snapshot — null after first read (prevents re-bootstrap on next tick)
  final snapshot = roomCubit.consumePendingSnapshot();
  // Only bootstrap if QuizCubit isn't already showing an active question/reveal
  final canBootstrap = quizCubit.state is! QuizQuestion && quizCubit.state is! QuizReveal;
  if (snapshot != null && canBootstrap) {
    quizCubit.bootstrapFromSnapshot(snapshot);
  }
});
```

Key facts:
- `roomCubit.myPlayerId` and `roomCubit.state.code` are set by `joinRoom()`.
- `consumePendingSnapshot()` nulls `_pendingSnapshot` after reading — safe to call every tick.
- `_pendingSnapshot` is set in two places: join response (rejoin path) and `_prefetchCurrentQuestionSnapshot()` (game start path).

### Polling Fallback
- `QuizCubit.startPolling()` runs every 1s — catches missed Realtime events
- `RoomLobbyScreen` polls `syncRoomState()` every 1s while `status == waiting`
- `GET /api/rooms/:code/round-state` returns cached reveal data if Realtime was missed

### Security Tripwire
`SupabaseService` logs a `security.violation` event if `correct_answer_index` appears in any `question:new` payload.

---

## 🔴 API Error Responses

All error bodies have shape `{ "error": string }`. Validation errors return Zod's flatten output.

| Endpoint | Status | Error body | Condition |
|----------|--------|-----------|-----------|
| Any | `400` | `{ "error": { "fieldErrors": {...} } }` | Zod validation failure |
| `POST /rooms` | `500` | room create DB error | Supabase write failed |
| `GET /rooms/:code` | `404` | `{ "error": "Room not found" }` | Unknown code |
| `POST /rooms/:code/join` | `404` | `{ "error": "Кімнату не знайдено" }` | Unknown code |
| `POST /rooms/:code/join` | `400` | `{ "error": "Гра вже почалась" }` | Status ≠ waiting AND no rejoin match |
| `POST /rooms/:code/join` | `400` | `{ "error": "Кімната повна" }` | `players.length >= max_players` |
| `POST /rooms/:code/start` | `404` | `{ "error": "Кімнату не знайдено" }` | Unknown code |
| `POST /rooms/:code/start` | `400` | `{ "error": "Гра вже почалась" }` | Status ≠ waiting |
| `POST /rooms/:code/start` | `403` | `{ "error": "Тільки творець може почати гру" }` | `is_creator = false` |
| `POST /rooms/:code/answer` | `403` | `{ "error": "Player does not belong to this room" }` | playerId not in room |
| `POST /rooms/:code/answer` | `400` | `{ "error": "Гру не знайдено або раунд ще не почався" }` | No active round |
| `POST /rooms/:code/answer` | `400` | `{ "error": "Ви вже відповіли на це запитання" }` | Duplicate answer |
| `POST /rooms/:code/answer` | `400` | `{ "error": "Неправильне ID запитання" }` | Wrong questionId |
| `POST /rooms/:code/answer` | `400` | `{ "error": "Невірний індекс відповіді" }` | answerIndex ≥ choices.length |
| `POST /rooms/:code/heartbeat` | `403` | `{ "error": "Player does not belong to this room" }` | Identity spoof |
| `POST /rooms/:code/heartbeat` | `400` | `{ "error": "Invalid room or session for heartbeat" }` | Not in pings Map |
| `POST /rooms/:code/restart` | `404` | `{ "error": "Кімнату не знайдено" }` | Unknown code |
| `POST /rooms/:code/restart` | `400` | `{ "error": "Гру ще не завершено" }` | Status ≠ finished |
| `POST /rooms/:code/restart` | `403` | `{ "error": "Тільки творець може почати нову гру" }` | Not creator |
| `POST /rooms/:code/next-question` | `400` | `{ "error": "Тільки творець може перейти до наступного питання" }` | Not creator |
| `POST /rooms/:code/next-question` | `400` | `{ "error": "Немає очікуваного наступного питання" }` | No pending round |

---

## 📋 Full API Response Shapes

### `GET /api/rooms/:code`

```json
{
  "code": "A9X",
  "subject": "ukrainian_language",
  "status": "playing",
  "maxPlayers": 4,
  "currentQuestionIndex": 2,
  "currentQuestion": {
    "id": "osy_ukrainian_language_42",
    "subject": "ukrainian_language",
    "text": "Яке з поданих слів пишеться з великої букви?",
    "choices": ["слово а", "слово б", "слово в", "слово г"],
    "questionIndex": 2,
    "totalQuestions": 5,
    "roundStartedAt": "2026-03-06T10:00:00.000Z",
    "timerMs": 300000
  },
  "players": [
    { "id": "uuid-v4", "name": "Веселий Кит", "color": "#4ECDC4", "score": 10, "isCreator": true },
    { "id": "uuid-v4", "name": "Сонячна Жаба", "color": "#FF6B6B", "score": 0, "isCreator": false }
  ]
}
```

> `currentQuestion` is `null` when status = `waiting` or `finished`, or between rounds (timer fired but next hasn't started).

### `POST /api/rooms/:code/join`

```json
{
  "playerId": "uuid-v4",
  "name": "Весела Лисиця",
  "color": "#FFE66D",
  "isCreator": false,
  "status": "waiting",
  "currentQuestion": null
}
```

> On **rejoin** (same `sessionId`): `status` may be `playing` and `currentQuestion` will be the active question. The frontend stores this in `RoomCubit._pendingSnapshot` for `QuizCubit.bootstrapFromSnapshot()`.

### `GET /api/rooms/:code/round-state`

```json
{
  "playerAnswers": {
    "uuid-player-1": 2,
    "uuid-player-2": null
  },
  "pendingReveal": {
    "correctIndex": 2,
    "playerAnswers": { "uuid-player-1": 2, "uuid-player-2": null },
    "scores": { "uuid-player-1": 20, "uuid-player-2": 0 },
    "scoreDeltas": { "uuid-player-1": 10, "uuid-player-2": 0 }
  }
}
```

> `playerAnswers` is `null` when no round is active. `pendingReveal` is `null` during an active round — it only appears between reveal and next question.

---

## 🎯 Dart State Type Definitions

### `QuizState` (abstract, in `quiz_state.dart`)

```dart
// State variants — use BlocBuilder<QuizCubit, QuizState>
QuizInitial                          // No game in progress

QuizQuestion {
  question: ClientQuestion           // id, subject, text, choices
  questionIndex: int                 // 1-based for display ("Q 3/5")
  totalQuestions: int                // from game:start (default 5)
  timeRemaining: Duration            // counts down 1s per tick
  totalTime: Duration                // full round duration
  myAnswer: int?                     // null = not answered yet
  playerAnswers: Map<String, int?>   // playerId → answerIndex|null
}

QuizReveal {
  question: ClientQuestion           // same question as QuizQuestion
  correctIndex: int
  playerAnswers: Map<String, int?>
  scores: Map<String, int>           // total scores (post-reveal)
  myAnswer: int?
  myScoreGained: int?                // points won this round (0 or 10)
}

QuizGameEnded {
  scoreboard: List<Map<String,dynamic>>  // [{rank, id, name, color, score}]
}

QuizError {
  message: String
}
```

### `RoomState` (in `room_state.dart`)

```dart
RoomState {
  code: String               // e.g. "A9X"
  subject: String            // e.g. "ukrainian_language"
  status: RoomStatus         // initial | waiting | playing | finished | error
  maxPlayers: int
  players: List<PlayerModel> // [{id, name, color, score, isCreator}]
  errorMessage: String?
  isStartingGame: bool       // true while POST /start is in-flight
}
```

Identity fields live as **public properties on `RoomCubit`** (not in `RoomState`):
```dart
roomCubit.myPlayerId  // String?  — null before join
roomCubit.myName      // String?
roomCubit.myIsCreator // bool
```

### `PlayerModel` (in `data/models/player_model.dart`)

```dart
PlayerModel { id, name, color, score, isCreator }
// Constructed from JSON via PlayerModel.fromJson(map)
// Keys: 'id', 'name', 'color', 'score', 'isCreator'
```

---

## 🎮 Game Constants & Env Overrides

| Constant | Default | Env Override |
|----------|---------|-------------|
| `QUESTION_COUNT` | `5` | — (hardcoded) |
| `ROUND_TIMER_MS` | `300000` (5 min) | `ROUND_TIMER_MS` env var |
| `PENDING_ROUND_TIMEOUT_MS` | `300000` (5 min) | `PENDING_ROUND_TIMEOUT_MS` env var |
| `CORRECT_ANSWER_POINTS` | `10` | — (hardcoded) |
| Disconnect timeout | `60000` ms | — |
| Heartbeat check interval | `30000` ms | — |
| Room cleanup delay | `3600000` ms (1 hr) | — |
| Rate limit | `10 rooms / 15 min / IP` | — |

For fast local testing: set `ROUND_TIMER_MS=10000` and `PENDING_ROUND_TIMEOUT_MS=30000` in `backend/.env`.

---

## 📜 Development Guidelines

1. **Security**: `correct_answer_index` is **never** sent to clients in `question:new`. Only revealed in `round:reveal`. The backend uses the service-role key; Flutter uses the anon key.
2. **Game Logic**: All timers, scoring, and answer validation are server-authoritative (GameEngine.ts).
3. **Logging**:
   - Backend: `pino` — base field `service: 'backend'`, structured objects `{ event, roomCode, playerId, ... }`, never template strings.
   - Frontend: `createAppLogger()` from `core/app_logger.dart` — outputs one JSON line per call.
   - `requestId` (UUID) flows through all HTTP logs; echoed as `x-request-id` response header.
4. **State Management**: Backend = in-memory `roundState` + Supabase DB. Frontend = `flutter_bloc` Cubits.
5. **Real-time transport**: Client→Server = REST POST. Server→Client = Supabase Realtime Broadcast.
6. **TypeScript**: `moduleResolution: "bundler"` in `tsconfig.json` — do NOT change to `nodenext` (breaks pino v8 types).
7. **UI framework**: Material3 dark theme — `shadcn_flutter` is **NOT** installed. Seed color `#4ECDC4`, background `#0D1117`.
8. **go_router**: Version `^17.1.0` — NOT v13. API uses `..onBroadcast(event:, callback:)` cascade for Supabase channels.
9. **Deprecations**: Use `withAlpha(int)` not `withOpacity(double)` — `withOpacity` is deprecated.
10. **Error handling**: Use `fpdart` (`Either<Failure, T>`) for functional error handling in Flutter services.

---

## ⚠️ Key Gotchas (Non-Obvious Facts)

- **Double-reveal prevention**: `roundState.delete(roomCode)` is called at the **start** of `revealRound()`, before any async work. This is the race-condition fix.
- **Supabase broadcast method**: `broadcastToRoom` uses `channel.httpSend()`, not `.send()`. This is the verified working path for local Supabase.
- **QUESTION_COUNT = 5**, not 10. Some old comments say 10 — ignore them.
- **Disconnected players during a game**: Players are NOT removed from the DB when they disconnect during `playing` or `finished` status. They are removed only during `waiting`. This preserves scores for rejoin.
- **Creator reassignment**: When creator disconnects, `PlayerManager` clears all `is_creator` flags then assigns to the oldest **online** player (falls back to oldest overall if all offline).
- **sessionId**: A 16-char random string generated once per app launch in `ApiService`. Sent on join for duplicate-tab/rejoin detection. Optional — join still works without it.
- **Rooms auto-deleted**: `endGame()` schedules a `setTimeout` for 1 hour to delete the room + clean up name cache. No cron job needed.
- **CORS**: In `NODE_ENV=production`, `CORS_ORIGIN` is required — server throws on startup if missing. In dev, all origins are allowed.
- **Room code validation**: All `:code` routes have middleware that validates exactly 3 uppercase alphanumeric chars. Codes are uppercased on access.
- **Broadcast uses `httpSend`**: The Supabase JS client's realtime `channel.send()` doesn't work reliably in local/server contexts; `httpSend()` bypasses the WS connection.

---

## 📓 Structured Log Event Catalog

Use these event names when adding new log statements. **Never invent new names** — grep first.

### Backend (pino, `service: 'backend'`)

| Event name | Level | Where |
|-----------|-------|-------|
| `http.request.start` / `http.request.finish` | info | requestLogger middleware |
| `room.created` | info | RoomController.createRoom |
| `room.get_state` / `room.get_state.not_found` | info/warn | RoomController.getRoomState |
| `room.player_joined` / `room.player_rejoined` | info | RoomController.joinRoom |
| `room.join.rejected` | warn | RoomController.joinRoom |
| `room.validate_player.error` | error | RoomController.validatePlayerInRoom |
| `game.start` / `game.start.failed` | info/warn | GameController.startGame |
| `game.restart` | info | GameController.restartGame |
| `game.next_question` / `game.next_question.failed` | info/warn | GameController.nextQuestion |
| `game.run` | info | GameEngine.runGame |
| `game.round.start` | info | GameEngine.startRound |
| `game.answer.received` / `game.answer.accepted` / `game.answer.rejected` | info/warn | GameEngine / GameController |
| `game.answer.invalid_index` | warn | GameEngine.submitAnswer |
| `game.round.reveal` | info | GameEngine.revealRound |
| `game.round.timer_expired` | warn | GameEngine.revealRound (unanswered players) |
| `game.next_question.creator_advance` | info | GameEngine.nextQuestion |
| `game.end` | info | GameEngine.endGame |
| `game.room.cleanup` | info | GameEngine cleanup timeout |
| `game.broadcast.failed` | error | GameEngine.safeBroadcast |
| `game.questions.insufficient` | warn | GameEngine.runGame |
| `player.disconnected` / `room.creator.reassigned` | info | PlayerManager |

### Frontend (logger package, `service: 'frontend'`)

| Event name | Level | Where |
|-----------|-------|-------|
| `api.request.start` / `api.request.finish` / `api.request.failed` | info/error | ApiService._traced() |
| `realtime.subscribe.start` / `realtime.subscribe.ok` / `realtime.subscribe.error` | info/error | SupabaseService |
| `realtime.broadcast.raw` / `realtime.broadcast.received` / `realtime.event.emitted` | debug/info | SupabaseService |
| `security.violation` | error | SupabaseService (correct_answer_index leaked) |
| `room.joined` / `room.join.failed` / `room.sync` / `room.sync.failed` | info/warn/error | RoomCubit |
| `game.start.attempt` / `game.start.already_started` / `game.start.failed` | info/warn/error | RoomCubit |
| `game.start.received` | info | QuizCubit._handleEvent |
| `question.new.received` / `question.parse.failed` | info/error | QuizCubit._handleNewQuestion |
| `round.reveal.received` | info | QuizCubit._handleReveal |
| `quiz.bootstrap.from_snapshot` / `quiz.bootstrap.failed` | info/error | QuizCubit.bootstrapFromSnapshot |
| `quiz.submit_answer.failed` / `quiz.next_question.failed` | error | QuizCubit |
| `flutter.framework.error` / `platform.unhandled.error` | error | main.dart error hooks |

---

## 🔧 Extending the App

See **[`docs/patterns.md`](docs/patterns.md)** for copy-paste code templates covering:
- Adding a new REST endpoint (controller + route + validator + tests)
- Adding a new Supabase broadcast event (GameEngine + SupabaseService + QuizCubit)
- Adding a new Flutter screen (page + route + BlocBuilder guards)
- Adding a new cubit state variant
- Backend error handling pattern
- Frontend logging pattern (structured object vs string)
- Flutter Either<Failure,T> error handling pattern

---

## 🧪 Before You Commit

```bash
make lint   # tsc --noEmit + flutter analyze — both must pass with 0 issues
```

Happy coding! 🚀
