# 🛠️ NMT Quiz — Developer Operations Guide

> **For AI agents and developers:** This is your complete guide for setting up, running, debugging, and deploying the NMT Quiz Multiplayer app.
>
> The application is **fully built**. This guide covers operations, not implementation.
>
> For architecture details, see [`plan.md`](plan.md).
> For a quick reference card, see [`AGENTS.md`](../AGENTS.md).

---

## 1. Prerequisites

| Tool | Minimum Version | Notes |
|------|----------------|-------|
| Flutter / Dart | SDK `^3.9.2` | `flutter doctor` must pass |
| Node.js | `20+` | Use [nvm](https://github.com/nvm-sh/nvm) or [fnm](https://github.com/Schniz/fnm) |
| Docker | Latest stable | Required for local Supabase |
| Supabase CLI | Latest | Installed via `brew install supabase/tap/supabase` |

---

## 2. First-Time Setup

### Step 1 — Install dependencies

```bash
make install
# Runs: npm install (backend) + flutter pub get (frontend)
```

### Step 2 — Configure backend environment

```bash
cp backend/.env.example backend/.env
```

Edit `backend/.env`:

```dotenv
SUPABASE_URL=https://your-project-ref.supabase.co
SUPABASE_SERVICE_KEY=your-service-role-key    # from Supabase dashboard → Settings → API
SUPABASE_ANON_KEY=your-anon-key               # read by Makefile for --dart-define
PORT=3000
CORS_ORIGIN=                                  # leave blank for dev; required in production
NODE_ENV=development
LOG_LEVEL=info
```

For **local Supabase** (Docker), use:
```dotenv
SUPABASE_URL=http://127.0.0.1:54321
SUPABASE_SERVICE_KEY=<service_role key from supabase status>
SUPABASE_ANON_KEY=<anon key from supabase status>
```

### Step 3 — Start local Supabase and apply schema

```bash
make supabase-start   # starts Docker containers

# Wait for containers to be ready, then:
make supabase-push    # applies /supabase/migrations/*.sql
```

This creates 4 tables (`questions`, `rooms`, `players`, `round_answers`) and the `increment_player_score` RPC.

**Verify:**
```bash
# Using the local-db MCP, or psql:
psql postgresql://postgres:postgres@localhost:54322/postgres \
  -c "SELECT table_name FROM information_schema.tables WHERE table_schema='public';"
# Expected: questions, rooms, players, round_answers
```

### Step 4 — Seed questions

```bash
make seed
# Runs: backend/src/scripts/seed.ts
# Upserts 3,595 questions from data-set/questions/all.json into the questions table
```

**Verify:**
```sql
SELECT subject, COUNT(*) FROM questions GROUP BY subject ORDER BY subject;
-- Expected:
-- geography        | 476
-- history          | 1138
-- math             | 58
-- ukrainian_language | 1923
```

### Step 5 — Verify lint passes

```bash
make lint
# tsc --noEmit (backend) + flutter analyze (frontend)
# Both must report 0 issues before committing
```

---

## 3. Running the App

### Mode A — Full stack (recommended)

```bash
make all
# Starts: Supabase (if not running) + backend (port 3000) + frontend (Chrome, port 5000)
# Uses concurrently with color-coded prefixes: [BE] cyan, [FE] magenta
```

### Mode B — Individual services

```bash
# Terminal 1
make supabase-start

# Terminal 2
make backend    # tsx watch src/main.ts — hot reload on save

# Terminal 3
make frontend   # flutter run -d chrome --web-port=5000
```

### Mode C — iPhone / Mobile LAN testing

```bash
make iphone
# Starts: backend + Chrome frontend (port 5000) + web-server frontend (port 8080, 0.0.0.0)
# Auto-detects Mac LAN IP and substitutes it into Supabase URL for mobile Realtime
# Prints QR code — scan with iPhone camera to open in Safari
```

### Manual Flutter run (if Makefile unavailable)

```bash
cd frontend && flutter run -d chrome --web-port=5000 \
  --dart-define=SUPABASE_URL=http://127.0.0.1:54321 \
  --dart-define=SUPABASE_ANON_KEY=eyJ... \
  --dart-define=API_URL=http://localhost:3000
```

---

## 4. Environment Variables Reference

### Backend (`backend/.env`)

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `SUPABASE_URL` | ✅ | — | Supabase project URL |
| `SUPABASE_SERVICE_KEY` | ✅ | — | Service-role key (full DB access, never expose) |
| `SUPABASE_ANON_KEY` | ✅ | — | Anon key (read by Makefile for `--dart-define`) |
| `PORT` | — | `3000` | Express listen port |
| `CORS_ORIGIN` | — (dev) / ✅ (prod) | — | Allowed origin; blank = allow all (dev only) |
| `NODE_ENV` | — | `development` | Set to `production` to enforce CORS_ORIGIN |
| `LOG_LEVEL` | — | `info` | Pino level: `debug` / `info` / `warn` / `error` |
| `ROUND_TIMER_MS` | — | `300000` | Override 5-min round timer for testing |
| `PENDING_ROUND_TIMEOUT_MS` | — | `300000` | Override auto-advance delay after reveal |

### Frontend (`--dart-define` flags)

| Variable | Required | Description |
|----------|----------|-------------|
| `SUPABASE_URL` | ✅ | Must match backend's SUPABASE_URL |
| `SUPABASE_ANON_KEY` | ✅ | Anon key (NOT service key) |
| `API_URL` | ✅ | Backend base URL, e.g. `http://localhost:3000` |

---

## 5. Codebase Orientation

### Backend Entry Points

| File | Purpose |
|------|---------|
| `backend/src/main.ts` | Express app: middleware stack (cors, helmet, requestId, requestLogger), route mount, global error handler, process signal handlers |
| `backend/src/presentation/routes/index.ts` | All 10 route registrations + rate limiter + `:code` validation middleware |
| `backend/src/services/GameEngine.ts` | **Core game logic**: `startGame`, `startRound`, `submitAnswer`, `revealRound`, `nextQuestion`, `restartGame`, `endGame`. All in-memory state lives here. |
| `backend/src/services/PlayerManager.ts` | Heartbeat tracking, disconnect detection (60s), creator reassignment |
| `backend/src/config/supabase.ts` | Supabase client + `broadcastToRoom(code, event, payload)` via `channel.httpSend()` |
| `backend/src/presentation/validators/requestSchemas.ts` | All Zod schemas for request validation |
| `backend/src/data/repositories/RoomRepository.ts` | All DB operations for rooms/players/round_answers |

### Frontend Entry Points

| File | Purpose |
|------|---------|
| `frontend/lib/main.dart` | Boot sequence: Supabase init → create services → create cubits → **stream coordinator** → `MultiBlocProvider` → `NmtQuizApp` |
| `frontend/lib/config/router.dart` | 6 routes: `/`, `/create`, `/room/:code`, `/room/:code/game`, `/room/:code/reveal`, `/room/:code/results` |
| `frontend/lib/services/api_service.dart` | All REST calls; `_traced()` wrapper logs start/finish with requestId and durationMs |
| `frontend/lib/services/supabase_service.dart` | Realtime subscription setup; all 7 broadcast events → `_controller` stream |
| `frontend/lib/presentation/cubits/room_cubit/room_cubit.dart` | Join room, maintain lobby state, heartbeat timer, rejoin snapshot |
| `frontend/lib/presentation/cubits/quiz_cubit/quiz_cubit.dart` | In-game state: question display, countdown timer, answer submit, polling fallback, bootstrap from snapshot |
| `frontend/lib/presentation/cubits/game_cubit/game_cubit.dart` | Subject loading + room creation flow |

### The `main.dart` Stream Coordinator

The most non-obvious wiring in the app. A `roomCubit.stream.listen` in `main.dart` ensures `QuizCubit` always has `myPlayerId` and `roomCode` before game events arrive:

```dart
roomCubit.stream.listen((_) {
  // Forward identity to QuizCubit before any game events can arrive.
  if (roomCubit.myPlayerId != null && roomCubit.state.code.isNotEmpty) {
    quizCubit.setContext(roomCubit.myPlayerId!, roomCubit.state.code);
  }

  // Consume the pending snapshot once; consumePendingSnapshot() clears it.
  final snapshot = roomCubit.consumePendingSnapshot();

  // Prevent stale snapshot bootstrap from overwriting an active question/reveal.
  final canBootstrap =
      quizCubit.state is! QuizQuestion && quizCubit.state is! QuizReveal;
  if (snapshot != null && canBootstrap) {
    quizCubit.bootstrapFromSnapshot(snapshot);
  }
});
```

Important details:

- identity lives on `RoomCubit.myPlayerId`, not inside `RoomState`
- `consumePendingSnapshot()` returns the snapshot once and then clears it
- snapshot bootstrap currently restores active-question state, not reveal-window state

This is why `QuizCubit.setContext()` must be called before any game event handlers run, and why the room snapshot contract matters for reconnect flow.

---

## 6. Debug Playbooks

### Scenario A — Round reveal never fires

**Symptoms:** Game question shows, timer counts, but reveal screen never appears. Backend logs show `game.round.start` but no `game.round.revealed`.

**Diagnosis steps:**
1. Check backend logs for `game.broadcast.failed` — if `broadcastToRoom` threw, the reveal broadcast didn't reach clients.
2. Check `GET /api/rooms/:code/round-state` — if `pendingReveal` is populated, the reveal happened but Realtime delivery failed.
3. Verify `roundState` was populated: look for `game.round.start` log with matching `questionIndex`.
4. Check if all players are offline — `revealRound` only triggers early if all **online** players answered. Offline players (not in `PlayerManager.pings`) are excluded.
5. If Realtime is down: the 1s polling fallback in `QuizCubit` should detect `pendingReveal` and transition automatically.

**Fix:** If `pendingReveal` is set but client never transitions, check `QuizCubit.startPolling()` is being called (it should be started from `GameplayScreen.initState()`).

---

### Scenario B — Player stuck in lobby after game starts

**Symptoms:** Creator starts the game, but one player's screen stays on `RoomLobbyScreen`.

**Diagnosis steps:**
1. Check if `game:start` broadcast was received — look for `supabase.event.received` with `event: game:start` in frontend logs.
2. Verify `QuizCubit.setContext()` was called before `game:start` arrived. If `setContext` runs after, the handler may have been a no-op.
3. Check `room:state` broadcast — `RoomLobbyScreen` polls `syncRoomState()` every 1s; if room status is now `playing`, it should route to game.
4. Verify the Supabase channel subscription is active — look for `supabase.channel.subscribed` in frontend logs.

**Fix:** The lobby's 1s polling fallback (`syncRoomState()`) should recover this. If it doesn't, check `RoomCubit.joinRoom()` established the subscription before the start event.

---

### Scenario C — Game starts twice (double start)

**Symptoms:** Backend logs show `game.run` emitting twice for the same room. Two `game:start` broadcasts.

**Diagnosis steps:**
1. Check `startingMutex` — `GameEngine.startGame()` should add `roomCode` to the mutex Set and return early if it's already present.
2. Check if `restartGame` was called while `startGame` was in progress (both acquire the same mutex).
3. Look for `game.start.mutex.busy` log — this is emitted when a duplicate call is rejected.

**This should not happen in production** — the mutex prevents it. If it does, restart the backend process (clears all in-memory state) and investigate if two concurrent HTTP requests hit the start endpoint.

---

### Scenario D — Creator role not reassigned after disconnect

**Symptoms:** A player's screen shows the "Start" button after the creator disconnected, but they can't actually start because `is_creator` was not set in DB.

**Diagnosis steps:**
1. Check `PlayerManager` disconnect log — look for `player.disconnected` and then `room.creator.reassigned`.
2. Verify the disconnecting player's `lastPing` exceeded 60s threshold.
3. Check if there are any online players in `pings` map — if all are offline, no creator is assigned (room cleanup happens instead).
4. Check DB: `SELECT * FROM players WHERE room_code = 'CODE' ORDER BY joined_at;`

**Fix:** If `is_creator` is missing, the frontend still shows the button but the API call will return 403. A `POST /api/rooms/:code/start` with any `playerId` where `is_creator=true` in DB will work.

---

### Scenario E — Supabase Realtime not delivering events on mobile/LAN

**Symptoms:** Everything works on localhost Chrome, but mobile device doesn't receive broadcasts.

**Root cause:** Mobile device connects to Supabase Realtime using the WS URL from `SUPABASE_URL`. If that URL is `127.0.0.1` or `localhost`, the phone can't reach it.

**Fix:** Use `make iphone` which automatically replaces `localhost`/`127.0.0.1` with the Mac's LAN IP in `SUPABASE_URL` passed to the Flutter app. The backend still uses `localhost` in its `.env`.

If Realtime still fails, the 1s polling fallback in `QuizCubit` should handle missed events.

---

### Scenario F — CORS error in production

**Symptoms:** Frontend gets CORS error on API calls. Backend logs show startup error about missing `CORS_ORIGIN`.

**Diagnosis:** In production (`NODE_ENV=production`), `CORS_ORIGIN` must be set. Server throws on startup if it's missing.

**Fix:** Set `CORS_ORIGIN=https://your-frontend-domain.web.app` in the backend env. Verify the Flutter app's `API_URL` matches the backend deployment URL exactly.

---

## 7. Supabase: Local vs Cloud

### Local (Docker) — for development

```bash
make supabase-start       # starts containers
# Studio UI: http://localhost:54323
# DB connection: postgresql://postgres:postgres@localhost:54322/postgres (local-db MCP)

make supabase-push        # applies /supabase/migrations/*.sql
make supabase-stop        # stops containers (data persists)
```

**MCP tools available when local Supabase is running:**
- `local-db` MCP: `mcp__local-db__query` — run SQL directly

**Key local ports:**
| Service | Port |
|---------|------|
| Supabase API / Realtime | `54321` |
| Postgres DB | `54322` |
| Supabase Studio | `54323` |

### Cloud (Supabase.com) — for staging/production

**Setup Supabase MCP for cloud management:**
```bash
claude mcp add supabase -- npx -y @supabase/mcp-server-supabase@latest \
  --project-ref YOUR_PROJECT_REF \
  --read-only false
```

Set `SUPABASE_ACCESS_TOKEN=your-personal-access-token` in your shell or `.zshrc`.

Get credentials from the Supabase dashboard:
- Project ref: from the dashboard URL `supabase.com/dashboard/project/{ref}`
- Personal access token: `supabase.com/dashboard/account/tokens`
- Service role key: Project → Settings → API → `service_role` (secret)
- Anon key: Project → Settings → API → `anon` (public)

---

## 8. Testing Tips

### Fast Game Loops

Set these in `backend/.env` for rapid testing:
```dotenv
ROUND_TIMER_MS=10000           # 10-second rounds (instead of 5 min)
PENDING_ROUND_TIMEOUT_MS=30000 # 30-second auto-advance after reveal
```

### Lint Gate (required before commit)

```bash
make lint
# tsc --noEmit → 0 TypeScript errors
# flutter analyze → 0 issues
```

### Manual End-to-End Test

1. Open `http://localhost:5000` in Chrome tab 1 → Create room (pick subject, 2 players)
2. Open the same room code in Chrome tab 2 → Join room
3. Tab 1 (creator) → Start game
4. Both tabs: submit answers (or wait for timer)
5. Verify: round reveal shows correct answer + scores on both tabs
6. Tab 1 → "Next Question" → verify next question appears on both tabs
7. Complete 5 rounds → verify ResultsScreen with correct final scores
8. Tab 1 → "Грати знову" → verify game restarts on both tabs
9. Tab 1 → "Нова тема" → verify navigation to /create

### Security Check

Verify `correct_answer_index` is never sent to the client:
```bash
# While game is running, intercept question:new events
# Check browser DevTools → Network → WS → filter for 'question:new'
# Payload must NOT contain 'correct_answer_index'
```

The frontend `SupabaseService` also logs `security.violation` if it ever appears.

---

## 9. Deployment

### Backend (Render / Railway)

1. Connect your GitHub repo to Render/Railway.
2. Set root directory to `backend/`.
3. Configure:
   ```
   Build command : npm run build
   Start command : npm start
   ```
4. Set environment variables:
   ```
   SUPABASE_URL=https://xxx.supabase.co
   SUPABASE_SERVICE_KEY=eyJ...
   SUPABASE_ANON_KEY=eyJ...
   PORT=3000
   CORS_ORIGIN=https://your-frontend.web.app
   NODE_ENV=production
   LOG_LEVEL=info
   ```
5. Deploy. Check logs for `Server listening on port 3000`.

### Frontend (Firebase Hosting)

```bash
# Build with production values
cd frontend && flutter build web --release \
  --dart-define=SUPABASE_URL=https://xxx.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=eyJ... \
  --dart-define=API_URL=https://your-backend.onrender.com

# Deploy
firebase deploy
```

### Database (Cloud Supabase)

Apply migrations to your cloud project:
```bash
# Via Supabase CLI (from repo root)
supabase db push --project-ref YOUR_PROJECT_REF

# Or via Supabase MCP in a Claude Code session
```

Seed questions to cloud:
```bash
# With SUPABASE_URL and SUPABASE_SERVICE_KEY pointing to cloud in backend/.env
make seed
```

Supabase free tier limits:
- 200 concurrent Realtime connections
- 100 messages/sec
- 500 MB database storage

---

## 10. Common Makefile Targets (Quick Reference)

```bash
make install         # npm install + flutter pub get
make all             # everything: supabase + backend + frontend
make backend         # backend only (tsx watch, hot reload)
make frontend        # flutter web on Chrome :5000
make iphone          # dual frontend: Chrome :5000 + mobile :8080 with QR
make supabase-start  # start local Docker Supabase
make supabase-stop   # stop local Docker Supabase
make supabase-push   # apply migrations to local DB
make seed            # upsert 3,595 questions from data-set/
make lint            # tsc --noEmit + flutter analyze
```
