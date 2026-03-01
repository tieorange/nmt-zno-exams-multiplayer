# API Endpoints Bugs & Improvements (Plan)

> **For AI Agents:** This document outlines bugs, edge cases, and missing features discovered while testing the backend REST API endpoints. Your objective is to fix these issues.

## 🚨 P0 - Critical Issues (Server Crashing / Blocking)

### 1) Backend Terminal Freezing / Ghost Processes
- **Symptom:** Running `npm run dev` (which triggers `tsx watch`) often hangs the port or freezes the terminal, leaving ghost `node` processes bound to port 3000. `curl` requests then time out after 10 seconds.
- **Cause:** `tsx watch` does not handle unhandled promise rejections cleanly, and our controllers (like `startGame`) don't await `engineStartGame` inside a `try/catch`. 
- **Agent Fix:**
  1. Add a global `process.on('unhandledRejection')` and `process.on('uncaughtException')` handler in `main.ts` that logs the error and exits cleanly, so `tsx watch` can restart the process instead of hanging.
  2. Implement a global async error-handling middleware (`const asyncHandler = (fn) => (req, res, next) => Promise.resolve(fn(req, res, next)).catch(next);`) and wrap all controller functions.

### 2) `GET /api/subjects` Returns `questionCount: 0` for some subjects
- **Symptom:** `ukrainian_language` and `math` returned `0` even though the seed script says it loaded thousands of questions.
- **Cause:** The `getSubjectCounts` in `QuestionRepository.ts` fetches *all* rows locally into memory to count them, but Supabase SDK limits `select()` results to 1,000 rows by default without pagination. Thus, subjects listed later in the DB simply aren't fetched, resulting in `0`.
- **Agent Fix:** 
  - Change `getSubjectCounts()` to use a true SQL aggregation. Unfortunately, the JS SDK doesn't have a simple `GROUP BY`.
  - Fix: EITHER write a Supabase RPC (`create function get_subject_counts()`) OR do 4 parallel `select('id', { count: 'exact', head: true }).eq('subject', s)` queries, one for each subject to get exact counts without downloading rows.

### 3) Disconnect Sweep & Restart Memory Leaks (Active Games Orphaned)
- **Symptom:** If the Node process restarts (which `tsx watch` does automatically on file changes), all active `roundState`, `sessions`, and `pings` maps are permanently lost.
- **Agent Fix:**
  - Game logic must tolerate process restarts.
  - Temporarily, for development: ensure `startGame` and `joinRoom` clear out any hanging DB records if the room is found in an impossible state.
  - Fix the `PlayerManager.ts` cleanup: If the timer fires and the room no longer exists in DB, it crashes because of missing error handling.

---

## 🛑 P1 - High Priority Logic & Security Flaws

### 4) Re-Join Session Bypass (Game State Override)
- **Symptom:** A player with an old `sessionId` can call `POST /api/rooms/:code/join` and successfully rejoin a room *even if the game has already started*.
- **Cause:** In `RoomController.ts` lines 73-85, the `sessionId` rejoin block successfully returns the player and `return;`'s **before** reaching the game status check (`if (room.status !== 'waiting') { res.status(400) }`).
- **Agent Fix:** 
  - Move the `room.status !== 'waiting'` check to the top of `joinRoom`, **except** if they are rejoining an active game (which *should* be allowed, but handled correctly without breaking state). Actually, rejoining an active game is intended (to recover from refresh). BUT they shouldn't trigger `addPlayer`. Make sure the logic explicitly handles "Rejoining an active game is OK, joining as a NEW player in an active game is blocked."

### 5) Heartbeat `roomCode` Ignored (Cross-Room Pings)
- **Symptom:** A player can send `POST /api/rooms/ANY_CODE/heartbeat` and keep themselves alive in a completely different room.
- **Cause:** `pingHeartbeat(playerId)` only does a lookup in `pings.get(playerId)`. The `roomCode` from the URL parameter is ignored.
- **Agent Fix:** 
  - In `RoomController.heartbeat`, fetch the player's session and verify `session.roomCode === code`. Reject with 400 if it doesn't match.

### 6) Silent 200 OK on Ignored Answers
- **Symptom:** Sending an answer with a wrong `questionId` or `answerIndex > choices.length` returns `200 { ok: true }`. The `GameEngine.submitAnswer` simply `return;`s silently.
- **Cause:** No error response mechanism from the engine to the controller.
- **Agent Fix:** 
  - Change `submitAnswer` to return a `boolean` or throw an error (e.g., `throw new Error('Invalid question ID')`). 
  - In `GameController`, catch the error and send a 400 status instead of always sending 200.

---

## ⚠️ P2 - Medium Priority Fixes

### 7) `answerIndex` Validation Missing Bounds Check on Controller
- **Symptom:** Zod validates `0-4` (up to 5 choices), but a question might have only 2 choices. `GameEngine` protects against it (line 154), but it fails silently.
- **Agent Fix:** 
  - Ensure the client receives a 400 error (as fixed in Bug 6) when submitting `answerIndex: 4` for a boolean question.

### 8) `isCreator` Missing logic in REST `joinRoom` Re-Join
- **Symptom:** When rejoining via session, `isCreator` is returned correctly in HTTP response, but the player isn't broadcast back to the room if they missed an event.
- **Agent Fix:** 
  - On rejoin, broadcast `room:state` again to notify others if their online status changed, or just let them receive the current state in the HTTP response. Ensure they get the *current* `currentQuestionIndex` and time so the frontend can catch up.

### 9) Score Never Resets on `restartGame`
- **Symptom:** `restartGame` brings everyone back to question 0, but their scores continue from the previous game.
- **Cause:** `restartGame` does not zero out player scores in the database.
- **Agent Fix:** 
  - In `GameEngine.restartGame`, add a call to `update players set score = 0 where room_code = X`.

---

## ✅ Recommended Execution Order for the Next AI Agent

1. **Fix Bug #1 First:** Wrap Express routes in `asyncHandler` and add global `unhandledRejection` so the terminal stops breaking.
2. **Fix Bug #2:** Rewrite `getSubjectCounts` in `QuestionRepository.ts` using single queries with `{ count: 'exact', head: true }` so it doesn't try to download 3,595 rows and hit the 1k limit.
3. **Fix Bug #6 & #7:** Throw explicit errors from `GameEngine.ts` and catch them in `GameController.ts`.
4. **Fix Bug #4 & #5:** Fix the `RoomController.ts` guards for join and heartbeat.
5. **Fix Bug #9:** Add score zeroing to `restartGame`.
