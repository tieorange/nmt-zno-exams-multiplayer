# Frontend + FE/BE Integration Fix Plan (Agent-Ready)

## Goal
A practical backlog for AI agents to fix frontend and frontend-backend integration defects with minimal ambiguity.

## How to use this file
- Execute tickets in order (dependencies are explicit).
- One ticket per agent/PR.
- Do not mix doc-only and code tickets in one PR.
- Keep API contracts backward-compatible unless ticket explicitly says otherwise.

## Current verification status
- Backend typecheck: `npm run typecheck` ✅
- Frontend analyze: blocked ❌ (local Dart `3.7.2`, project requires `^3.9.2`)

---

## Priority Roadmap
1. `P0-A` Rejoin sync during active round
2. `P0-B` Creator reassignment when creator is offline
3. `P1-A` CORS + dev port consistency
4. `P1-B` Stable backend error contract
5. `P1-C` Route guards for deep links
6. `P1-D` Results rematch in same room (`restart`)
7. `P1-E` Dynamic subjects from backend
8. `P2-A` Broadcast hardening (`httpSend` risk)
9. `P2-B` Docs/code contract sync
10. `P2-C` Toolchain pinning for frontend

---

## P0-A: Rejoin During Active Round Is Not Fully Synced

### Problem
Rejoining player can enter `playing` state without current question/timer context and get stuck in loading screen until next event.

### Evidence
- Recovery endpoint already exists and returns `currentQuestion`:
  - `backend/src/presentation/controllers/RoomController.ts:47`
  - `backend/src/presentation/controllers/RoomController.ts:61`
- Frontend never calls room state endpoint:
  - `frontend/lib/services/api_service.dart`
- Gameplay requires `QuizQuestion` state, otherwise spinner:
  - `frontend/lib/presentation/pages/gameplay_screen.dart:28`

### Root cause
Backend supports rejoin recovery, frontend does not consume it.

### Implementation checklist
1. Add `ApiService.getRoomState(String roomCode)` -> `GET /api/rooms/:code`.
2. In `RoomCubit.joinRoom`, after successful join call `getRoomState`.
3. If `status=playing` and `currentQuestion!=null`, pass sync payload to `QuizCubit`.
4. Add method in `QuizCubit` for bootstrap state from server snapshot:
   - set current question
   - set question index
   - initialize timer with remaining duration strategy
5. Add fallback behavior if snapshot exists but timer metadata is missing.

### Contract improvement (recommended)
Extend `GET /api/rooms/:code` payload with:
- `roundStartedAt` (ISO)
- `timerMs`
- `questionIndex` (already partially available)

### Acceptance criteria
- Refresh during active question restores the same question immediately.
- No indefinite spinner on `/room/:code/game` after refresh.
- Answer submission works after rejoin without requiring next round.

### Agent prompt
Implement ticket `P0-A` from `planBugs.md`. Only modify FE + minimal BE contract fields needed for room snapshot recovery. Add logs for sync path and include a short manual test checklist in your PR description.

---

## P0-B: Creator Reassignment Fails If Creator Disconnects Mid-Game

### Problem
If creator goes offline mid-game, creator role can remain attached to offline player; online players cannot manually advance rounds.

### Evidence
- Offline players are retained in DB while playing:
  - `backend/src/services/PlayerManager.ts:65`
- Reassignment checks only `hasCreator` flag globally, not online status:
  - `backend/src/services/PlayerManager.ts:85`

### Root cause
Creator liveness is not considered in reassignment logic.

### Implementation checklist
1. In `handlePlayerDisconnect`, identify current creator and whether creator is online (`pings.has(creatorId)`).
2. If creator is offline:
   - clear existing creator flag(s) in room
   - assign creator to oldest online player
3. Broadcast updated `room:state` after reassignment.
4. Keep behavior unchanged for waiting-room disconnect edge cases unless broken.

### Acceptance criteria
- Creator disconnect during reveal/gameplay -> online player becomes creator in next sweep.
- New creator can successfully call `/next-question`.

