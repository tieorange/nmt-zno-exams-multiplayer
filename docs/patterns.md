# 🧩 Code Patterns — NMT Quiz Multiplayer

> **For AI agents:** This file contains copy-paste templates for the most common extension tasks. Read the relevant pattern fully before writing any code. Every template is derived from existing code in this repo.

---

## Pattern 1 — Adding a New REST Endpoint (Backend)

This is a 4-step process: validator → controller → route → done.

### Step 1: Add a Zod schema (`backend/src/presentation/validators/requestSchemas.ts`)

```typescript
// Follow existing schemas exactly. playerId is always UUID.
export const MyNewActionSchema = z.object({
  playerId: z.string().uuid(),
  // add other fields here
  myField: z.string().min(1),
});
```

### Step 2: Write the controller function (`backend/src/presentation/controllers/GameController.ts` or `RoomController.ts`)

```typescript
export async function myNewAction(req: Request, res: Response) {
  const requestId = res.locals['requestId'] as string;
  const code = String(req.params.code).toUpperCase();

  // 1. Validate request body
  const parsed = MyNewActionSchema.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({ error: parsed.error.flatten() });
    return;
  }

  // 2. Fetch room (always check existence)
  const room = await getRoom(code);
  if (!room) {
    logger.warn({ event: 'my_action.failed', requestId, roomCode: code, reason: 'room_not_found' });
    res.status(404).json({ error: 'Кімнату не знайдено' });
    return;
  }

  // 3. Authorization checks (creator-only example)
  const players = await getPlayers(code);
  const player = players.find((p) => p.id === parsed.data.playerId);
  if (!player?.is_creator) {
    logger.warn({ event: 'my_action.failed', requestId, roomCode: code, reason: 'not_creator' });
    res.status(403).json({ error: 'Тільки творець може це зробити' });
    return;
  }

  // 4. Business logic (wrap in try/catch if it can throw)
  try {
    await engineMyNewAction(code, parsed.data.playerId);
    logger.info({ event: 'my_action.success', requestId, roomCode: code, outcome: 'success' });
    res.json({ ok: true });
  } catch (err: unknown) {
    const serialized = serializeError(err);
    logger.warn({ event: 'my_action.failed', requestId, roomCode: code, reason: serialized.message });
    res.status(400).json({ error: serialized.message });
  }
}
```

### Step 3: Register the route (`backend/src/presentation/routes/index.ts`)

```typescript
// POST routes go after the matching GET, grouped by resource
router.post('/rooms/:code/my-new-action', validateRoomCode, myNewAction);
```

> `validateRoomCode` middleware is already applied to all `:code` routes and uppercases the code.

### Step 4: Add to `ApiService` (Flutter, `frontend/lib/services/api_service.dart`)

```dart
Future<void> myNewAction(String roomCode, String playerId) {
  final endpoint = '/api/rooms/${roomCode.toUpperCase()}/my-new-action';
  return _traced('ApiService', 'POST', endpoint, (_) async {
    final res = await http.post(
      Uri.parse('$baseUrl$endpoint'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'playerId': playerId}),
    );
    if (res.statusCode != 200) {
      throw Exception('myNewAction failed (${res.statusCode}): ${res.body}');
    }
  });
}
```

---

## Pattern 2 — Adding a New Supabase Broadcast Event

Three steps: emit it in `GameEngine.ts` → declare it in `SupabaseService` → handle it in a cubit.

### Step 1: Emit in `GameEngine.ts`

```typescript
// Use safeBroadcast so a Supabase failure doesn't crash the server
await safeBroadcast(roomCode, 'my:event', {
  someField: 'value',
  anotherField: 42,
});
```

### Step 2: Declare in `SupabaseService` (`frontend/lib/services/supabase_service.dart`)

```dart
// Add to the enum:
enum RealtimeEventType {
  roomState,
  gameStart,
  questionNew,
  roundUpdate,
  roundReveal,
  gameEnd,
  playerDisconnected,
  myEvent,        // ← add here
}

// Add to subscribeToRoom() — chain with ..onBroadcast:
.onBroadcast(
  event: 'my:event',
  callback: _buildCallback(
    roomCode,
    RealtimeEventType.myEvent,
    'my:event',
    extra: (p) => 'someField=${p['someField']}',  // logged in info line
  ),
)
```

### Step 3: Handle in a cubit (e.g. `QuizCubit._handleEvent`)

```dart
void _handleEvent(RealtimeEvent event) {
  switch (event.type) {
    // ... existing cases ...
    case RealtimeEventType.myEvent:
      _handleMyEvent(event.data);
      break;
    default:
      logger.w('[QuizCubit] Unknown event received | type=${event.type}');
      break;
  }
}

void _handleMyEvent(Map<String, dynamic> data) {
  final someField = data['someField'] as String?;
  logger.i({
    'feature': 'QuizCubit',
    'event': 'my_event.received',
    'roomCode': _roomCode,
    'someField': someField,
  });
  // emit new state...
}
```

---

