# planBugs.md

## Scope
Analysis of:
- `docs/plan.md`
- `docs/planImplementation.md`

This is a prioritized list of bugs, contradictions, and improvement items in the docs, with concrete solutions for AI agents.

## Priority Legend
- `P0` critical: security/data integrity/broken core flow
- `P1` high: major product or architecture mismatch
- `P2` medium: scalability/reliability/quality risks
- `P3` low: wording/consistency/doc hygiene

---

## P0 Issues (Fix First)

### 1) Unauthenticated identity spoofing via `playerId`
- Severity: `P0`
- Evidence:
  - [docs/plan.md](/Users/anduser/AndroidStudioProjects/nmt-zno-exams-multiplayer/docs/plan.md:192) and [docs/plan.md](/Users/anduser/AndroidStudioProjects/nmt-zno-exams-multiplayer/docs/plan.md:197) define sensitive actions by client-supplied `playerId`.
  - [docs/planImplementation.md](/Users/anduser/AndroidStudioProjects/nmt-zno-exams-multiplayer/docs/planImplementation.md:873) checks creator using provided `playerId` only.
  - [docs/planImplementation.md](/Users/anduser/AndroidStudioProjects/nmt-zno-exams-multiplayer/docs/planImplementation.md:886) accepts answer with provided `playerId` only.
- Why this is a bug:
  - Any client that knows another player's ID can impersonate them (`start`, `answer`, future `restart`).
- Solution:
  - Introduce signed server-issued identity token on join (JWT or opaque token).
  - Replace `playerId` in request body with `Authorization: Bearer <token>`.
  - Server resolves player identity from token claims/session table.
- Agent tasks:
  1. Add `player_sessions` table (player_id, session_id, token hash/exp).
  2. Update `POST /join` to return `{ accessToken, player }`.
  3. Add auth middleware to `start/answer/heartbeat/restart`.
  4. Remove trust in body `playerId`.
- Acceptance criteria:
  - Requests with forged `playerId` but wrong token are `401/403`.
  - Creator-only actions cannot be triggered by non-creator token.

### 2) Duplicate-join/session design is declared but not implemented in base flow
- Severity: `P0`
- Evidence:
  - [docs/plan.md](/Users/anduser/AndroidStudioProjects/nmt-zno-exams-multiplayer/docs/plan.md:152), [docs/plan.md](/Users/anduser/AndroidStudioProjects/nmt-zno-exams-multiplayer/docs/plan.md:190), [docs/plan.md](/Users/anduser/AndroidStudioProjects/nmt-zno-exams-multiplayer/docs/plan.md:213) require persistent `sessionId`.
  - `JoinRoomSchema` has no body: [docs/planImplementation.md](/Users/anduser/AndroidStudioProjects/nmt-zno-exams-multiplayer/docs/planImplementation.md:498).
  - `joinRoom` ignores session and always creates a new UUID: [docs/planImplementation.md](/Users/anduser/AndroidStudioProjects/nmt-zno-exams-multiplayer/docs/planImplementation.md:577).
- Why this is a bug:
  - Reloading/opening multiple tabs can consume extra room slots and break lobby correctness.
- Solution:
  - Make `sessionId` mandatory in join body.
  - Add unique constraint per room on `(room_code, session_id)`.
  - If same session joins again, return existing player.
- Agent tasks:
  1. Add `session_id` column in `players` and unique index.
  2. Update `JoinRoomSchema` + `ApiService.joinRoom(sessionId)`.
  3. Change join logic to upsert/find-by-session first.
- Acceptance criteria:
  - Same browser session rejoin returns same player identity.
  - No duplicate slots for same session.

### 3) Heartbeat/restart endpoints are in plan but missing from core implementation routes
- Severity: `P0`
- Evidence:
  - Planned: [docs/plan.md](/Users/anduser/AndroidStudioProjects/nmt-zno-exams-multiplayer/docs/plan.md:193), [docs/plan.md](/Users/anduser/AndroidStudioProjects/nmt-zno-exams-multiplayer/docs/plan.md:194).
  - Routes shown only include `subjects/rooms/join/start/answer`: [docs/planImplementation.md](/Users/anduser/AndroidStudioProjects/nmt-zno-exams-multiplayer/docs/planImplementation.md:613).
  - Phase 3.5 claims they are implemented, but no code block for actual route/controller wiring: [docs/planImplementation.md](/Users/anduser/AndroidStudioProjects/nmt-zno-exams-multiplayer/docs/planImplementation.md:1867).
