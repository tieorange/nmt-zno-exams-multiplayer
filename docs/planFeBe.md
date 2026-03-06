# FE/BE Integration Review Plan

## Scope

Reviewed:

- `docs/plan.md`
- `docs/planImplementation.md`
- backend room/game/player lifecycle
- frontend API, realtime, cubits, and page routing

## Verdict

The happy path is mostly wired correctly:

- room creation and join flow are aligned
- backend remains the game authority
- frontend has reasonable realtime + polling fallbacks
- security around `correct_answer_index` is handled correctly

The weak part is recovery behavior:

- disconnect / reconnect
- creator reassignment
- reveal-window recovery
- missed realtime events

Those paths still have contract gaps and a couple of real races.

## Priority Summary

| Priority | Issue |
|---|---|
| P1 | FE removes disconnected players from local room state even when BE intentionally keeps them in the game |
| P1 | Rejoin during the reveal window can leave the player stuck on a loading spinner |
| P1 | Backend broadcasts `question:new` before the round is actually ready to accept answers |
| P2 | Creator reassignment is not propagated to FE ownership state |
| P2 | Room is deleted as soon as all players are offline, which breaks reconnect expectations |
| P3 | Docs describe a broader transport contract than the code actually sends |

---

## 1. P1: FE removes players that BE only marked as offline

### Symptom

During `playing` or `finished`, a disconnected player disappears from:

- gameplay chips
- reveal scoreboard list
- any UI derived from `RoomCubit.state.players`

This is wrong because backend explicitly keeps those players in DB to preserve score and rejoin support.

### Evidence

- Backend keeps players in DB outside lobby: `backend/src/services/PlayerManager.ts:66`
- Backend then broadcasts `room:state` with the full player list: `backend/src/services/PlayerManager.ts:100`
- Backend also sends a separate `player:disconnected` event: `backend/src/services/PlayerManager.ts:112`
- Frontend handles that event by removing the player from local state: `frontend/lib/presentation/cubits/room_cubit/room_cubit.dart:183`

Because `room:state` is broadcast before `player:disconnected`, FE ends up with the wrong final state.

### Root Cause

The BE event means "offline", but the FE interprets it as "remove from room".

### Fix Plan

#### Backend

1. Decide on one contract:
   - preferred: `room:state` is the source of truth for membership
   - `player:disconnected` is only a hint/toast event
2. Extend player payloads with `isOnline` if the UI needs to show offline state.
3. Return the same shape from:
   - `GET /api/rooms/:code`
   - `POST /api/rooms/:code/join`
   - `room:state`

#### Frontend

1. Stop removing the player from `state.players` on `player:disconnected`.
2. If `isOnline` is added, update the UI to show offline status instead of deleting the player.
3. Keep `room:state` as the only membership source.

#### Tests

1. Disconnect a non-creator during `playing`.
2. Verify the player still exists in FE room state.
3. Verify score/reveal screens still show that player.

### Acceptance Criteria

- A disconnected player remains visible in room/game/results state.
- FE can visually mark offline state without corrupting membership.

---

## 2. P1: Rejoin during reveal window can get stuck forever

### Symptom

If a player reloads or rejoins after `round:reveal` fired but before the next question starts, they can land in `/game` and stay on a spinner until the creator advances or the fallback timer fires.

### Evidence

- `getRoomState()` only exposes `currentQuestion`, which is `null` after `roundState` is deleted: `backend/src/presentation/controllers/RoomController.ts:63`
- `pendingReveal` exists only in `/round-state`: `backend/src/presentation/controllers/RoomController.ts:83`
- reveal cache does not include question text/choices, only reveal metadata: `backend/src/services/GameEngine.ts:280`
- FE recovery only bootstraps from `currentQuestion`: `frontend/lib/presentation/cubits/quiz_cubit/quiz_cubit.dart:113`
- polling stops immediately for `QuizInitial`: `frontend/lib/presentation/cubits/quiz_cubit/quiz_cubit.dart:258`
- reveal handling is impossible without `_currentQuestion`: `frontend/lib/presentation/cubits/quiz_cubit/quiz_cubit.dart:364`

### Root Cause

The backend exposes two partial recovery contracts:

- active-round recovery via `currentQuestion`
- reveal recovery via `pendingReveal`