## Pattern 3 — Adding a New Flutter Screen

### Step 1: Create the page file (`frontend/lib/presentation/pages/my_screen.dart`)

```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../cubits/room_cubit/room_cubit.dart';
import '../cubits/quiz_cubit/quiz_cubit.dart';
import '../cubits/quiz_cubit/quiz_state.dart';

class MyScreen extends StatefulWidget {
  final String roomCode;
  const MyScreen({super.key, required this.roomCode});

  @override
  State<MyScreen> createState() => _MyScreenState();
}

class _MyScreenState extends State<MyScreen> {
  @override
  void initState() {
    super.initState();
    // Start polling if this screen needs to detect next-state transitions
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<QuizCubit>().startPolling();
    });
  }

  @override
  Widget build(BuildContext context) {
    final roomCubit = context.read<RoomCubit>();

    // Route guard — bounce to home if player hasn't joined
    if (roomCubit.myPlayerId == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => context.go('/'));
      return const SizedBox.shrink();
    }

    return BlocListener<QuizCubit, QuizState>(
      // Navigate when state transitions happen
      listener: (context, state) {
        if (state is QuizQuestion) {
          context.go('/room/${widget.roomCode}/game');
        }
      },
      child: BlocBuilder<QuizCubit, QuizState>(
        builder: (context, state) {
          return Scaffold(
            backgroundColor: const Color(0xFF0D1117),
            appBar: AppBar(title: const Text('Мій екран')),
            body: _buildBody(context, state, roomCubit),
          );
        },
      ),
    );
  }

  Widget _buildBody(BuildContext context, QuizState state, RoomCubit roomCubit) {
    // Build UI based on state
    return const Center(child: Text('Content here'));
  }
}
```

### Step 2: Register the route (`frontend/lib/config/router.dart`)

```dart
// Add inside the /room/:roomCode subroutes list:
GoRoute(
  path: 'my-screen',
  builder: (context, state) => MyScreen(
    roomCode: state.pathParameters['roomCode']!,
  ),
),
```

Access the route: `context.go('/room/$roomCode/my-screen')`

---

## Pattern 4 — Adding a New Cubit State Variant

### In `quiz_state.dart` (or equivalent state file)

```dart
// Add the class:
class QuizMyNewState extends QuizState {
  final String someField;
  final int? optionalField;

  const QuizMyNewState({
    required this.someField,
    this.optionalField,
  });

  @override
  List<Object?> get props => [someField, optionalField];
}
```