- Why this is a bug:
  - Core edge-case behavior depends on heartbeat/restart; without endpoints it is incomplete.
- Solution:
  - Add explicit controller/service snippets for `heartbeat` and `restart` in main phase sections (not only narrative).
- Agent tasks:
  1. Add validators, controllers, routes, tests.
  2. Add frontend API methods and periodic heartbeat scheduler.
- Acceptance criteria:
  - Endpoint list and route code are consistent.
  - Disconnect sweep and restart are test-covered.

### 4) Volatile in-memory round state with no crash-recovery plan
- Severity: `P0`
- Evidence:
  - Round state is only in memory: [docs/planImplementation.md](/Users/anduser/AndroidStudioProjects/nmt-zno-exams-multiplayer/docs/planImplementation.md:708).
  - Plan expects handling disconnection/restart cleanup: [docs/plan.md](/Users/anduser/AndroidStudioProjects/nmt-zno-exams-multiplayer/docs/plan.md:307).
- Why this is a bug:
  - Process restart loses active timers/answers, leaving rooms stuck or inconsistent.
- Solution:
  - Persist round metadata (`round_started_at`, answers, status) and run a recovery bootstrap on server start.
  - On restart, either resume round based on elapsed time or force safe reveal/cancel.
- Agent tasks:
  1. Add persistent `round_answers` store (JSONB or dedicated table).
  2. Add startup recovery job.
  3. Document deterministic restart behavior.
- Acceptance criteria:
  - Restart during active game produces deterministic and recoverable state.

### 5) CORS fallback `*` is unsafe for production docs - DON"T IMPLEMENT IT!!!!!!
- Severity: `P0`
- Evidence:
  - [docs/planImplementation.md](/Users/anduser/AndroidStudioProjects/nmt-zno-exams-multiplayer/docs/planImplementation.md:637) uses `origin: process.env.CORS_ORIGIN || '*'`.
- Why this is a bug:
  - Enables any origin if env misconfigured.
- Solution:
  - Remove wildcard fallback; fail fast if `CORS_ORIGIN` missing outside local dev.
- Agent tasks:
  1. Add env validation schema.
  2. Allow `localhost` defaults only in `development`.
- Acceptance criteria:
  - Production startup fails on missing `CORS_ORIGIN`.

---

## P1 Issues

### 6) Core architecture contradiction: Socket.io/MongoDB vs Supabase-only design
- Severity: `P1`
- Evidence:
  - Plan says no Socket.io/Mongoose: [docs/plan.md](/Users/anduser/AndroidStudioProjects/nmt-zno-exams-multiplayer/docs/plan.md:85).
  - Implementation start says build with Socket.io + MongoDB: [docs/planImplementation.md](/Users/anduser/AndroidStudioProjects/nmt-zno-exams-multiplayer/docs/planImplementation.md:23).
  - Gameplay loop mentions MongoDB: [docs/plan.md](/Users/anduser/AndroidStudioProjects/nmt-zno-exams-multiplayer/docs/plan.md:157).
- Why this is a bug:
  - Agents will implement different stacks depending on section read order.
- Solution:
  - Normalize all docs to one stack (Supabase + REST + Realtime Broadcast).
  - Remove all Socket.io/MongoDB mentions.

### 7) Logging spec contradicts chosen transport and format
- Severity: `P1`
- Evidence:
  - Wants structured logs: [docs/plan.md](/Users/anduser/AndroidStudioProjects/nmt-zno-exams-multiplayer/docs/plan.md:341).
  - Examples use `SocketHandler`/`SocketService` and plain-text lines: [docs/plan.md](/Users/anduser/AndroidStudioProjects/nmt-zno-exams-multiplayer/docs/plan.md:351), [docs/plan.md](/Users/anduser/AndroidStudioProjects/nmt-zno-exams-multiplayer/docs/plan.md:372).
  - Rule says "Log every Socket.io event": [docs/plan.md](/Users/anduser/AndroidStudioProjects/nmt-zno-exams-multiplayer/docs/plan.md:380).
- Why this is a bug:
  - Confuses observability and event taxonomy.
- Solution:
  - Define one canonical JSON log schema.
  - Rename event logging to REST + Supabase broadcast events.

### 8) Endpoint contract mismatch for `join`
- Severity: `P1`
- Evidence:
  - Event table says `join` body includes `{ sessionId }`: [docs/plan.md](/Users/anduser/AndroidStudioProjects/nmt-zno-exams-multiplayer/docs/plan.md:190).
  - Gate check sends empty body join: [docs/planImplementation.md](/Users/anduser/AndroidStudioProjects/nmt-zno-exams-multiplayer/docs/planImplementation.md:668).
