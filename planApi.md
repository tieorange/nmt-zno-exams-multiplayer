# API Review Plan (curl-driven)

Date: 2026-03-06

## Scope and Method
- Started API with `make backend` (Supabase local + `npm run dev`).
- Exercised endpoints with live `curl` requests against `http://127.0.0.1:3000/api`.
- Used code inspection (`rg`, `sed`, `nl`) to map each behavior to source lines.

## Priority Findings

### 1) P0: Malformed JSON returns 500 instead of 400
- Repro:
```bash
curl -s -X POST http://127.0.0.1:3000/api/rooms \
  -H 'Content-Type: application/json' \
  -d '{"subject":"math","maxPlayers":2'
# -> {"error":"Internal server error"} (HTTP 500)
```
- Why this is wrong:
  - Invalid client payload should be `400 Bad Request`, not internal server error.
  - Current behavior hides actionable client error and pollutes error telemetry.
- Code pointers:
  - `backend/src/main.ts:48` (`express.json()`)
  - `backend/src/main.ts:57` (generic 500 error handler)
- Fix plan:
  - Add explicit middleware for `SyntaxError` from JSON parser before generic handler.
  - Return stable client error shape (`400`, localized message, requestId).
- Acceptance criteria:
  - Malformed JSON always returns `400` with predictable API error contract.

### 2) P1: `GET /rooms/:code/round-state` returns 200 for non-existent rooms
- Repro:
```bash
curl -s http://127.0.0.1:3000/api/rooms/ZZZ/round-state
# -> {"playerAnswers":null,"pendingReveal":null} (HTTP 200)
```
- Why this is wrong:
  - Non-existent room should return `404`.
  - Clients cannot distinguish “no active round” vs “room does not exist”.
- Code pointers:
  - `backend/src/presentation/controllers/RoomController.ts:83-88`
- Fix plan:
  - Check room existence (`dbGetRoom`) before returning round state.
  - Return `404` if missing; otherwise return current payload.
- Acceptance criteria:
  - `/round-state` behavior matches `/rooms/:code` existence semantics.

### 3) P1: `POST /rooms/:code/next-question` returns misleading 400 for non-existent room
- Repro:
```bash
curl -s -X POST http://127.0.0.1:3000/api/rooms/ZZZ/next-question \
  -H 'Content-Type: application/json' \
  -d '{"playerId":"11111111-1111-1111-1111-111111111111"}'
# -> {"error":"Тільки творець може перейти до наступного питання"} (HTTP 400)
```
- Why this is wrong:
  - For missing room, response should be `404`, not creator-permission error.
- Code pointers:
  - `backend/src/presentation/controllers/GameController.ts:108-125`
  - `backend/src/services/GameEngine.ts:315-320` (`getPlayers` empty => not creator)
- Fix plan:
  - In controller: load room first and return `404` if missing.
  - Distinguish authorization (`403`) from state errors (`409`/`400`).
- Acceptance criteria:
  - Missing room => `404`; non-creator => `403`; invalid phase => dedicated business error code.

### 4) P1: Heartbeat on non-existent room returns 403 “does not belong to this room”
- Repro:
```bash
curl -s -X POST http://127.0.0.1:3000/api/rooms/ZZZ/heartbeat \
  -H 'Content-Type: application/json' \
  -d '{"playerId":"11111111-1111-1111-1111-111111111111"}'
# -> {"error":"Player does not belong to this room"} (HTTP 403)
```
- Why this is wrong:
  - Missing room should return `404`.
  - Current message is semantically wrong and complicates client recovery.
- Code pointers:
  - `backend/src/presentation/controllers/RoomController.ts:195-199`
  - `validatePlayerInRoom()` (`RoomController.ts:23-31`)
- Fix plan:
  - First check room existence in `heartbeat`.
  - Then check membership (`403`) and heartbeat session validity (`400`).
- Acceptance criteria:
  - Error order: room existence -> membership -> session validity.

### 5) P2: Authorization/status-code inconsistency on game actions
- Repro examples:
  - Non-creator next question returns `400` (should be `403`).
  - Similar permission failures elsewhere return `403` correctly.
- Code pointers:
  - `backend/src/presentation/controllers/GameController.ts:124`
- Fix plan:
  - Introduce typed domain errors (e.g., `NotFoundError`, `ForbiddenError`, `ConflictError`, `ValidationError`).
  - Map errors centrally in middleware instead of per-controller `catch` returning hardcoded `400`.
- Acceptance criteria:
  - Consistent status-code mapping across all game/room endpoints.

