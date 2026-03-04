# NMT Quiz Multiplayer — Testing Plan (Code-Verified)

## 1) Verification Matrix (from current code)

### Exists (confirmed in code)
1. `playerId` vs `id` mismatch across API payloads.
   - Join returns `playerId`: `backend/src/presentation/controllers/RoomController.ts:127,177`
   - Room state returns `players[].id`: `backend/src/presentation/controllers/RoomController.ts:73-79`
2. Lobby max-player flicker risk (`1/4` before sync).
   - Default is `maxPlayers = 4`: `frontend/lib/presentation/cubits/room_cubit/room_state.dart:22`
   - UI renders `state.maxPlayers`: `frontend/lib/presentation/pages/room_lobby_screen.dart:160`
   - Initial `joinRoom` emit does not set maxPlayers: `frontend/lib/presentation/cubits/room_cubit/room_cubit.dart:96-102`
3. Refresh/rejoin may lose selected-answer UI state in active round.
   - Snapshot restore does not include `myAnswer`: `frontend/lib/presentation/cubits/quiz_cubit/quiz_cubit.dart:76-83`
   - UI selection depends on `q.myAnswer`: `frontend/lib/presentation/pages/gameplay_screen.dart:119-135`
   - Backend has answer-load helper but no integration into rejoin flow: `backend/src/services/GameEngine.ts:383-393`
4. Frontend web port hardcoded to `5000`.
   - `Makefile:62,69`
5. Missing full in-round realtime fallback path.
   - Lobby polling exists only in waiting state: `frontend/lib/presentation/pages/room_lobby_screen.dart:29-35`
   - Gameplay has one-time snapshot recovery, not continuous fallback for reveal/end: `frontend/lib/presentation/pages/gameplay_screen.dart:33-37`

### Not a bug (design/contract as implemented)
1. Round does not auto-advance immediately after all answers.
   - Intended flow: reveal -> creator calls `next-question`, with fallback timer.
   - `backend/src/services/GameEngine.ts:277-313`
   - `frontend/lib/presentation/pages/round_reveal_screen.dart:185-203`
2. `maxPlayers` naming in create-room payload.
   - Backend schema expects `maxPlayers`: `backend/src/presentation/validators/requestSchemas.ts:8-11`
   - Frontend sends `maxPlayers`: `frontend/lib/services/api_service.dart:73-80`

### Requires runtime repro (cannot prove from static code alone)
1. `SUPABASE_URL` resolving to frontend origin/port.
   - Frontend reads dart define: `frontend/lib/services/supabase_service.dart:31-35`
   - Makefile injects from `backend/.env`: `Makefile:4-11`
   - Current local `.env` value is valid (`http://127.0.0.1:54321`), so treat as environment/runtime issue until reproduced.

## 2) Prioritized Worklist

### P0 (reliability)
- [ ] Implement full gameplay fallback when realtime is degraded (playing/reveal/end states, not only lobby waiting state).
- [ ] Restore submitted-answer state on refresh/rejoin from backend truth.
- [ ] Add startup validation logs for `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `API_URL` and clear failure mode in debug.

### P1 (consistency + UX)
- [ ] Unify player identifier contract (`playerId` vs `id`) or document strict mapping in DTOs.
- [ ] Fix lobby `maxPlayers` flicker at join time.
- [ ] Make web port configurable (`WEB_PORT ?= 5001`) and use it in both `frontend` and `all` targets.

### P2 (docs/maintenance)
- [ ] Document intended round progression behavior (creator advances, fallback timeout exists).
- [ ] Add API payload examples for room lifecycle endpoints.

## 3) Test Execution Plan

### A. Core Flow
- [ ] Create room (`POST /api/rooms`, `maxPlayers=2`) and verify lobby immediately stabilizes at `1/2`.
- [ ] Join second player and verify creator + roster fields.
- [ ] Start game and verify `question:new` payload excludes `correct_answer_index`.
- [ ] Submit both players’ answers and verify reveal state appears.
- [ ] Advance with `POST /api/rooms/:code/next-question` and verify next round starts.
- [ ] Finish all rounds and verify `game:end` scoreboard + room status.

### B. Failure/Recovery
- [ ] Break realtime connection during round and verify fallback still reaches reveal/end states.
- [ ] Refresh after answer submit; verify selected answer remains locked/restored.
- [ ] Disconnect creator during reveal; verify fallback timer eventually advances.

### C. Contract/Security
- [ ] Validate endpoint docs and tests use `/api/...` paths only.
- [ ] Validate player ID field mapping is consistent at boundaries.
- [ ] Verify no client-facing payload includes `correct_answer_index`.

## 4) Exit Criteria

- [ ] No round can get stuck due only to realtime disconnects.
- [ ] Refresh/rejoin keeps player answer state accurate for current round.
- [ ] API contracts are consistent and documented.
- [ ] Local run flow is portable on macOS without port conflicts.
