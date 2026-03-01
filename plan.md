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
- **Node.js + Express + TypeScript** — REST + Socket.io server
- **MongoDB Atlas** (free tier) — document DB, perfect for JSON question storage
- **Clean Architecture** — `domain / data / presentation` layers split by feature
- Copy `data-set/types.ts` into backend as the canonical type source

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
| `socket.io` | `^4.7` | Real-time events |
| `mongoose` | `^8.0` | MongoDB ODM + validation |
| `nanoid` | `^5.0` | 3-char room code generation |
| `zod` | `^3.22` | Socket payload validation |
| `pino` | `^8.17` | Structured JSON logger |
| `pino-pretty` | `^10.3` | Dev-friendly log formatting |
| `express-rate-limit` | `^7.1` | Rate-limit room creation |
| `cors` | `^2.8` | CORS middleware |
| `helmet` | `^7.1` | Security headers |
| `dotenv` | `^16.3` | Environment variables |
| `tsx` (dev) | `^4.6` | Run TypeScript directly (replaces ts-node) |
| `typescript` (dev) | `^5.3` | TypeScript compiler |

> Use `tsx` for all scripts and dev server — it's faster than `ts-node`.

### Frontend (`frontend/pubspec.yaml`)

| Package | Version | Purpose |
|---|---|---|
| `socket_io_client` | `^2.0` | Socket.io WebSocket client |
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
│       ├── data/           ← Mongoose models, repository implementations
│       ├── services/       ← GameEngine, RoomService, CodeGenerator, NameGenerator
│       ├── presentation/   ← Express routes, Socket handlers, Zod validators
│       ├── config/         ← db.ts, logger.ts
│       └── scripts/seed.ts ← One-time DB seeding
└── frontend/               ← Flutter Web app (Phase 3)
    └── lib/
        ├── config/         ← router.dart, logger.dart
        ├── core/           ← failures.dart, typedefs.dart
        ├── services/       ← socket_service.dart
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

## ⚡ Real-time Events (Socket.io)

| Event | Direction | Payload |
|---|---|---|
| `room:join` | client → server | `{ roomCode, playerName? }` |
| `room:state` | server → client | `{ players, subject, status }` |
| `game:start` | server → all | `{ totalQuestions: 10 }` |
| `question:new` | server → all | `ClientQuestion` (no correct index) |
| `player:answer` | client → server | `{ questionId, answerIndex }` |
| `round:reveal` | server → all | `{ correctIndex, playerAnswers, scores }` |
| `game:end` | server → all | `{ scoreboard }` |
| `player:disconnected` | server → all | `{ playerId }` |

---

## 🪄 Edge Cases to Handle

| Scenario | Handling |
|---|---|
| Player disconnects mid-game | Mark as `null` answer for that round, game continues for remaining players |
| Only 1 player left | Game continues as solo mode |
| Creator disconnects | Assign creator role to next player in room |
| Player tries to join full room (4/4) | Reject with error message |
| Player opens same link twice | Detect duplicate session, show error |
| Room code collision | Regenerate on collision (rare with alphanumeric 3-char codes = 46,656 combos) |
| Player joins after game started | Reject — rooms are locked once game starts |
| All players disconnect | Clean up room from server after 60s timeout |

---

## 🔒 Security Rules

1. **Never send `correct_answer_index` in `question:new`** — always strip server-side
2. Only emit `correct_answer_index` via `round:reveal` after timer expires
3. Validate all socket payloads server-side (zod schemas recommended)
4. Rate-limit room creation per IP to prevent abuse

---

## 🗄️ MongoDB Collections

### `questions`
```json
{
  "_id": "osy_history_42",
  "subject": "history",
  "text": "...",
  "choices": ["...", "..."],
  "correct_answer_index": 0,
  "exam_type": "ZNO_NMT_General"
}
```
**Index:** `{ subject: 1 }`  
**Seed:** `data-set/questions/all.json` (3,595 docs)

### `rooms`
```json
{
  "code": "A9X",
  "subject": "history",
  "status": "waiting" | "playing" | "finished",
  "maxPlayers": 4,
  "players": [
    { "id": "socket_id", "name": "Веселий Кит", "color": "#FF6B6B", "score": 0, "isCreator": true }
  ],
  "questions": ["id1", "id2", ...],
  "currentQuestionIndex": 0,
  "createdAt": "..."
}
```

---

## 🪜 Build Steps (in order)

### Phase 1: Backend Foundation
- [ ] Init Node.js + Express + TypeScript project
- [ ] Connect to MongoDB Atlas (free tier)
- [ ] Seed database from `data-set/questions/all.json`
- [ ] Create index on `{ subject: 1 }`
- [ ] REST endpoint: `GET /subjects` — returns subject list + question counts
- [ ] REST endpoint: `POST /rooms` — creates room, returns code
- [ ] REST endpoint: `GET /rooms/:code` — returns room state

### Phase 2: Real-time Game Engine
- [ ] Integrate Socket.io into Express server
- [ ] Implement `room:join` handler + lobby broadcast
- [ ] Implement `game:start` — sample 10 questions, lock room
- [ ] Implement question timer (5 min server-side, authoritative)
- [ ] Implement `player:answer` handler + `round:reveal` emit
- [ ] Implement `game:end` with scoreboard
- [ ] Handle all disconnection edge cases

### Phase 3: Flutter Frontend
- [ ] Init Flutter Web project (`flutter create --platforms web frontend`)
- [ ] Add all packages from Confirmed Package Versions table
- [ ] `SocketService` — wraps socket_io_client, exposes event stream
- [ ] `RoomCubit` — lobby state (waiting/ready/gameStarted)
- [ ] `QuizCubit` — in-game state (question, timer countdown, answers, reveal)
- [ ] `GameCubit` — overall flow (create/join/results)
- [ ] go_router setup: `/`, `/create`, `/room/:code`, `/room/:code/game`, `/room/:code/results`
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
- [ ] Deploy backend → Railway (set env vars: `MONGODB_URI`, `PORT`, `CORS_ORIGIN`)
- [ ] Deploy frontend → Firebase Hosting (`flutter build web --release && firebase deploy`)

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
| **Railway** | Node.js backend (auto-deploys from GitHub, preferred) |
| **MongoDB Atlas** | Database (M0 free forever) |
| **Firebase Hosting** | Flutter Web frontend (CDN, fast) |

---

## 🎨 UI/UX Vibe

- **Dark mode first**, vibrant accent colors (think neon on dark)
- **Bouncy animations** on answer selection and reveal (like QuizUp)
- **Timer bar** that changes from green → yellow → red as time runs out
- **Player avatars** = colored circles with their funny name initials
- NMT-themed but **not boring** — it should feel like a game, not a study tool