- Why this is a bug:
  - API consumers get conflicting contracts.
- Solution:
  - Choose one contract (recommended: mandatory `sessionId`) and align all examples/tests.

### 9) “3-digit alphanumeric” wording is incorrect and repeated
- Severity: `P1`
- Evidence:
  - [docs/plan.md](/Users/anduser/AndroidStudioProjects/nmt-zno-exams-multiplayer/docs/plan.md:144) / [docs/plan.md](/Users/anduser/AndroidStudioProjects/nmt-zno-exams-multiplayer/docs/plan.md:150) say "3-digit" but sample `A9X` is not digits-only.
- Why this is a bug:
  - Creates validation mistakes in UI/backend.
- Solution:
  - Replace with "3-character alphanumeric (A-Z0-9)" in all docs and validators.

### 10) Create-room flow says creator immediately gets name/color, but API flow requires extra join
- Severity: `P1`
- Evidence:
  - Flow expectation: [docs/plan.md](/Users/anduser/AndroidStudioProjects/nmt-zno-exams-multiplayer/docs/plan.md:146).
  - Implementation: `POST /rooms` returns only `{code}`, identity only in `/join`: [docs/planImplementation.md](/Users/anduser/AndroidStudioProjects/nmt-zno-exams-multiplayer/docs/planImplementation.md:548), [docs/planImplementation.md](/Users/anduser/AndroidStudioProjects/nmt-zno-exams-multiplayer/docs/planImplementation.md:593).
- Why this is a bug:
  - UX spec and API behavior diverge.
- Solution:
  - Either:
    - A) make `createRoom` auto-join creator and return identity, or
    - B) explicitly document the two-step flow (`create` then `join`).

### 11) Security rule references socket payloads despite REST architecture
- Severity: `P1`
- Evidence:
  - [docs/plan.md](/Users/anduser/AndroidStudioProjects/nmt-zno-exams-multiplayer/docs/plan.md:224).
- Why this is a bug:
  - Misdirects validation responsibilities.
- Solution:
  - Replace with: validate all REST payloads and all outgoing broadcast payload shapes.

### 12) “Implemented” Phase 3.5 section is claim-only, not actionable
- Severity: `P1`
- Evidence:
  - Section claims features already implemented: [docs/planImplementation.md](/Users/anduser/AndroidStudioProjects/nmt-zno-exams-multiplayer/docs/planImplementation.md:1869).
- Why this is a bug:
  - False confidence; no code templates/steps for agents.
- Solution:
  - Convert each Phase 3.5 item into explicit diffs/snippets, route list, tests, and gate checks.

---

## P2 Issues

### 13) Score update is non-atomic (race risk)
- Severity: `P2`
- Evidence:
  - Read-modify-write score pattern: [docs/planImplementation.md](/Users/anduser/AndroidStudioProjects/nmt-zno-exams-multiplayer/docs/planImplementation.md:351).
- Why this is a bug:
  - Concurrent updates can lose points.
- Solution:
  - Use SQL atomic increment (RPC or `UPDATE ... SET score = score + delta`).

### 14) Subject counts query is inefficient
- Severity: `P2`
- Evidence:
  - Pulls all subject rows and counts in app code: [docs/planImplementation.md](/Users/anduser/AndroidStudioProjects/nmt-zno-exams-multiplayer/docs/planImplementation.md:275).
- Why this is a bug:
  - Unnecessary bandwidth/latency.
- Solution:
  - Use DB aggregation (`GROUP BY subject`) or materialized counts.

### 15) Random question selection loads all subject rows then shuffles in memory
- Severity: `P2`
- Evidence:
  - [docs/planImplementation.md](/Users/anduser/AndroidStudioProjects/nmt-zno-exams-multiplayer/docs/planImplementation.md:256).
- Why this is a bug:
  - Does not scale with dataset growth.
- Solution:
  - Use DB-side random sampling strategy or pre-shuffled pools per subject.

### 16) Potential crash with non-null assertion on missing question mapping
- Severity: `P2`
- Evidence:
  - [docs/planImplementation.md](/Users/anduser/AndroidStudioProjects/nmt-zno-exams-multiplayer/docs/planImplementation.md:849).
- Why this is a bug:
  - If a question is missing/deleted, process can crash.
- Solution:
  - Validate mapping, handle missing IDs gracefully, fail round safely.