But the reveal recovery payload is missing the question snapshot, and the FE only knows how to bootstrap a question, not a reveal.

### Fix Plan

#### Backend

1. Extend reveal recovery payload to include the client question snapshot:
   - `question: { id, subject, text, choices, questionIndex, totalQuestions }`
2. Return reveal recovery from at least one of:
   - `GET /api/rooms/:code`
   - `POST /api/rooms/:code/join`
   - `GET /api/rooms/:code/round-state`
3. Make recovery contract explicit:
   - active round => `currentQuestion`
   - reveal window => `pendingReveal` with `question`

#### Frontend

1. Add `bootstrapRevealFromSnapshot(...)` in `QuizCubit`.
2. When joining/syncing a `playing` room:
   - if `currentQuestion != null`, bootstrap question
   - else if `pendingReveal != null`, bootstrap reveal
3. Do not stop polling from `QuizInitial` while the room is `playing`; keep polling until one recoverable state is found.

#### Tests

1. Join room during active question -> FE restores `QuizQuestion`.
2. Join room during reveal window -> FE restores `QuizReveal`.
3. Miss both realtime `question:new` and `round:reveal` -> FE still recovers through REST.

### Acceptance Criteria

- Reload during reveal always lands on reveal UI, not a spinner.
- FE can recover both active-round and reveal states without relying on event order.

---

## 3. P1: Backend broadcasts `question:new` before answer submission is valid

### Symptom

A very fast client can receive `question:new`, tap an answer immediately, and get:

- `400 Гру не знайдено або раунд ще не почався`

### Evidence

- Backend sends `question:new` first: `backend/src/services/GameEngine.ts:152`
- Backend only creates `roundState` after that: `backend/src/services/GameEngine.ts:160`
- `submitAnswer()` rejects when `roundState` is absent: `backend/src/services/GameEngine.ts:169`

### Root Cause

The room becomes visible to FE before the backend round state is ready.

### Fix Plan

#### Backend

1. In `startRound()` create:
   - answers map
   - timer
   - `roundState`
   before calling `safeBroadcast('question:new', ...)`
2. Keep DB `round_started_at` update before broadcast.
3. Only then emit `question:new`.

#### Frontend

1. No major FE change required.
2. Optionally keep existing optimistic retry behavior, but it should no longer be needed for this race.

#### Tests

1. Start a round.
2. Submit an answer immediately after first `question:new`.
3. Verify no transient 400 is possible.

### Acceptance Criteria

- Once FE sees `question:new`, the backend accepts answers immediately.

---

## 4. P2: Creator reassignment is not reflected in FE ownership state

### Symptom

If the creator disconnects and backend reassigns creator to another player:

- lobby start button can stay wrong
- results restart button can stay wrong

### Evidence

- Backend reassigns creator in DB: `backend/src/services/PlayerManager.ts:89`
- FE stores creator ownership in mutable field `myIsCreator`: `frontend/lib/presentation/cubits/room_cubit/room_cubit.dart:19`
- `myIsCreator` is set only on join and reset on leave: `frontend/lib/presentation/cubits/room_cubit/room_cubit.dart:47`, `frontend/lib/presentation/cubits/room_cubit/room_cubit.dart:332`
- `room:state` processing never recalculates it: `frontend/lib/presentation/cubits/room_cubit/room_cubit.dart:298`
- lobby and results rely on the stale field:
  - `frontend/lib/presentation/pages/room_lobby_screen.dart:374`
  - `frontend/lib/presentation/pages/results_screen.dart:87`

### Root Cause

Ownership is stored separately from the source-of-truth player list and is not re-derived after BE broadcasts.

### Fix Plan

#### Frontend

1. Recompute `myIsCreator` on every:
   - `joinRoom()`
   - `syncRoomState()`
   - `room:state`
2. Better: remove the mutable field entirely and derive ownership from:
   - `myPlayerId`
   - `state.players`
3. Update screens to use derived ownership, not cached ownership.

#### Backend

1. No protocol change required if `room:state` remains authoritative.
2. If adding `isOnline`, include it here too.

#### Tests

1. Creator disconnects during waiting.
2. New creator sees start button.
3. New creator sees restart button after game end.

### Acceptance Criteria

