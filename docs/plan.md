# 🎮 NMT Quiz — Multiplayer App Plan

> Refined app plan based on the full project context established in our chat.  
> Use this document to vibe-code the backend and frontend step by step.

---

## 🧠 Context

Ukrainian students (16 yo) need to pass the **NMT (НМТ)** national exam. This app makes studying fun by turning it into a real-time multiplayer quiz game — like **QuizUp** but for Ukrainian exam prep.

## 🌐 Language Rules

| Layer | Language |
|---|---|
| All UI text, labels, buttons, messages | 🇺🇦 **Ukrainian** |
| Code (variables, functions, classes, comments) | 🇬🇧 **English** |
| Server logs (BE) | 🇬🇧 **English** |
| Flutter logs (FE) | 🇬🇧 **English** |

> Logs must be structured so they can be copy-pasted directly to an AI for debugging. See [Logging Strategy](#-logging-strategy) below.

**Dataset is already done.** See [`data-set/README.md`](./data-set/README.md).

---

## 📦 Available Subjects (from `data-set/questions/`)

| Subject key | Display name | Questions |
|---|---|---|
| `ukrainian_language` | Українська мова та література | 1,923 |
| `history` | Історія України | 1,138 |
| `geography` | Географія | 476 |
| `math` | Математика | 58 (demo only) |

> Language and Literature cannot be separated — the source dataset does not distinguish them.

---

## 🏗️ Tech Stack (Decided)

### Backend
- **Node.js + Express + TypeScript** — thin REST API + server-authoritative game engine (timers, scoring, answer validation)
- **Supabase PostgreSQL** (free tier) — `questions` and `rooms`/`players` tables; Node.js uses service-role key (full access); Flutter uses anon key (never sees `correct_answer_index`)
- **Supabase Realtime** (Broadcast) — server→client real-time event bus; Node.js broadcasts via REST API with service-role key; Flutter clients subscribe directly to channels
- **Clean Architecture** — `domain / data / presentation` layers split by feature
- Copy `data-set/types.ts` into backend as the canonical type source

> **Why keep Node.js?** Supabase Realtime has no server-side logic — it's a dumb pub/sub bus. The 5-minute round timer, answer validation, scoring, and `correct_answer_index` security all require a real server process.

### Frontend
- **Flutter Web** — cross-platform, runs in browser
- **flutter_bloc** (Cubits) — state management
- **fpdart** — functional error handling
- **go_router** — web-aware navigation (handles browser back/forward, deep links like `/room/A9X`)
- **flutter_animate** + **shadcn_flutter** — vibrant game aesthetic, bouncy animations

---

## 📦 Confirmed Package Versions

> These are locked decisions — use these exact packages when implementing.

### Backend (`backend/package.json`)

| Package | Version | Purpose |
|---|---|---|
| `express` | `^4.18` | HTTP server |
| `@supabase/supabase-js` | `^2.0` | Supabase client (DB queries + Realtime broadcast) |
| `nanoid` | `^5.0` | 3-char room code generation |
| `zod` | `^3.22` | Request payload validation |
| `pino` | `^8.17` | Structured JSON logger |
| `pino-pretty` | `^10.3` | Dev-friendly log formatting |
| `express-rate-limit` | `^7.1` | Rate-limit room creation |
| `cors` | `^2.8` | CORS middleware |
| `helmet` | `^7.1` | Security headers |
| `dotenv` | `^16.3` | Environment variables |
| `uuid` | `^9.0` | Generate UUIDs for player IDs |
| `tsx` (dev) | `^4.6` | Run TypeScript directly (replaces ts-node) |
| `typescript` (dev) | `^5.3` | TypeScript compiler |
| `@types/uuid` (dev) | `^9.0` | TypeScript types for uuid |

> Use `tsx` for all scripts and dev server — it's faster than `ts-node`.
>
> **No Socket.io, no Mongoose.** Real-time transport = Supabase Realtime. Database = Supabase PostgreSQL via `@supabase/supabase-js`.

### Frontend (`frontend/pubspec.yaml`)

| Package | Version | Purpose |
|---|---|---|
| `supabase_flutter` | `^2.0` | Supabase client: Realtime subscriptions + anon DB queries |
| `flutter_bloc` | `^8.1` | Cubit-based state management |
| `fpdart` | `^1.1` | `Either<Failure, T>` error handling |
| `go_router` | `^13.0` | Web-aware navigation + deep links |
| `flutter_animate` | `^4.3` | Bouncy answer/score animations |
| `shadcn_flutter` | `^0.1` | Dark-mode UI component kit |
| `percent_indicator` | `^4.2` | Timer bar (green→orange→red) |
| `confetti` | `^0.7` | Win celebration animation |
| `logger` | `^2.0` | Structured logs with tag prefix |
| `equatable` | `^2.0` | Value equality for Cubit states |
| `url_launcher` | `^6.2` | Share link button |
| `http` | `^1.2` | HTTP client for REST calls to Node.js backend |

> **No `socket_io_client`.** Real-time events received via `supabase_flutter` Broadcast channel subscriptions. Mutations (join/start/answer) sent via `http` REST calls to Node.js.

---

## 🗂️ Project Folder Structure

```
nmt-zno-exams-multiplayer/
├── data-set/               ← DONE. Source of truth for types + questions
│   ├── types.ts            ← Copy this into backend/src/domain/types.ts
│   └── questions/all.json  ← Seed source (3,595 docs)
├── backend/                ← Node.js server (Phase 1–2)
│   └── src/
│       ├── domain/         ← Entities, repository interfaces, types
│       ├── data/           ← Supabase query helpers (no Mongoose)
│       ├── services/       ← GameEngine, RoomService, CodeGenerator, NameGenerator
│       ├── presentation/   ← Express routes, REST controllers, Zod validators
│       ├── config/         ← supabase.ts (client + broadcastToRoom), logger.ts
│       └── scripts/seed.ts ← One-time DB seeding via Supabase upsert
└── frontend/               ← Flutter Web app (Phase 3)
    └── lib/
        ├── config/         ← router.dart, logger.dart
        ├── core/           ← failures.dart, typedefs.dart
        ├── services/       ← supabase_service.dart (Realtime), api_service.dart (REST)
        ├── data/           ← models/, repositories/
        ├── domain/         ← entities/, usecases/
        └── presentation/   ← cubits/, pages/, widgets/
```

---

## 🗺️ User Flows

### 1. Home Screen
- Two buttons: **"Create Room"** and **"Join Room"**
- No login required (auth added later)

### 2. Create Room Flow
1. Player selects a **subject** from the available list
2. Player selects **number of players** (1–4)
3. Server generates a **3-digit alphanumeric room code** (e.g. `A9X`) + a shareable URL (`/room/A9X`)
4. Creator sees a **waiting lobby** with the room code and a "Share Link" button
5. A randomly generated **funny name** + **color** is assigned to the creator
6. Room stays open until all expected players join OR creator starts the game manually

### 3. Join Room Flow
- Player visits the home screen, taps "Join Room", enters 3-digit code  
- OR opens the shared URL directly → auto-joins the room
- Sends a persistent `sessionId` to prevent duplicate slots if opening multiple tabs wrapper
- Gets assigned a random funny name + color
- Lands in the **waiting lobby**

### 4. Gameplay Loop (per round)
1. Server draws **10 random questions** from MongoDB for the chosen subject
2. Server broadcasts `question:new` to all players (WITHOUT `correct_answer_index`)
3. Each player sees the question + 4–5 answer buttons
4. **Timer: 5 minutes** per question — intentionally long so players can discuss IRL, debate the answer together, make it social and educational. This is the core social mechanic.
5. Player taps an answer → their button locks in, others remain visible
6. Either:
   - All players answered → immediately proceed to reveal
   - Timer runs out → unanswered players get `null`
7. Server emits `round:reveal` with `correct_answer_index` + all player answers
8. Every player sees: correct answer highlighted, what each player picked, score delta
   - UI text in Ukrainian (e.g. "Правильна відповідь!", "Ви помилилися")
9. After a short delay (3s), next question begins automatically
10. After 10 questions → **Results screen**

### 5. Results Screen
- Scoreboard with all players ranked
- Creator sees: **"Play Again Together"** or **"New Game"** button
  - Both require choosing a subject → new 10-question pool → game restarts
- Non-creator sees: **"Join a Game"** button → back to join screen with code input

---

## ⚡ Real-time Events

> **Two transports:**
> - **Client → Server** mutations: HTTP POST to Node.js REST API
> - **Server → Client** broadcasts: Supabase Realtime Broadcast on channel `room:{CODE}`
>
> Flutter subscribes to `supabase.channel('room:A9X')` for all incoming events.
> Node.js broadcasts via `POST /realtime/v1/api/broadcast` with service-role key.

| Event / Endpoint | Direction | Transport | Payload |
|---|---|---|---|
| `POST /api/rooms/:code/join` | client → server | REST | `{ sessionId }` body → returns `{ playerId, name, color, isCreator }` |
| `room:state` | server → all in room | Supabase Broadcast | `{ code, subject, status, maxPlayers, players }` |
| `POST /api/rooms/:code/start` | client → server | REST | `{ playerId }` — creator triggers game start |
| `POST /api/rooms/:code/heartbeat` | client → server | REST | `{ playerId }` — keeps player active |
| `POST /api/rooms/:code/restart` | client → server | REST | `{ playerId }` — creator restarts game |
| `game:start` | server → all | Supabase Broadcast | `{ totalQuestions: 10 }` — game has begun |
| `question:new` | server → all | Supabase Broadcast | `ClientQuestion` (no `correct_answer_index`) |
| `POST /api/rooms/:code/answer` | client → server | REST | `{ playerId, questionId, answerIndex }` |
| `round:update` | server → all | Supabase Broadcast | `{ playerAnswers }` — partial results as players answer |
| `round:reveal` | server → all | Supabase Broadcast | `{ correctIndex, playerAnswers, scores }` |
| `game:end` | server → all | Supabase Broadcast | `{ scoreboard }` |
| `player:disconnected` | server → all | Supabase Broadcast | `{ playerId }` |

---

## 🪄 Edge Cases to Handle

| Scenario | Handling |
|---|---|
| Player disconnects mid-game | PlayerManager sweeps them after 60s of missed heartbeats. Mark as `null` answer for that round, game continues for remaining players. |
| Only 1 player left | Game continues as solo mode |
| Creator disconnects | `PlayerManager` automatically reassigns creator role to the oldest remaining player. |
| Player tries to join full room (4/4) | Reject with error message |
| Player opens same link twice | Backend checks `sessionId`; reconnects to existing identity instead of making a duplicate slot. |
| Room code collision | Regenerate on collision (rare with alphanumeric 3-char codes = 46,656 combos) |
| Player joins after game started | Reject — rooms are locked once game starts |
| All players disconnect | `PlayerManager` cleans up room from DB and RAM after the last player is removed. |

---

## 🔒 Security Rules

1. **Never send `correct_answer_index` in `question:new`** — always strip server-side
2. Only emit `correct_answer_index` via `round:reveal` after timer expires
3. Validate all socket payloads server-side (zod schemas recommended)
4. Rate-limit room creation per IP to prevent abuse

---

## 🗄️ Supabase PostgreSQL Tables

> Create these via Supabase MCP or the Supabase SQL editor before running the seed script.

### `questions`
```sql
CREATE TABLE questions (
  id                   TEXT PRIMARY KEY,   -- e.g. "osy_history_42"
  subject              TEXT NOT NULL,
  text                 TEXT NOT NULL,
  choices              TEXT[] NOT NULL,
  correct_answer_index INTEGER NOT NULL,
  exam_type            TEXT
);

CREATE INDEX idx_questions_subject ON questions (subject);
```
**Seed:** `data-set/questions/all.json` (3,595 rows) via `npm run seed`

> **Security:** `correct_answer_index` is never queried by client-facing code. Node.js uses the **service-role key** (bypasses RLS, full access) and manually strips the field before broadcasting `question:new`. Flutter uses the **anon key** and never queries this table directly.

### `rooms`
```sql
CREATE TABLE rooms (
  code                    TEXT PRIMARY KEY,  -- e.g. "A9X"
  subject                 TEXT NOT NULL,
  status                  TEXT NOT NULL DEFAULT 'waiting'
                            CHECK (status IN ('waiting', 'playing', 'finished')),
  max_players             INTEGER NOT NULL,
  question_ids            TEXT[] DEFAULT '{}',
  current_question_index  INTEGER DEFAULT 0,
  round_started_at        TIMESTAMPTZ,
  created_at              TIMESTAMPTZ DEFAULT now()
);

-- Auto-delete rooms older than 1 hour (handled in Node.js GameEngine cleanup)
```

### `players`
```sql
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

> Note: `players` table starts **empty** when room is created via `POST /api/rooms`. Players are added when they call `POST /api/rooms/:code/join`.

---

## 🪜 Build Steps (in order)

### Phase 0: Supabase Project Setup (do this first, before writing any code)
- [ ] Create Supabase project at [supabase.com](https://supabase.com) (free tier)
- [ ] Run SQL from the "Supabase PostgreSQL Tables" section above (via MCP or SQL editor)
- [ ] Copy `SUPABASE_URL`, `SUPABASE_SERVICE_KEY`, `SUPABASE_ANON_KEY` to `backend/.env`

### Phase 1: Backend Foundation
- [ ] Init Node.js + Express + TypeScript project
- [ ] Connect to Supabase via `@supabase/supabase-js` (service-role key)
- [ ] Seed database from `data-set/questions/all.json` via Supabase upsert
- [ ] REST endpoint: `GET /api/subjects` — returns subject list + question counts
- [ ] REST endpoint: `POST /api/rooms` — creates room, returns code
- [ ] REST endpoint: `GET /api/rooms/:code` — returns room state

### Phase 2: Real-time Game Engine
- [ ] Implement `POST /api/rooms/:code/join` — add player, broadcast `room:state` via Supabase, return player identity
- [ ] Implement `POST /api/rooms/:code/start` — sample 10 questions, lock room, broadcast `game:start` + first `question:new`
- [ ] Implement question timer (5 min server-side, authoritative — `setTimeout` in Node.js)
- [ ] Implement `POST /api/rooms/:code/answer` — record answer, broadcast `round:update`; when all answered → `round:reveal`
- [ ] Implement `game:end` with scoreboard broadcast
- [ ] Handle disconnection edge cases (on process restart, rooms clean up)

### Phase 3: Flutter Frontend
- [ ] Init Flutter Web project (`flutter create --platforms web frontend`)
- [ ] Add all packages from Confirmed Package Versions table
- [ ] `SupabaseService` — initializes `supabase_flutter`, subscribes to room Broadcast channel
- [ ] `ApiService` — HTTP calls to Node.js REST endpoints (join, start, answer)
- [ ] `RoomCubit` — lobby state (waiting/ready/gameStarted)
- [ ] `QuizCubit` — in-game state (question, timer countdown, answers, reveal)
- [ ] `GameCubit` — overall flow (create/join/results)
- [ ] go_router setup: `/`, `/create`, `/room/:code`, `/room/:code/game`, `/room/:code/reveal`, `/room/:code/results`
- [ ] Home screen — "Створити кімнату" / "Приєднатися" buttons
- [ ] Create room screen — subject picker + player count selector
- [ ] Room lobby screen — large room code, share link, player list, "Почати гру"
- [ ] Gameplay screen — TimerBar + question card + answer buttons + player status chips
- [ ] Round reveal screen — correct answer green, wrong red, score delta pop, 3s auto-advance
- [ ] Results / scoreboard screen — ranked list + confetti for 1st place

### Phase 4: Polish + Deploy
- [ ] Funny Ukrainian name list (50+ entries, adjective + animal, server-side)
- [ ] 8-color curated player palette: `['#FF6B6B','#4ECDC4','#45B7D1','#96CEB4','#FFEAA7','#DDA0DD','#98D8C8','#F7DC6F']`
- [ ] `flutter_animate` — bouncy answer button tap, score pop, reveal slide-in
- [ ] `percent_indicator` — timer bar color urgency (green → orange → red)
- [ ] `confetti` — win screen celebration
- [ ] Responsive layout: vertical stack on mobile (<600px), 70/30 split on desktop
- [ ] Deploy backend → Render (set env vars: `SUPABASE_URL`, `SUPABASE_SERVICE_KEY`, `PORT`, `CORS_ORIGIN`)
- [ ] Deploy frontend → Firebase Hosting (`flutter build web --release --dart-define=API_URL=... --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=... && firebase deploy`)

> See [`planImplementation.md`](./planImplementation.md) for step-by-step commands, file templates, and exact code patterns.

---

## 📋 Logging Strategy

> Logs must be English, structured, and copy-pasteable to an AI to diagnose issues.

### Backend (Node.js) — Log Format

Use a logger like **`pino`** or **`winston`** with JSON output + a human-readable dev mode.

Every log line must include: `timestamp`, `level`, `context` (feature area), and a `message`.

```
[2024-03-01T02:30:00Z] INFO  [RoomService]   Room created | code=A9X subject=history players=1/4
[2024-03-01T02:30:05Z] INFO  [SocketHandler] Player joined | roomCode=A9X playerId=abc123 name="Веселий Кит"
[2024-03-01T02:30:10Z] INFO  [GameEngine]    Game started  | roomCode=A9X questions=10
[2024-03-01T02:30:15Z] INFO  [GameEngine]    Round started | roomCode=A9X questionIndex=0 questionId=osy_history_42
[2024-03-01T02:31:00Z] INFO  [GameEngine]    Answer recv   | roomCode=A9X playerId=abc123 answerIndex=2 timeTakenMs=45000
[2024-03-01T02:32:00Z] WARN  [GameEngine]    Timer expired | roomCode=A9X questionIndex=0 unanswered=["xyz456"]
[2024-03-01T02:32:01Z] INFO  [GameEngine]    Round reveal  | roomCode=A9X correctIndex=0 scores={abc123:10,xyz456:0}
[2024-03-01T02:35:00Z] INFO  [GameEngine]    Game ended    | roomCode=A9X scoreboard=[{name:"Веселий Кит",score:80}]
[2024-03-01T02:35:01Z] WARN  [RoomService]   Player disc.  | roomCode=A9X playerId=xyz456
[2024-03-01T02:35:01Z] ERROR [SocketHandler] Unhandled ev   | event=unknown_event payload={...} err=EventNotFound
```

### Frontend (Flutter) — Log Format

Use the **`logger`** package with a consistent tag prefix per feature.

```
[QuizBloc]     question:new received  | questionId=osy_history_42 choicesCount=4 timerMs=300000
[QuizBloc]     answer submitted       | questionId=osy_history_42 selectedIndex=2
[QuizBloc]     round:reveal received  | correctIndex=0 myAnswer=2 isCorrect=false scoreGained=0
[RoomCubit]    room:state updated     | status=playing players=2 currentQ=1/10
[RoomCubit]    player disconnected    | playerId=xyz456
[SocketService] connected             | url=wss://api.example.com
[SocketService] reconnecting...       | attempt=2
[SocketService] ERROR emit failed     | event=player:answer err=SocketException: connection lost
```

**Rules:**
- Always log `ERROR` with the full error message + relevant context
- Never log `correct_answer_index` on the client (it should never be there)
- Log every Socket.io event received and emitted on both sides

---

## 🚀 Deployment Targets (Free Tier)

| Service | What |
|---|---|
| **Render** (or Railway) | Node.js backend — free tier sleeps after 15min, Socket.io reconnection handles wake-up |
| **Supabase** | PostgreSQL + Realtime — free tier: 500MB DB, 200 concurrent connections, 100 msg/sec |
| **Firebase Hosting** | Flutter Web frontend (CDN, fast) |

> **Cold start note:** Render free tier sleeps after 15 min of inactivity. On wake (~30s), Supabase Realtime channels auto-reconnect on the Flutter side — no user action needed.

---

## 🤖 Supabase MCP Server (for AI agents)

The [Supabase MCP server](https://github.com/supabase-community/supabase-mcp) lets Claude Code manage your Supabase project directly — run SQL migrations, inspect table schemas, query data — without leaving the terminal or switching to the Supabase dashboard.

### Setup (one-time, per project)

Add to your `.claude/mcp_servers.json` (or via `claude mcp add`):

```json
{
  "supabase": {
    "command": "npx",
    "args": ["-y", "@supabase/mcp-server-supabase@latest", "--project-ref", "YOUR_PROJECT_REF"],
    "env": {
      "SUPABASE_ACCESS_TOKEN": "your-supabase-personal-access-token"
    }
  }
}
```

Get your project ref from: `https://supabase.com/dashboard/project/[ref]`
Get your personal access token from: `https://supabase.com/dashboard/account/tokens`

### What AI agents can do with MCP
- Create and alter tables (run the schema SQL from "Supabase PostgreSQL Tables" above)
- Check row counts (`SELECT COUNT(*) FROM questions WHERE subject = 'history'`)
- Debug data issues without writing a script
- Inspect indexes, constraints, and RLS policies
- Run the seed verification after `npm run seed`

---

## 🎨 UI/UX Vibe

- **Dark mode first**, vibrant accent colors (think neon on dark)
- **Bouncy animations** on answer selection and reveal (like QuizUp)
- **Timer bar** that changes from green → yellow → red as time runs out
- **Player avatars** = colored circles with their funny name initials
- NMT-themed but **not boring** — it should feel like a game, not a study tool