### 6) P2: API error contract is inconsistent (shape + language)
- Observed variants:
  - English: `Room not found`, `Invalid room code format`, `Player does not belong to this room`
  - Ukrainian: `Кімнату не знайдено`, `Гра вже почалась`, etc.
  - Validation: `{ error: parsed.error.flatten() }` object shape differs from string errors.
- Code pointers:
  - `backend/src/presentation/controllers/RoomController.ts`
  - `backend/src/presentation/controllers/GameController.ts`
  - `backend/src/presentation/routes/index.ts`
- Fix plan:
  - Standardize error envelope, for example:
    - `{ error: { code, message, details?, requestId } }`
  - Adopt one user-facing language for API client messages (UA for UI-facing errors).
  - Keep internal logs in English.
- Acceptance criteria:
  - Every non-2xx response follows one schema and one localization policy.

### 7) P2: Sensitive room state endpoints are unauthenticated
- Repro:
```bash
curl -s http://127.0.0.1:3000/api/rooms/<code>
curl -s http://127.0.0.1:3000/api/rooms/<code>/round-state
```
- Why improve:
  - Anyone with a guessed room code can fetch player identities/scores/answer-progress state.
  - Room code is only 3 chars (`36^3 = 46,656` combinations), so enumeration risk is practical.
- Code pointers:
  - `backend/src/presentation/routes/index.ts:32,39`
- Fix plan:
  - Add access token/session proof for room reads.
  - Increase room code entropy (e.g., 5-6 chars) or add rate-limited lookup protections.
- Acceptance criteria:
  - Unauthorized room state reads are rejected; code brute-force cost is materially higher.

### 8) P3: API robustness/testing improvements
- Current gap:
  - No automated API contract suite validating status codes and error shapes for edge cases found above.
- Fix plan:
  - Add integration tests (Node test runner + `supertest` or `vitest` + `supertest`).
  - Cover:
    - malformed JSON
    - non-existent room behavior for all room/game routes
    - auth vs validation vs conflict code mapping
    - error schema consistency
- Acceptance criteria:
  - CI blocks regressions for API contract and status-code semantics.

### 9) P1: Orphaned round timers after room deletion cause invalid reveal metrics
- Evidence observed in backend logs after players disconnected:
  - `event: "game.round.reveal"`
  - `answeredCount: -2`
  - `scores: {}`
- Why this is wrong:
  - Negative `answeredCount` is impossible in valid game state.
  - Indicates reveal timer is still firing after room/player teardown, producing inconsistent events.
- Code pointers:
  - `backend/src/services/GameEngine.ts:224-229` (unanswered derived from stale in-memory map)
  - `backend/src/services/GameEngine.ts:278` (`players.length - unanswered.length` can go negative)
  - `backend/src/services/PlayerManager.ts:77-85` (room deletion path does not clear game timers/state)
- Likely root cause:
  - `roundState`/pending timers are in-memory and survive room deletion triggered by disconnect handler.
- Fix plan:
  - Add explicit game-state cleanup API in `GameEngine` (clear round timer, pending fallback timer, reveal cache, cleanup timeout) and call it when room is deleted/abandoned.
  - Guard reveal path: if room no longer exists, abort without broadcasting.
  - Clamp or recompute `answeredCount` from active player set only.
- Acceptance criteria:
  - No negative reveal metrics.
  - No `round:reveal` broadcast after room deletion.
  - Disconnect/delete flow leaves no orphaned timers for removed room.

## Useful Reproduction Commands
```bash
# 1. malformed JSON
curl -i -X POST http://127.0.0.1:3000/api/rooms -H 'Content-Type: application/json' -d '{"subject":"math","maxPlayers":2'

# 2. round-state on missing room
curl -i http://127.0.0.1:3000/api/rooms/ZZZ/round-state

# 3. next-question on missing room
curl -i -X POST http://127.0.0.1:3000/api/rooms/ZZZ/next-question -H 'Content-Type: application/json' -d '{"playerId":"11111111-1111-1111-1111-111111111111"}'

# 4. heartbeat on missing room
curl -i -X POST http://127.0.0.1:3000/api/rooms/ZZZ/heartbeat -H 'Content-Type: application/json' -d '{"playerId":"11111111-1111-1111-1111-111111111111"}'
```

## Suggested Agent Work Split
1. Agent A: Error handling foundation
- Add typed domain errors + centralized HTTP mapper + malformed JSON handler.

2. Agent B: Room/game route semantics
- Fix not-found/forbidden/conflict mapping for `round-state`, `next-question`, `heartbeat`.

3. Agent C: API contract unification
- Unify error schema + localization policy.

4. Agent D: Security hardening
- Add auth/session gate for room state endpoints + improve room code entropy/rate-protection.

5. Agent E: Integration tests
- Add regression suite for all issues above and wire into CI.