### Agent prompt
Implement `P0-B` only. Ensure creator reassignment uses online status, not only DB flags. Keep existing room cleanup behavior unless directly required.

---

## P1-A: Dev CORS Configuration Conflicts With Flutter Web Port Behavior

### Problem
Local FE calls can fail due CORS depending on random Flutter web port.

### Evidence
- Backend dev allowlist: `localhost:3000`, `localhost:4200`
  - `backend/src/main.ts:26`
- `.env.example` suggests `localhost:5000`
  - `backend/.env.example:5`
- `make frontend` does not pin web port
  - `Makefile:57`

### Implementation checklist
1. Choose one policy:
   - Option 1: fixed port (`flutter run ... --web-port=5000`)
   - Option 2: function-based CORS origin allowing localhost any port in dev.
2. Align `backend/.env.example`, `Makefile`, and README with selected policy.
3. Verify create/join/start/answer from browser without manual CORS edits.

### Acceptance criteria
- `make backend` + `make frontend` works in clean setup.
- No CORS errors in browser console for core endpoints.

### Agent prompt
Implement `P1-A` and keep production CORS strict. Dev mode should be frictionless but not weaken prod.

---

## P1-B: Missing Global Express Error Middleware

### Problem
Unhandled exceptions can return non-JSON responses and break FE error handling.

### Evidence
- Async route wrapper calls `next(err)`:
  - `backend/src/presentation/routes/index.ts:24`
- No centralized error middleware in app:
  - `backend/src/main.ts`

### Implementation checklist
1. Add final error middleware after routes.
2. Return stable shape: `{ error: string, code?: string }`.
3. Map known validation/domain errors to 4xx, unknown errors to 500.
4. Keep full stack details server-side logs only.

### Acceptance criteria
- All thrown route/controller errors return JSON.
- Frontend receives parseable error payloads consistently.

### Agent prompt
Implement `P1-B` with minimal API changes. Ensure no HTML error pages are returned from `/api/*`.

---

## P1-C: Deep-Link Route Guards Missing (`/game`, `/reveal`, `/results`)

### Problem
Direct navigation can land user in routes with missing cubit state and infinite loaders.

### Evidence
- No route guard/redirect logic:
  - `frontend/lib/config/router.dart`
- Gameplay/reveal assume state exists:
  - `frontend/lib/presentation/pages/gameplay_screen.dart:28`
  - `frontend/lib/presentation/pages/round_reveal_screen.dart:28`

### Implementation checklist
1. Add guard/redirect policy in router:
   - not joined -> lobby/home
   - no active gameplay snapshot -> lobby
2. Add bootstrap/recovery step using room snapshot (`P0-A`).
3. Replace indefinite spinner with actionable fallback UI.

### Acceptance criteria
- Opening deep links never hangs permanently.
- User is redirected to valid state or sees recover action.

### Agent prompt
Implement `P1-C` after `P0-A`. Keep routing deterministic and avoid navigation loops.

---

## P1-D: Results Screen Missing In-Room Rematch

### Problem
Creator cannot trigger same-room rematch despite backend `restart` support.

### Evidence
- Creator button only routes to `/create`:
  - `frontend/lib/presentation/pages/results_screen.dart:176`
- Restart endpoint exists and API client has method:
  - `backend/src/presentation/routes/index.ts:37`
  - `frontend/lib/services/api_service.dart:105`

### Implementation checklist
1. Add creator actions:
   - `Грати знову` -> call `restartGame(roomCode, myPlayerId)`.
   - `Нова тема` -> existing `/create` flow.
2. Show loading/disabled state while restart request in flight.
3. Handle restart failure with snackbar/toast.
4. Transition on `game:start` event to gameplay.

### Acceptance criteria
- Rematch works without creating new room.
- All connected players continue in same room and receive new round stream.

### Agent prompt
Implement `P1-D` only. Keep non-creator flow unchanged.

---

## P1-E: Subject Picker Is Hardcoded (Drifts From Backend)

### Problem
Create-room subject list is static and can diverge from backend enabled/count metadata.

