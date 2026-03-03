# Logging Upgrade Plan (FE + BE) for AI Debugging

## Goal
Make backend and frontend logs detailed, structured, and copy-paste-friendly for AI agents so production/dev bugs can be diagnosed quickly.

## Copy-Paste Prompt for AI Agent
```md
You are working in `/Users/anduser/AndroidStudioProjects/nmt-zno-exams-multiplayer`.

Implement a full logging upgrade for backend (`/backend`) and frontend (`/frontend`) with these requirements:

### Project constraints
- Do NOT modify `/data-set` (read-only).
- Keep architecture clean by feature/layer.
- UI text remains Ukrainian; code/comments/log fields remain English.
- Preserve current game behavior and API contracts.
- Security rule: never expose `correct_answer_index` to clients.

### Main objective
When a bug happens, logs should be easy to copy to an AI and should contain enough context to reproduce root cause without extra back-and-forth.

### Deliverables
1. Backend structured logging improvements.
2. Frontend structured logging improvements.
3. Clear incident log format examples.
4. Validation via type/analyze checks.

---

## 1) Backend logging tasks (Node.js + Express + pino)

### A. Standard log shape
Every backend log entry should be structured with stable keys where applicable:
- `ts` (ISO timestamp)
- `level`
- `service` (`backend`)
- `event` (machine-friendly event name, e.g. `room.joined`, `http.request.started`)
- `requestId`
- `roomCode`
- `playerId`
- `sessionId`
- `statusCode`
- `durationMs`
- `outcome` (`success`/`failure`)
- `error` (object: `name`, `message`, `stack`, `cause`)
- `context` (additional fields)

### B. Request lifecycle tracing
- Add request-id middleware (`x-request-id` support + generate if absent).
- Log request start and request finish with same `requestId`.
- Include method/path/query/params/body keys (sanitize sensitive values).
- On errors, include request context + serialized error object + stack trace.

### C. Domain events
Upgrade logs in:
- `RoomController`
- `GameController`
- `GameEngine`
- `PlayerManager`
- `config/supabase.ts`

Use explicit event names and context fields instead of only free-text strings.

### D. Error serialization
Create helper to safely serialize unknown errors:
- Handles `Error`, non-Error throws, nested causes.
- Never crashes logger on circular structures.

---

## 2) Frontend logging tasks (Flutter Web + logger package)

### A. JSON/structured output
Create a frontend logging wrapper/printer so each log line has:
- `ts`
- `level`
- `service` (`frontend`)
- `feature` (e.g. `ApiService`, `RoomCubit`, `QuizCubit`)
- `event`
- `requestId` (for HTTP calls)
- `roomCode`
- `playerId`
- `durationMs`
- `outcome`
- `error` + `stackTrace`
- `context`

### B. API request tracing
In `ApiService`:
- Generate per-request `requestId`.
- Log `request.start` and `request.finish`.
- Include endpoint, method, status code, duration.
- On failure, log body snippet + stack trace.

### C. Realtime diagnostics
In `SupabaseService`:
- Log subscribe/unsubscribe lifecycle.
- Log every received broadcast with event name + payload keys + room code.
- Log malformed payloads and security anomalies with full context.

### D. Cubit error observability
In `RoomCubit`, `QuizCubit`, `GameCubit`:
- Ensure `catch (e, st)` is used where useful.
- Include current state context in error logs (room status, question index, etc.).

---

## 3) Redaction and safety

- Redact or avoid sensitive keys: `authorization`, `token`, `secret`, `key`.
- Keep payload previews truncated to safe length.
- Never leak server-only secrets.

---

## 4) Acceptance criteria

Consider task done only if:
1. A failed API call can be traced end-to-end via `requestId` in backend logs.
2. Frontend logs contain enough context to identify exact failing action and app state.
3. All major game flow events are logged with explicit event names.
4. Errors include stack traces in both FE and BE.
5. No gameplay regression and no API contract change.
6. Security rule about `correct_answer_index` remains intact.

---

## 5) Validation commands

Run and report:
- `cd backend && npm run typecheck`
- `cd frontend && flutter analyze`

If a command cannot run, explain why and what blocks it.

---

## 6) Final report format

Return:
1. Files changed.
2. What was added per file.
3. Sample backend log line.
4. Sample frontend log line.
5. Validation results.
6. Follow-up recommendations (optional).
```

## Suggested Rollout Order
1. Backend request-id + lifecycle logs.
2. Backend domain/service structured events.
3. Frontend structured logger wrapper.
4. Frontend API/realtime/cubit instrumentation.
5. Type/analyze validation and sample logs.

## Notes
- Keep logs actionable for AI: event names + IDs + timing + state snapshot.
- Prefer structured fields over long human-only strings.
- Keep log volume reasonable by using `debug` for noisy payload logs.