> **Rules:**
> - Extend `QuizState` (or `RoomState` etc.)
> - Add `const` constructor
> - List ALL fields in `props` (drives Equatable's `==`)
> - `copyWith` is only needed if the state is updated frequently (e.g. every second like `QuizQuestion`)

### Emit in the cubit:

```dart
emit(QuizMyNewState(someField: 'value'));
```

### Handle in a `BlocBuilder`:

```dart
BlocBuilder<QuizCubit, QuizState>(
  builder: (context, state) {
    if (state is QuizMyNewState) {
      return MyNewStateWidget(state: state);
    }
    // ... other states
    return const SizedBox.shrink();
  },
)
```

---

## Pattern 5 — Backend Error Handling in Controllers

The standard pattern used across all controllers:

```typescript
// Pattern A: expected business logic error → 400
const room = await getRoom(code);
if (!room) {
  res.status(404).json({ error: 'Кімнату не знайдено' });
  return;
}

// Pattern B: authorization error → 403
if (!player?.is_creator) {
  res.status(403).json({ error: 'Тільки творець може це зробити' });
  return;
}

// Pattern C: service call that throws → wrap in try/catch → 400
try {
  await engineDoSomething(code, playerId);
  res.json({ ok: true });
} catch (err: unknown) {
  const serialized = serializeError(err);
  logger.warn({ event: 'thing.failed', reason: serialized.message });
  res.status(400).json({ error: serialized.message });
}
```

> **Never** use `res.send()` — always use `res.json()`.
> **Always** `return` after sending a response (TypeScript won't warn you otherwise).
> **Always** log before returning an error (at `warn` level for expected errors, `error` for unexpected).

---

## Pattern 6 — Backend Logging (pino)

All logs must be structured objects. **No template strings.**

```typescript
// ✅ Correct — structured object
logger.info({
  event: 'game.round.start',
  roomCode,
  questionIndex,
  questionId: questionDoc.id,
  choicesCount: questionDoc.choices.length,
});

// ✅ Correct — warn with reason field
logger.warn({
  event: 'room.join.rejected',
  requestId,
  roomCode: code,
  reason: 'room_full',
  playerCount: players.length,
  maxPlayers: room.max_players,
  outcome: 'failure',
});

// ✅ Correct — error with serialized error
logger.error({
  event: 'game.broadcast.failed',
  roomCode,
  broadcastEvent: event,
  error: serializeError(err),  // always use serializeError(), not err.message
});

// ❌ Wrong — template strings
logger.info(`Room ${roomCode} started`);
// ❌ Wrong — raw error object
logger.error({ error: err });
```

**Standard field names** (use consistently):
- `event` — dot-separated name (e.g. `game.round.start`)
- `roomCode` — 3-char code
- `playerId` — UUID
- `requestId` — from `res.locals['requestId']`
- `outcome` — `'success'` | `'failure'`
- `reason` — snake_case failure reason

---

## Pattern 7 — Frontend Logging (Flutter logger)

Two valid call styles — both produce the same JSON output:

```dart
// Style A: structured map (preferred for new code)
logger.i({
  'feature': 'QuizCubit',           // class name
  'event': 'question.new.received', // dot-separated, matches BE naming
  'roomCode': _roomCode,
  'questionId': _currentQuestion!.id,
  'questionIndex': _questionIndex,
});

// Style B: string (still valid, parsed by StructuredLogPrinter)
logger.i('[QuizCubit] nextQuestion | roomCode=$_roomCode');

// Error logs: always include stackTrace
logger.e(
  {
    'feature': 'QuizCubit',
    'event': 'quiz.submit_answer.failed',
    'roomCode': _roomCode,
    'error': e.toString(),
    'currentState': state.runtimeType.toString(),  // helpful context
  },
  error: e,
  stackTrace: st,
);
```

> **Levels:** `logger.d()` = debug (polling noise), `logger.i()` = info (normal flow), `logger.w()` = warn (unexpected but recoverable), `logger.e()` = error (with stackTrace).

---

## Pattern 8 — Flutter Either<Failure, T> Error Handling

Used in services (not cubits — cubits use try/catch directly).

```dart
// In a service method (if it uses fpdart):
Future<Either<Failure, MyData>> fetchSomething() async {
  try {
    final result = await apiService.getSomething();
    return Right(MyData.fromJson(result));
  } on SocketException {
    return Left(NetworkFailure('Немає з\'єднання з інтернетом'));
  } catch (e) {
    return Left(ServerFailure(e.toString()));
  }
}

// In a cubit consuming the Either:
final result = await myService.fetchSomething();
result.fold(
  (failure) => emit(MyErrorState(failure.message)),
  (data) => emit(MyLoadedState(data)),
);
```

> **Note:** The current cubits (RoomCubit, QuizCubit) mostly use direct try/catch rather than Either, since they call `ApiService` methods that throw exceptions. Use Either for any new **repository or service layer** code, not for cubit event handlers.

---

## Pattern 9 — Adding a New GameEngine Function

```typescript
// In GameEngine.ts — export only if called from a controller
export async function myEngineAction(roomCode: string, playerId?: string): Promise<void> {
  // 1. Validate state
  const state = roundState.get(roomCode);
  if (!state) throw new Error('Раунд не активний');

  // 2. Do work (modify in-memory state first, then DB, then broadcast)
  state.answers.set(playerId ?? '', 99); // example mutation

  await updateRoom(roomCode, { current_question_index: 1 }); // example DB write

  // 3. Broadcast result
  await safeBroadcast(roomCode, 'my:event', { field: 'value' });

  logger.info({ event: 'my_engine.action', roomCode, playerId });
}
```

> **Order of operations:** in-memory mutation → DB write → broadcast. This ensures the state is consistent if the broadcast fails.

---

## Pattern 10 — Lobby Polling (RoomLobbyScreen pattern)

For screens that need to detect state changes while in `waiting` status:

```dart
// In initState or after joinRoom completes:
Timer.periodic(const Duration(seconds: 1), (timer) {
  if (!mounted) { timer.cancel(); return; }
  final status = context.read<RoomCubit>().state.status;
  if (status != RoomStatus.waiting) {
    timer.cancel();
    return;
  }
  context.read<RoomCubit>().syncRoomState();
});
```

For in-game state transitions, use `QuizCubit.startPolling()` instead (it handles all three scenarios: reveal, next question, game restart).

---

## Common Mistakes to Avoid

### Backend
- ❌ `await broadcastToRoom(...)` directly — use `await safeBroadcast(...)` which won't crash on Supabase errors
- ❌ Sending `correct_answer_index` in any broadcast — strip it before any client-facing payload
- ❌ Forgetting `return` after `res.status(4xx).json(...)` — controller keeps executing
- ❌ Using `channel.send()` for broadcasts — use `channel.httpSend()` (set in `supabase.ts`)
- ❌ Changing `moduleResolution` in `tsconfig.json` — must stay `"bundler"` for pino v8

### Frontend
- ❌ Calling `quizCubit.setContext()` after the first game event arrives — it's set via the `roomCubit.stream.listen` coordinator in `main.dart`, not manually
- ❌ `withOpacity(double)` — use `withAlpha(int)` instead (withOpacity is deprecated)
- ❌ Adding Supabase channel `.onBroadcast()` calls after `.subscribe()` — must be before
- ❌ Forgetting to call `startPolling()` on a new game screen — events are missed on slow networks
- ❌ Putting identity state (`myPlayerId`, `myIsCreator`) in `RoomState` — it lives as public properties on `RoomCubit` directly