### Evidence
- Hardcoded subjects:
  - `frontend/lib/presentation/pages/create_room_screen.dart:8`
- Backend authoritative subjects endpoint:
  - `backend/src/presentation/controllers/SubjectController.ts`

### Implementation checklist
1. Add FE state for subjects loading (new cubit or extend `GameCubit`).
2. Load `/api/subjects` on create-room screen entry.
3. Render `displayName`, `questionCount`, `enabled`.
4. Prevent selecting disabled subjects.

### Acceptance criteria
- FE subject list matches backend response.
- Enabled/disabled state respected.

### Agent prompt
Implement `P1-E` with no hardcoded subject data in UI.

---

## P2-A: Broadcast Path Uses `httpSend` + Per-Event Channel Creation

### Problem
Current broadcast path depends on non-public-ish API usage and may create unnecessary channel objects.

### Evidence
- `any` cast + `httpSend`:
  - `backend/src/config/supabase.ts:33`
- New channel created each broadcast call:
  - `backend/src/config/supabase.ts:29`

### Implementation checklist
1. Replace with explicit REST broadcast request (documented Supabase path), or
2. Reuse room channels and remove them when no longer needed.
3. Add integration check that FE receives a broadcast after backend emit.

### Acceptance criteria
- Broadcast implementation uses stable public mechanism.
- No unbounded channel growth risk.

### Agent prompt
Implement `P2-A` with zero payload contract changes for frontend listeners.

---

## P2-B: Docs and Runtime Contract Drift

### Problem
Docs describe behavior differing from code; agents can implement wrong behavior.

### Evidence
- Docs say 10 questions + auto-next delay:
  - `docs/plan.md:157`, `docs/plan.md:168`
- Runtime uses 5 questions + creator-next with fallback timeout:
  - `backend/src/services/GameEngine.ts:22`, `:320`, `:342`
- `planImplementation.md` still has outdated scaffold assumptions.

### Implementation checklist
1. Decide canonical behavior (code-first recommended).
2. Update docs to exact current event contracts and gameplay loop.
3. Add “Contract Version” section:
   - endpoints
   - realtime events
   - required/optional fields

### Acceptance criteria
- Docs match runtime behavior and payloads.
- New agent can work from docs without reverse engineering code.

### Agent prompt
Implement `P2-B` docs-only PR. No runtime code changes.

---

## P2-C: Frontend Toolchain Pinning Missing

### Problem
Developers/agents can’t run FE checks reliably due SDK mismatch.

### Evidence
- Required SDK: `frontend/pubspec.yaml` -> `^3.9.2`
- Local environment here: Dart `3.7.2` (analyze blocked)

### Implementation checklist
1. Choose strategy:
   - pin Flutter via FVM and commit `.fvmrc`, or
   - relax SDK constraint if safe.
2. Add version requirements in README + Makefile help output.
3. Add CI guard printing detected Flutter/Dart versions before FE jobs.

### Acceptance criteria
- Fresh contributor can run `flutter pub get` and `flutter analyze` directly from docs.

### Agent prompt
Implement `P2-C` with the least friction for onboarding.

---

## PR Boundaries (Important)
- PR-1: `P0-A`
- PR-2: `P0-B`
- PR-3: `P1-A` + `P1-B`
- PR-4: `P1-C` + `P1-D`
- PR-5: `P1-E`
- PR-6: `P2-A`
- PR-7: `P2-B` + `P2-C`

---

## Regression Suite (Manual)
1. Create room, join with second player, start game.
2. Refresh one player mid-question; verify instant recovery.
3. Disconnect creator; verify reassignment and next-question authority.
4. Deep-link directly to `/room/:code/game` before join; verify safe redirect.
5. Finish game, creator presses `Грати знову`; verify same-room rematch.
6. Verify `question:new` never contains `correct_answer_index`.
7. Verify no CORS errors in local browser during full loop.

---

## Non-Goals
- Redesign UI style.
- New gameplay mechanics.
- Backend architecture rewrites.