- FE ownership controls always match the latest backend creator assignment.

---

## 5. P2: Room deletion when everyone is offline breaks reconnect flow

### Symptom

If all players disconnect for more than the heartbeat timeout, the room is deleted immediately. Rejoin becomes impossible even though the app otherwise claims to support reconnect during active/finished games.

### Evidence

- BE keeps disconnected players in DB during active game: `backend/src/services/PlayerManager.ts:66`
- but deletes the room when `onlinePlayers.length === 0`: `backend/src/services/PlayerManager.ts:78`

### Root Cause

The disconnect policy mixes two different intents:

- lobby cleanup
- active game recovery

### Fix Plan

#### Backend

1. Only delete immediately when `room.status == 'waiting'`.
2. For `playing` and `finished`:
   - keep the room
   - keep players
   - rely on existing end-game cleanup TTL or introduce a dedicated reconnect TTL
3. Optionally broadcast a room-empty/offline event if useful for UI.

#### Frontend

1. Treat temporary 404 after reconnect as unexpected once this fix is in place.
2. Optionally show "all players offline" if BE exposes such a state.

#### Tests

1. Start a game with 2 players.
2. Let both go offline.
3. Reopen one client within reconnect TTL.
4. Verify room and scores are still there.

### Acceptance Criteria

- Active or recently finished rooms survive temporary total disconnects.

---

## 6. P3: Docs drift from the real transport contract

### Symptom

The docs imply payloads and coordinator behavior that are not exactly what the code does. This is likely to send future AI agents in the wrong direction.

### Evidence

- `docs/plan.md` says `question:new` may include `questionIndex`, `totalQuestions`, `roundStartedAt`, `timerMs`: `docs/plan.md:208`
- actual broadcast only sends `{ id, subject, text, choices }`: `backend/src/services/GameEngine.ts:143`
- `docs/planImplementation.md` shows a `main.dart` coordinator using `state.myPlayerId`, `hasPendingSnapshot`, and `isActiveGameState`: `docs/planImplementation.md:203`
- actual code uses `roomCubit.myPlayerId`, `consumePendingSnapshot()`, and explicit type checks: `frontend/lib/main.dart:59`

### Root Cause

The recovery model evolved but the docs were not updated with the final runtime contract.

### Fix Plan

1. Update docs so they distinguish:
   - realtime `question:new`
   - room snapshot `currentQuestion`
   - reveal recovery payload
2. Document which fields are guaranteed on each transport.
3. Document creator reassignment and offline-player semantics explicitly.

### Acceptance Criteria

- A new agent can implement fixes from the docs without first reverse-engineering the runtime behavior.

---

## Recommended Execution Order

1. Fix the transport contract for reconnect/reveal recovery.
2. Fix FE membership handling for disconnected players.
3. Fix creator derivation on FE.
4. Fix `question:new` ordering race on BE.
5. Relax room deletion policy for active/finished rooms.
6. Update docs after code is merged.

## Recommended Contract Shape

Use one normalized room snapshot shape everywhere:

```json
{
  "code": "A9X",
  "status": "playing",
  "players": [
    {
      "id": "uuid",
      "name": "Player",
      "color": "#4ECDC4",
      "score": 20,
      "isCreator": false,
      "isOnline": true
    }
  ],
  "activeRound": {
    "question": {
      "id": "q1",
      "subject": "history",
      "text": "...",
      "choices": ["A", "B", "C", "D"],
      "questionIndex": 2,
      "totalQuestions": 5,
      "roundStartedAt": "2026-03-06T10:00:00.000Z",
      "timerMs": 300000
    },
    "playerAnswers": {
      "player-1": 2,
      "player-2": null
    }
  },
  "pendingReveal": {
    "question": {
      "id": "q1",
      "subject": "history",
      "text": "...",
      "choices": ["A", "B", "C", "D"],
      "questionIndex": 2,
      "totalQuestions": 5
    },
    "correctIndex": 2,
    "playerAnswers": {
      "player-1": 2,
      "player-2": null
    },
    "scores": {
      "player-1": 20,
      "player-2": 10
    },
    "scoreDeltas": {
      "player-1": 10,
      "player-2": 0
    }
  }
}
```

That removes most of the current edge-case branching from the frontend.