### 17) Flutter timer can drift from server-authoritative timer
- Severity: `P2`
- Evidence:
  - Client always starts from 5:00 locally: [docs/planImplementation.md](/Users/anduser/AndroidStudioProjects/nmt-zno-exams-multiplayer/docs/planImplementation.md:1479), [docs/planImplementation.md](/Users/anduser/AndroidStudioProjects/nmt-zno-exams-multiplayer/docs/planImplementation.md:1486).
- Why this is a bug:
  - Reconnects/lag cause timer mismatch UX.
- Solution:
  - Broadcast `roundStartedAt` and `roundDurationMs`; derive remaining time from server timestamps.

### 18) Unsafe null assertions in Quiz reveal path
- Severity: `P2`
- Evidence:
  - Uses `_currentQuestion!` in reveal: [docs/planImplementation.md](/Users/anduser/AndroidStudioProjects/nmt-zno-exams-multiplayer/docs/planImplementation.md:1512).
- Why this is a bug:
  - Out-of-order events can throw.
- Solution:
  - Guard missing question and request room sync snapshot before rendering reveal.

### 19) `RoomState.copyWith` unintentionally clears error message
- Severity: `P2`
- Evidence:
  - `errorMessage: errorMessage` not fallback: [docs/planImplementation.md](/Users/anduser/AndroidStudioProjects/nmt-zno-exams-multiplayer/docs/planImplementation.md:1236).
- Why this is a bug:
  - Any non-error state update drops previous error implicitly.
- Solution:
  - Use tri-state pattern (`bool clearError`, or sentinel wrapper) to control retention/clear explicitly.

### 20) Build/deploy guidance favors runtime TS in production
- Severity: `P2`
- Evidence:
  - Render start command uses `npx tsx src/main.ts`: [docs/planImplementation.md](/Users/anduser/AndroidStudioProjects/nmt-zno-exams-multiplayer/docs/planImplementation.md:1947).
- Why this is a bug:
  - Slower startup and larger runtime attack surface than built JS.
- Solution:
  - Build with `tsc`, deploy `dist/main.js`, pin Node version.

---

## P3 Issues

### 21) Makefile text still refers to MongoDB
- Severity: `P3`
- Evidence:
  - [docs/planImplementation.md](/Users/anduser/AndroidStudioProjects/nmt-zno-exams-multiplayer/docs/planImplementation.md:2055), [docs/planImplementation.md](/Users/anduser/AndroidStudioProjects/nmt-zno-exams-multiplayer/docs/planImplementation.md:2074).
- Why this is a bug:
  - Doc hygiene issue, causes confusion for agents.
- Solution:
  - Replace with Supabase wording everywhere.

### 22) Gate check asks to verify Realtime payload in DevTools Network
- Severity: `P3`
- Evidence:
  - [docs/planImplementation.md](/Users/anduser/AndroidStudioProjects/nmt-zno-exams-multiplayer/docs/planImplementation.md:1863), [docs/planImplementation.md](/Users/anduser/AndroidStudioProjects/nmt-zno-exams-multiplayer/docs/planImplementation.md:2108).
- Why this is a bug:
  - Supabase Realtime broadcast visibility is mostly in websocket frames/app logs, not standard HTTP network entries.
- Solution:
  - Update QA step to inspect websocket frames or instrument app-side payload logging assertions.

### 23) Clean Architecture statement is unclear (“layers split by feature”)
- Severity: `P3`
- Evidence:
  - [docs/plan.md](/Users/anduser/AndroidStudioProjects/nmt-zno-exams-multiplayer/docs/plan.md:46) + folder tree is layer-first not feature-first [docs/plan.md](/Users/anduser/AndroidStudioProjects/nmt-zno-exams-multiplayer/docs/plan.md:108).
- Why this is a bug:
  - Ambiguous architectural guidance.
- Solution:
  - Choose one explicit structure: `features/<feature>/{domain,data,presentation}` or strict global layers.

---

## Recommended Execution Order for Agents
1. Fix `P0` security and identity/session model.
2. Align architecture contracts (`P1`) across both docs.
3. Address backend reliability/performance (`P2` issues 13-16).
4. Fix frontend robustness (`P2` issues 17-19).
5. Clean deployment/docs hygiene (`P2` issue 20 + all `P3`).

## Definition of Done (Docs)
- Both docs describe the same stack, same API contracts, same event model.
- All referenced endpoints are defined in routes/controllers/validators sections.
- Security model is explicit (auth/session/token), not body-trust.
- Gate checks validate real behavior and can be executed without guesswork.
