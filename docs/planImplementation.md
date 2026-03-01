# 🛠️ NMT Quiz — Implementation Guide

> **For AI agents (Claude Code):** This file is your complete execution guide. Follow phases in strict order. Never skip a gate check. If a gate fails, fix the issue before moving to the next phase.
>
> For architecture decisions and package versions, see [`plan.md`](./plan.md).
> For dataset docs, see [`data-set/README.md`](./data-set/README.md).

---

## 🏁 Starting State (read before doing anything)

```
nmt-zno-exams-multiplayer/        ← you are here (git repo)
├── data-set/                     ← ALREADY DONE, do not modify
│   ├── types.ts                  ← canonical TypeScript types
│   └── questions/all.json        ← 3,595 questions, ready to seed
├── plan.md                       ← architecture decisions
├── planImplementation.md         ← this file
└── (nothing else)                ← no backend/, no frontend/ yet
```

**What you must do:**
1. Create `backend/` — Node.js + Express + Socket.io + MongoDB
2. Create `frontend/` — Flutter Web app
3. Do them in order: Phase 0 → 1 → 2 → 3 → 4

**Never modify `data-set/`.**
**Always run gate checks before advancing to the next phase.**
**Working directory for all commands = repo root unless stated otherwise.**

---

## Phase 0 — Scaffold Both Projects

> **Before writing any code:** Set up your Supabase project (free tier at [supabase.com](https://supabase.com)), then configure the MCP server so the AI agent can manage your DB directly.

### 0.0 Supabase MCP Setup (do this first)

The Supabase MCP server lets Claude Code run SQL, inspect schemas, and seed the DB without leaving the terminal.

**Step 1 — Get credentials from Supabase dashboard:**
- Project ref: from `https://supabase.com/dashboard/project/[ref]` URL
- Personal access token: `https://supabase.com/dashboard/account/tokens`
- Service role key: Project → Settings → API → `service_role` (secret)
- Anon key: Project → Settings → API → `anon` (public)
- Project URL: Project → Settings → API → Project URL

**Step 2 — Add MCP server:**
```bash
# From repo root — add Supabase MCP to this project
claude mcp add supabase -- npx -y @supabase/mcp-server-supabase@latest \
  --project-ref YOUR_PROJECT_REF \
  --read-only false
```
Set env var `SUPABASE_ACCESS_TOKEN=your-personal-access-token` in your shell or `.zshrc`.

**Step 3 — Create tables via MCP:**
Once the MCP server is active in a Claude Code session, the AI agent can run the SQL from `plan.md` → "Supabase PostgreSQL Tables" section directly. No need to open the Supabase SQL editor manually.

---

### 0.1 Backend

```bash
mkdir backend && cd backend
npm init -y
npm install express @supabase/supabase-js nanoid zod pino pino-pretty cors helmet express-rate-limit dotenv uuid
npm install -D typescript tsx @types/node @types/express @types/cors @types/uuid
npx tsc --init
```

**`tsconfig.json`** — replace the generated one with:
```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "NodeNext",
    "moduleResolution": "nodenext",
    "rootDir": "src",
    "outDir": "dist",
    "strict": true,
    "esModuleInterop": true,
    "resolveJsonModule": true,
    "skipLibCheck": true
  },
  "include": ["src"]
}
```

**`package.json`** — merge these fields into the generated file (critical: `"type": "module"` enables ESM imports):
```json
{
  "type": "module",
  "scripts": {
    "dev": "tsx watch src/main.ts",
    "build": "tsc",
    "start": "node dist/main.js",
    "seed": "tsx src/scripts/seed.ts",
    "typecheck": "tsc --noEmit"
  }
}
```

**`backend/.env.example`**:
```
PORT=3000
SUPABASE_URL=https://your-project-ref.supabase.co
SUPABASE_SERVICE_KEY=your-service-role-key-here
SUPABASE_ANON_KEY=your-anon-key-here
CORS_ORIGIN=http://localhost:5000
NODE_ENV=development
LOG_LEVEL=info
```

> **⚠️ Before running any backend command:** copy and fill in your `.env` file:
> ```bash
> cp .env.example .env
> # Edit .env → set SUPABASE_URL and SUPABASE_SERVICE_KEY from your Supabase project
> # Project → Settings → API → Project URL + service_role key
> # Without this, the server crashes on startup with "SUPABASE_URL missing"
> ```

Create folder structure:
```bash
mkdir -p src/{domain/{entities,repositories,exceptions},data/{models,repositories},services,presentation/{handlers,controllers,validators,middlewares,routes},config,scripts}
```

### 0.2 Frontend

```bash
cd ..
flutter create --platforms web frontend
cd frontend
flutter pub add flutter_bloc fpdart go_router supabase_flutter flutter_animate percent_indicator confetti logger equatable url_launcher shadcn_flutter http
```

Create folder structure:
```bash
mkdir -p lib/{config,core,services,data/{models,repositories},domain/{entities,usecases},presentation/{cubits/{room_cubit,quiz_cubit,game_cubit},pages,widgets}}
```

---

### ✅ Phase 0 Gate Check

Run these before moving on. All must pass:

```bash
# backend folder structure exists
ls backend/src/domain backend/src/data backend/src/services backend/src/presentation backend/src/config backend/src/scripts

# flutter project was created
ls frontend/lib/main.dart frontend/pubspec.yaml frontend/web/index.html

# flutter pub get succeeded (packages installed)
cat frontend/pubspec.lock | grep flutter_bloc
cat frontend/pubspec.lock | grep shadcn_flutter
cat frontend/pubspec.lock | grep supabase_flutter
cat frontend/pubspec.lock | grep '"http"'
```

If any command fails, fix it before continuing.

---

## Phase 1 — Backend Foundation

### 1.1 Logger

**`src/config/logger.ts`**:
```typescript
import pino from 'pino';

export const logger = pino({
  level: process.env.LOG_LEVEL || 'info',
  transport: process.env.NODE_ENV !== 'production'
    ? {
        target: 'pino-pretty',
        options: { colorize: true, translateTime: 'SYS:standard', ignore: 'pid,hostname' },
      }
    : undefined,
});
```

### 1.2 Types (copy from dataset)

```bash
cp ../data-set/types.ts src/domain/types.ts
```

These are the canonical types — `Question`, `ClientQuestion`, `QuestionSubject`, `SUBJECTS`, etc.

### 1.3 Supabase Client

**`src/config/supabase.ts`**:
```typescript
import { createClient } from '@supabase/supabase-js';
import { logger } from './logger.js';

const url = process.env.SUPABASE_URL;
const key = process.env.SUPABASE_SERVICE_KEY;

if (!url || !key) {
  logger.error('[Supabase] SUPABASE_URL or SUPABASE_SERVICE_KEY missing in .env');
  process.exit(1);
}

// Service-role client — full DB access, bypasses RLS. NEVER expose this key to clients.
export const supabase = createClient(url, key, {
  auth: { persistSession: false },
});

logger.info('[Supabase] Client initialized');

// Broadcast an event to all Supabase Realtime subscribers of a room channel.
// Uses the REST broadcast endpoint — works from Node.js without subscribing to the channel.
export async function broadcastToRoom(
  roomCode: string,
  event: string,
  payload: unknown,
): Promise<void> {
  const res = await fetch(`${url}/realtime/v1/api/broadcast`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${key}`,
      'apikey': key,
    },
    body: JSON.stringify({
      messages: [{ topic: `room:${roomCode}`, event, payload }],
    }),
  });
  if (!res.ok) {
    throw new Error(`[Supabase] broadcastToRoom failed | event=${event} status=${res.status} body=${await res.text()}`);
  }
}
```

### 1.4 Supabase Repository Helpers

Replace Mongoose models with typed Supabase query functions.

**`src/data/repositories/QuestionRepository.ts`**:
```typescript
import { supabase } from '../../config/supabase.js';

export interface Question {
  id: string;
  subject: string;
  text: string;
  choices: string[];
  correct_answer_index: number;
  exam_type: string;
}

export async function getRandomQuestions(subject: string, count: number): Promise<Question[]> {
  const { data, error } = await supabase
    .from('questions')
    .select('id, subject, text, choices, correct_answer_index, exam_type')
    .eq('subject', subject);
  if (error) throw new Error(`[QuestionRepo] getRandomQuestions failed: ${error.message}`);
  const shuffled = (data ?? []).sort(() => Math.random() - 0.5);
  return shuffled.slice(0, count);
}

export async function getQuestionsByIds(ids: string[]): Promise<Question[]> {
  const { data, error } = await supabase
    .from('questions')
    .select('id, subject, text, choices, correct_answer_index, exam_type')
    .in('id', ids);
  if (error) throw new Error(`[QuestionRepo] getQuestionsByIds failed: ${error.message}`);
  return data ?? [];
}

export async function getSubjectCounts(): Promise<Record<string, number>> {
  const { data, error } = await supabase
    .from('questions')
    .select('subject');
  if (error) throw new Error(`[QuestionRepo] getSubjectCounts failed: ${error.message}`);
  const counts: Record<string, number> = {};
  for (const row of data ?? []) counts[row.subject] = (counts[row.subject] ?? 0) + 1;
  return counts;
}
```

**`src/data/repositories/RoomRepository.ts`**:
```typescript
import { supabase } from '../../config/supabase.js';

export interface Room {
  code: string;
  subject: string;
  status: 'waiting' | 'playing' | 'finished';
  max_players: number;
  question_ids: string[];
  current_question_index: number;
  round_started_at: string | null;
  created_at: string;
}

export interface Player {
  id: string;
  room_code: string;
  name: string;
  color: string;
  score: number;
  is_creator: boolean;
  joined_at: string;
}

export async function createRoom(code: string, subject: string, maxPlayers: number): Promise<Room> {
  const { data, error } = await supabase
    .from('rooms')
    .insert({ code, subject, max_players: maxPlayers })
    .select()
    .single();
  if (error) throw new Error(`[RoomRepo] createRoom failed: ${error.message}`);
  return data;
}

export async function getRoom(code: string): Promise<Room | null> {
  const { data, error } = await supabase
    .from('rooms').select('*').eq('code', code).maybeSingle();
  if (error) throw new Error(`[RoomRepo] getRoom failed: ${error.message}`);
  return data;
}

export async function updateRoom(code: string, updates: Partial<Room>): Promise<void> {
  const { error } = await supabase.from('rooms').update(updates).eq('code', code);
  if (error) throw new Error(`[RoomRepo] updateRoom failed: ${error.message}`);
}

export async function deleteRoom(code: string): Promise<void> {
  const { error } = await supabase.from('rooms').delete().eq('code', code);
  if (error) throw new Error(`[RoomRepo] deleteRoom failed: ${error.message}`);
}

export async function getPlayers(roomCode: string): Promise<Player[]> {
  const { data, error } = await supabase
    .from('players').select('*').eq('room_code', roomCode);
  if (error) throw new Error(`[RoomRepo] getPlayers failed: ${error.message}`);
  return data ?? [];
}

export async function addPlayer(roomCode: string, player: Omit<Player, 'room_code' | 'joined_at'>): Promise<void> {
  const { error } = await supabase
    .from('players').insert({ ...player, room_code: roomCode });
  if (error) throw new Error(`[RoomRepo] addPlayer failed: ${error.message}`);
}

export async function incrementPlayerScore(roomCode: string, playerId: string, delta: number): Promise<void> {
  const { data: p } = await supabase
    .from('players').select('score').eq('id', playerId).single();
  const newScore = (p?.score ?? 0) + delta;
  const { error } = await supabase
    .from('players').update({ score: newScore }).eq('id', playerId).eq('room_code', roomCode);
  if (error) throw new Error(`[RoomRepo] incrementPlayerScore failed: ${error.message}`);
}
```

### 1.5 Seed Script

> **Before running seed:** Make sure the `questions` table exists in Supabase (create it using the SQL in `plan.md` → "Supabase PostgreSQL Tables", either via Supabase MCP or the SQL editor).

**`src/scripts/seed.ts`**:
```typescript
import 'dotenv/config';
import { readFileSync } from 'fs';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';
import { supabase } from '../config/supabase.js';
import { logger } from '../config/logger.js';

const __dirname = dirname(fileURLToPath(import.meta.url));
const JSON_PATH = join(__dirname, '../../../data-set/questions/all.json');

async function seed() {
  const raw = JSON.parse(readFileSync(JSON_PATH, 'utf-8')) as Array<{
    id: string; subject: string; text: string;
    choices: string[]; correct_answer_index: number; exam_type: string;
  }>;
  logger.info(`[Seed] Loaded ${raw.length} questions from JSON`);

  const BATCH = 500;
  for (let i = 0; i < raw.length; i += BATCH) {
    const batch = raw.slice(i, i + BATCH).map((q) => ({
      id: q.id,
      subject: q.subject,
      text: q.text,
      choices: q.choices,
      correct_answer_index: q.correct_answer_index,
      exam_type: q.exam_type,
    }));

    const { error } = await supabase
      .from('questions')
      .upsert(batch, { onConflict: 'id' });

    if (error) throw new Error(`[Seed] Batch failed: ${error.message}`);
    logger.info(`[Seed] Progress: ${Math.min(i + BATCH, raw.length)} / ${raw.length}`);
  }

  logger.info('[Seed] Done.');
}

seed().catch((e) => { logger.error(e, '[Seed] Failed'); process.exit(1); });
```

Run: `cd backend && npm run seed`

Expected output:
```
[Seed] Loaded 3595 questions from JSON
[Seed] Progress: 500 / 3595
...
[Seed] Progress: 3595 / 3595
[Seed] Done.
```

If you see errors, check `SUPABASE_URL` and `SUPABASE_SERVICE_KEY` in `backend/.env`.

**Verify via Supabase MCP after seeding:**
```sql
SELECT subject, COUNT(*) FROM questions GROUP BY subject ORDER BY subject;
-- Expected:
-- geography         | 476
-- history           | 1138
-- math              | 58
-- ukrainian_language | 1923
```

### 1.6 Services

**`src/services/CodeGenerator.ts`**:
```typescript
import { customAlphabet } from 'nanoid';
import { getRoom } from '../data/repositories/RoomRepository.js';

const gen = customAlphabet('ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789', 3);

export async function generateUniqueCode(): Promise<string> {
  for (let attempt = 0; attempt < 10; attempt++) {
    const code = gen();
    const existing = await getRoom(code);
    if (!existing) return code;
  }
  throw new Error('Failed to generate unique room code after 10 attempts');
}
```

**`src/services/NameGenerator.ts`**:
```typescript
const NAMES = [
  'Веселий Кит', 'Сонячна Жаба', 'Хоробрий Гусак', 'Мудра Сова', 'Швидкий Заєць',
  'Лінивий Ведмідь', 'Бойовий Орел', 'Тихий Кіт', 'Гучний Ворон', 'Добрий Вовк',
  'Смілива Лисиця', 'Сильний Тигр', 'Грайливий Дельфін', 'Чесний Олень', 'Дотепний Пінгвін',
  'Яскравий Папуга', 'Розумна Мавпа', 'Уважна Черепаха', 'Дружній Їжак', 'Чарівний Лось',
  'Кмітливий Бобер', 'Спритний Борсук', 'Задерикуватий Козел', 'Ніжний Лебідь', 'Гордий Лев',
  'Сміливий Сокіл', 'Зворушливий Кролик', 'Незворушний Буйвол', 'Щасливий Дятел', 'Тямущий Рак',
  'Активний Хом\'як', 'Бадьорий Качур', 'Стрімкий Леопард', 'Непосидючий Горобець', 'Хитрий Осел',
  'Наполегливий Бик', 'Ласкавий Єнот', 'Загадковий Осьминіг', 'Безстрашний Шакал', 'Ввічливий Кенгуру',
  'Мрійливий Фламінго', 'Відважний Крокодил', 'Спокійний Бегемот', 'Жвавий Горила', 'Привітний Пелікан',
  'Неприборканий Ягуар', 'Допитливий Суслик', 'Терплячий Жираф', 'Чудовий Носоріг', 'Лагідний Зубр',
];

const COLORS = ['#FF6B6B', '#4ECDC4', '#45B7D1', '#96CEB4', '#FFEAA7', '#DDA0DD', '#98D8C8', '#F7DC6F'];

const usedNamesInRoom = new Map<string, Set<string>>();

export function assignName(roomCode: string): { name: string; color: string } {
  if (!usedNamesInRoom.has(roomCode)) usedNamesInRoom.set(roomCode, new Set());
  const used = usedNamesInRoom.get(roomCode)!;
  const available = NAMES.filter((n) => !used.has(n));
  const name = available.length > 0
    ? available[Math.floor(Math.random() * available.length)]
    : `Гравець ${used.size + 1}`;
  used.add(name);
  const color = COLORS[used.size % COLORS.length];
  return { name, color };
}

export function clearRoom(roomCode: string): void {
  usedNamesInRoom.delete(roomCode);
}
```

### 1.7 Zod Validators

**`src/presentation/validators/requestSchemas.ts`**:
```typescript
import { z } from 'zod';

export const CreateRoomSchema = z.object({
  subject: z.enum(['ukrainian_language', 'history', 'geography', 'math']),
  maxPlayers: z.number().int().min(1).max(4),
});

export const JoinRoomSchema = z.object({
  // No body — player identity assigned server-side
});

export const StartGameSchema = z.object({
  playerId: z.string().uuid(),
});

export const SubmitAnswerSchema = z.object({
  playerId: z.string().uuid(),
  questionId: z.string().min(1),
  answerIndex: z.number().int().min(0).max(4),
});
```

### 1.8 REST Controllers + Routes

**`src/presentation/controllers/SubjectController.ts`**:
```typescript
import { Request, Response } from 'express';
import { SUBJECTS } from '../../domain/types.js';
import { getSubjectCounts } from '../../data/repositories/QuestionRepository.js';

export async function getSubjects(_req: Request, res: Response) {
  const counts = await getSubjectCounts();
  const subjects = SUBJECTS.map((s) => ({ ...s, questionCount: counts[s.key] ?? 0 }));
  res.json({ subjects });
}
```

**`src/presentation/controllers/RoomController.ts`**:
```typescript
import { Request, Response } from 'express';
import { v4 as uuid } from 'uuid';
import { createRoom as dbCreateRoom, getRoom as dbGetRoom, getPlayers, addPlayer } from '../../data/repositories/RoomRepository.js';
import { generateUniqueCode } from '../../services/CodeGenerator.js';
import { assignName } from '../../services/NameGenerator.js';
import { broadcastToRoom } from '../../config/supabase.js';
import { CreateRoomSchema, JoinRoomSchema } from '../validators/requestSchemas.js';
import { logger } from '../../config/logger.js';

export async function createRoom(req: Request, res: Response) {
  const parsed = CreateRoomSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });

  const { subject, maxPlayers } = parsed.data;
  const code = await generateUniqueCode();
  await dbCreateRoom(code, subject, maxPlayers);

  logger.info(`[RoomController] Room created | code=${code} subject=${subject} maxPlayers=${maxPlayers}`);
  res.status(201).json({ code });
}

export async function getRoomState(req: Request, res: Response) {
  const code = req.params.code.toUpperCase();
  const room = await dbGetRoom(code);
  if (!room) return res.status(404).json({ error: 'Room not found' });

  const players = await getPlayers(code);
  res.json({
    code: room.code,
    subject: room.subject,
    status: room.status,
    maxPlayers: room.max_players,
    currentQuestionIndex: room.current_question_index,
    players: players.map((p) => ({ id: p.id, name: p.name, color: p.color, score: p.score, isCreator: p.is_creator })),
  });
}

export async function joinRoom(req: Request, res: Response) {
  const code = req.params.code.toUpperCase();
  const room = await dbGetRoom(code);
  if (!room) return res.status(404).json({ error: 'Кімнату не знайдено' });
  if (room.status !== 'waiting') return res.status(400).json({ error: 'Гра вже почалась' });

  const players = await getPlayers(code);
  if (players.length >= room.max_players) return res.status(400).json({ error: 'Кімната повна' });

  const { name, color } = assignName(code);
  const playerId = uuid();
  const isCreator = players.length === 0;

  await addPlayer(code, { id: playerId, name, color, score: 0, is_creator: isCreator });

  const updatedPlayers = await getPlayers(code);
  await broadcastToRoom(code, 'room:state', {
    code,
    subject: room.subject,
    status: room.status,
    maxPlayers: room.max_players,
    players: updatedPlayers.map((p) => ({ id: p.id, name: p.name, color: p.color, score: p.score, isCreator: p.is_creator })),
  });

  logger.info(`[RoomController] Player joined | roomCode=${code} playerId=${playerId} name=${name} isCreator=${isCreator}`);
  // Return player identity in HTTP response — replaces socket "room:joined" event
  res.json({ playerId, name, color, isCreator });
}
```

**`src/presentation/routes/index.ts`**:
```typescript
import { Router } from 'express';
import rateLimit from 'express-rate-limit';
import { getSubjects } from '../controllers/SubjectController.js';
import { createRoom, getRoomState, joinRoom } from '../controllers/RoomController.js';
import { startGame, submitAnswer } from '../controllers/GameController.js';

const router = Router();

const roomCreationLimit = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 10,
  message: { error: 'Too many rooms created. Please try again later.' },
});

router.get('/subjects', getSubjects);
router.post('/rooms', roomCreationLimit, createRoom);
router.get('/rooms/:code', getRoomState);
router.post('/rooms/:code/join', joinRoom);
router.post('/rooms/:code/start', startGame);
router.post('/rooms/:code/answer', submitAnswer);

export default router;
```

### 1.9 Main Entry Point

**`src/main.ts`**:
```typescript
import 'dotenv/config';
import './config/supabase.js';  // validates env vars + initializes client on import
import express from 'express';
import cors from 'cors';
import helmet from 'helmet';
import { logger } from './config/logger.js';
import routes from './presentation/routes/index.js';

const app = express();

app.use(cors({ origin: process.env.CORS_ORIGIN || '*' }));
app.use(helmet());
app.use(express.json());
app.use('/api', routes);

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => logger.info(`[Server] Listening on port ${PORT}`));
```

> **Note:** No `createServer(http)` needed — we don't run Socket.io. Plain Express is enough. Supabase Realtime runs in Supabase's cloud, not in our process.

---

### ✅ Phase 1 Gate Check

```bash
# Dev server starts without errors
cd backend && npm run dev
# Should print: [Supabase] Client initialized  then  [Server] Listening on port 3000

# In a new terminal — test REST endpoints:
curl http://localhost:3000/api/subjects
# Expected: { "subjects": [{ "key": "ukrainian_language", "questionCount": 1923 }, ...] }

curl -X POST http://localhost:3000/api/rooms \
  -H 'Content-Type: application/json' \
  -d '{"subject":"history","maxPlayers":2}'
# Expected: { "code": "A9X" }
# Note: no player identity yet — assigned when player calls POST /rooms/:code/join

# Save the code from above and test join:
curl -X POST http://localhost:3000/api/rooms/A9X/join \
  -H 'Content-Type: application/json'
# Expected: { "playerId": "uuid-v4", "name": "Веселий Кит", "color": "#FF6B6B", "isCreator": true }

# Get room state:
curl http://localhost:3000/api/rooms/A9X
# Expected: room object with 1 player — NO correct_answer_index anywhere
```

Checklist:
- [ ] `GET /api/subjects` returns subjects with correct `questionCount` values (1923, 1138, 476, 58)
- [ ] `POST /api/rooms` returns `{ code }` — 3-char alphanumeric
- [ ] `POST /api/rooms/:code/join` returns `{ playerId, name, color, isCreator: true }` for first joiner
- [ ] Second `POST /api/rooms/:code/join` returns `isCreator: false`
- [ ] `GET /api/rooms/:code` shows both players, no `correct_answer_index` in response
- [ ] Server logs are structured and readable in `pino-pretty` format

Stop the dev server after verifying.

---

## Phase 2 — Real-time Game Engine

> **Architecture shift from Phase 1:** No Socket.io. All client→server communication is REST. All server→client broadcasts go through Supabase Realtime via `broadcastToRoom()`. The `GameEngine` service has no dependency on Socket.io — it imports `broadcastToRoom` from config.

### 2.1 Game Engine

**`src/services/GameEngine.ts`**:
```typescript
import { broadcastToRoom } from '../config/supabase.js';
import { getRoom, updateRoom, getPlayers, incrementPlayerScore, deleteRoom } from '../data/repositories/RoomRepository.js';
import { getRandomQuestions, getQuestionsByIds } from '../data/repositories/QuestionRepository.js';
import { clearRoom } from './NameGenerator.js';
import { logger } from '../config/logger.js';

const QUESTION_COUNT = 10;
const ROUND_TIMER_MS = 5 * 60 * 1000; // 5 minutes — reduce temporarily for testing
const REVEAL_DELAY_MS = 3000;
const CORRECT_ANSWER_POINTS = 10;

// In-memory: roomCode → { answers: Map<playerId, number|null>, timer: NodeJS.Timeout }
// This state lives in Node.js — intentional. Keeps game logic server-authoritative.
const roundState = new Map<string, { answers: Map<string, number | null>; timer: NodeJS.Timeout }>();

export async function startGame(roomCode: string): Promise<void> {
  const room = await getRoom(roomCode);
  if (!room || room.status !== 'waiting') return;

  const questions = await getRandomQuestions(room.subject, QUESTION_COUNT);
  const questionIds = questions.map((q) => q.id);

  await updateRoom(roomCode, { status: 'playing', question_ids: questionIds, current_question_index: 0 });

  logger.info(`[GameEngine] Game started | roomCode=${roomCode} questions=${QUESTION_COUNT}`);
  await broadcastToRoom(roomCode, 'game:start', { totalQuestions: QUESTION_COUNT });

  await startRound(roomCode, 0, questions);
}

async function startRound(roomCode: string, questionIndex: number, questions: ReturnType<typeof getRandomQuestions> extends Promise<infer T> ? T : never) {
  const room = await getRoom(roomCode);
  if (!room || room.status !== 'playing') return;

  const questionDoc = questions[questionIndex];
  await updateRoom(roomCode, { current_question_index: questionIndex, round_started_at: new Date().toISOString() });

  // SECURITY CRITICAL: strip correct_answer_index before broadcasting
  const clientQuestion = {
    id: questionDoc.id,
    subject: questionDoc.subject,
    text: questionDoc.text,
    choices: questionDoc.choices,
  };

  logger.info(`[GameEngine] Round started | roomCode=${roomCode} questionIndex=${questionIndex} questionId=${questionDoc.id}`);
  await broadcastToRoom(roomCode, 'question:new', clientQuestion);

  // Initialize answer tracking for all players in this room
  const players = await getPlayers(roomCode);
  const answers = new Map<string, number | null>();
  players.forEach((p) => answers.set(p.id, null));

  const timer = setTimeout(() => revealRound(roomCode, questionIndex, questions), ROUND_TIMER_MS);
  roundState.set(roomCode, { answers, timer });
}

export async function submitAnswer(roomCode: string, playerId: string, questionId: string, answerIndex: number): Promise<void> {
  const state = roundState.get(roomCode);
  if (!state) return;
  if (state.answers.get(playerId) !== null) return; // already answered

  const room = await getRoom(roomCode);
  if (!room || room.question_ids[room.current_question_index] !== questionId) return;

  const timeTakenMs = Date.now() - new Date(room.round_started_at ?? Date.now()).getTime();
  state.answers.set(playerId, answerIndex);
  logger.info(`[GameEngine] Answer recv | roomCode=${roomCode} playerId=${playerId} answerIndex=${answerIndex} timeTakenMs=${timeTakenMs}`);

  await broadcastToRoom(roomCode, 'round:update', { playerAnswers: Object.fromEntries(state.answers) });

  // Check if all active players have answered → early reveal
  const players = await getPlayers(roomCode);
  const allAnswered = players.every((p) => state.answers.get(p.id) !== null);
  if (allAnswered) {
    clearTimeout(state.timer);
    const questions = await fetchQuestionsOrdered(room.question_ids);
    await revealRound(roomCode, room.current_question_index, questions);
  }
}

async function revealRound(
  roomCode: string,
  questionIndex: number,
  questions: Awaited<ReturnType<typeof getQuestionsByIds>>,
) {
  const state = roundState.get(roomCode);
  if (!state) return;

  const questionDoc = questions[questionIndex];
  const correctIndex = questionDoc.correct_answer_index;
  const unanswered = [...state.answers.entries()].filter(([, v]) => v === null).map(([k]) => k);

  if (unanswered.length > 0) {
    logger.warn(`[GameEngine] Timer expired | roomCode=${roomCode} questionIndex=${questionIndex} unanswered=${JSON.stringify(unanswered)}`);
  }

  // Update scores
  const players = await getPlayers(roomCode);
  const scores: Record<string, number> = {};
  for (const player of players) {
    const answer = state.answers.get(player.id);
    if (answer === correctIndex) {
      await incrementPlayerScore(roomCode, player.id, CORRECT_ANSWER_POINTS);
      scores[player.id] = player.score + CORRECT_ANSWER_POINTS;
    } else {
      scores[player.id] = player.score;
    }
  }

  logger.info(`[GameEngine] Round reveal | roomCode=${roomCode} correctIndex=${correctIndex} scores=${JSON.stringify(scores)}`);
  await broadcastToRoom(roomCode, 'round:reveal', {
    correctIndex,
    playerAnswers: Object.fromEntries(state.answers),
    scores,
  });

  roundState.delete(roomCode);

  setTimeout(async () => {
    if (questionIndex + 1 >= QUESTION_COUNT) {
      await endGame(roomCode);
    } else {
      const updatedQuestions = await fetchQuestionsOrdered(questions.map((q) => q.id));
      await startRound(roomCode, questionIndex + 1, updatedQuestions);
    }
  }, REVEAL_DELAY_MS);
}

async function endGame(roomCode: string) {
  await updateRoom(roomCode, { status: 'finished' });
  const players = await getPlayers(roomCode);

  const scoreboard = [...players]
    .sort((a, b) => b.score - a.score)
    .map((p, i) => ({ rank: i + 1, id: p.id, name: p.name, color: p.color, score: p.score }));

  logger.info(`[GameEngine] Game ended | roomCode=${roomCode} scoreboard=${JSON.stringify(scoreboard)}`);
  await broadcastToRoom(roomCode, 'game:end', { scoreboard });

  // Schedule room cleanup after 1 hour
  setTimeout(async () => {
    await deleteRoom(roomCode);
    clearRoom(roomCode);
    logger.info(`[GameEngine] Room cleaned up | roomCode=${roomCode}`);
  }, 60 * 60 * 1000);
}

// Preserves the original random order from startGame (do NOT sort by id)
async function fetchQuestionsOrdered(questionIds: string[]) {
  const docs = await getQuestionsByIds(questionIds);
  const docMap = new Map(docs.map((d) => [d.id, d]));
  return questionIds.map((id) => docMap.get(id)!);
}
```

### 2.2 Game Controller (REST handlers for start + answer)

**`src/presentation/controllers/GameController.ts`**:
```typescript
import { Request, Response } from 'express';
import { getRoom, getPlayers } from '../../data/repositories/RoomRepository.js';
import { startGame, submitAnswer } from '../../services/GameEngine.js';
import { StartGameSchema, SubmitAnswerSchema } from '../validators/requestSchemas.js';
import { logger } from '../../config/logger.js';

export async function startGame(req: Request, res: Response) {
  const code = req.params.code.toUpperCase();
  const parsed = StartGameSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });

  const room = await getRoom(code);
  if (!room) return res.status(404).json({ error: 'Кімнату не знайдено' });
  if (room.status !== 'waiting') return res.status(400).json({ error: 'Гра вже почалась' });

  const players = await getPlayers(code);
  const player = players.find((p) => p.id === parsed.data.playerId);
  if (!player?.is_creator) return res.status(403).json({ error: 'Тільки творець може почати гру' });

  logger.info(`[GameController] game:start | roomCode=${code} playerId=${parsed.data.playerId}`);
  await startGame(code);
  res.json({ ok: true });
}

export async function submitAnswer(req: Request, res: Response) {
  const code = req.params.code.toUpperCase();
  const parsed = SubmitAnswerSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });

  const { playerId, questionId, answerIndex } = parsed.data;
  logger.info(`[GameController] answer | roomCode=${code} playerId=${playerId} answerIndex=${answerIndex}`);
  await submitAnswer(code, playerId, questionId, answerIndex);
  res.json({ ok: true });
}
```

---

### ✅ Phase 2 Gate Check

Start the backend (`cd backend && npm run dev`), then test the full REST + Supabase Realtime flow with a Node.js test script.

**Install test dependencies (one-time):**
```bash
npm install -g @supabase/supabase-js  # or use: node --input-type=module
# or just run: node test_game.mjs (it uses dynamic import)
```

```javascript
// test_game.mjs — run with: node test_game.mjs
// Tests: create room → join (2 players) → game:start → question:new (security check) → answer → round:update → round:reveal
import { createClient } from '@supabase/supabase-js';

const BASE = 'http://localhost:3000';
const SUPABASE_URL = process.env.SUPABASE_URL;   // same as in backend/.env
const SUPABASE_ANON_KEY = process.env.SUPABASE_ANON_KEY; // anon key (NOT service key)

const post = (path, body) => fetch(`${BASE}${path}`, {
  method: 'POST', headers: { 'Content-Type': 'application/json' },
  body: body ? JSON.stringify(body) : undefined,
}).then(r => r.json());

// Step 1: Create room
const { code } = await post('/api/rooms', { subject: 'history', maxPlayers: 2 });
console.log('Room created ✅ | code=' + code);

// Step 2: Two players join
const p1 = await post(`/api/rooms/${code}/join`);
console.log('P1 joined ✅ | playerId=' + p1.playerId + ' isCreator=' + p1.isCreator);
if (!p1.isCreator) { console.error('ERROR: p1 should be creator!'); process.exit(1); }

const p2 = await post(`/api/rooms/${code}/join`);
console.log('P2 joined ✅ | playerId=' + p2.playerId + ' isCreator=' + p2.isCreator);
if (p2.isCreator) { console.error('ERROR: p2 should NOT be creator!'); process.exit(1); }

// Step 3: Subscribe to Supabase Realtime channel (both players share one subscription for test)
const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
let receivedGameStart = false, receivedQuestion = false, receivedRoundUpdate = false;

const channel = supabase.channel(`room:${code}`)
  .on('broadcast', { event: 'game:start' }, ({ payload }) => {
    console.log('game:start ✅ | totalQuestions=' + payload.totalQuestions);
    receivedGameStart = true;
  })
  .on('broadcast', { event: 'question:new' }, ({ payload }) => {
    const hasCorrect = 'correct_answer_index' in payload;
    console.log('question:new ✅ | id=' + payload.id + ' has correct_answer_index? ' + hasCorrect);
    if (hasCorrect) { console.error('SECURITY VIOLATION: correct_answer_index in question:new!'); process.exit(1); }
    receivedQuestion = true;
    // Both players answer immediately
    post(`/api/rooms/${code}/answer`, { playerId: p1.playerId, questionId: payload.id, answerIndex: 0 });
    post(`/api/rooms/${code}/answer`, { playerId: p2.playerId, questionId: payload.id, answerIndex: 1 });
  })
  .on('broadcast', { event: 'round:update' }, ({ payload }) => {
    console.log('round:update ✅ | playerAnswers=' + JSON.stringify(payload.playerAnswers));
    receivedRoundUpdate = true;
  })
  .on('broadcast', { event: 'round:reveal' }, ({ payload }) => {
    console.log('round:reveal ✅ | correctIndex=' + payload.correctIndex + ' scores=' + JSON.stringify(payload.scores));
    console.log('All Phase 2 checks passed ✅');
    channel.unsubscribe();
    process.exit(0);
  })
  .subscribe();

// Step 4: Creator starts game
await post(`/api/rooms/${code}/start`, { playerId: p1.playerId });
console.log('game:start sent ✅');

setTimeout(() => { console.error('TIMEOUT: test did not complete in 15s'); process.exit(1); }, 15000);
```

Run: `SUPABASE_URL=... SUPABASE_ANON_KEY=... node test_game.mjs`

Checklist before moving on:
- [ ] `POST /api/rooms` returns `{ code }` (3-char)
- [ ] First `POST /api/rooms/:code/join` → `isCreator: true`; second → `isCreator: false`
- [ ] `POST /api/rooms/:code/start` by creator → Supabase broadcasts `game:start` + first `question:new`
- [ ] `question:new` payload does **NOT** contain `correct_answer_index`
- [ ] `round:update` fires after each player answers (partial results visible)
- [ ] `round:reveal` fires when all players answer — contains `correctIndex`, `playerAnswers`, `scores`
- [ ] `round:reveal` fires after timer if not all players answered (temporarily reduce `ROUND_TIMER_MS = 5000` for testing)
- [ ] Non-creator calling `POST /api/rooms/:code/start` → `403` error

---

## Phase 3 — Flutter Frontend

### 3.1 SupabaseService + ApiService

> **No `socket_io_client`.** Flutter subscribes to Supabase Realtime Broadcast for server events. REST calls go to Node.js via `http` package.

**`lib/services/supabase_service.dart`**:
```dart
import 'dart:async';
import 'package:logger/logger.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Server→client event types (all delivered via Supabase Realtime Broadcast)
enum RealtimeEventType { roomState, gameStart, questionNew, roundUpdate, roundReveal, gameEnd, playerDisconnected }

class RealtimeEvent {
  final RealtimeEventType type;
  final Map<String, dynamic> data;
  const RealtimeEvent(this.type, this.data);
}

class SupabaseService {
  final Logger logger;
  final _controller = StreamController<RealtimeEvent>.broadcast();
  RealtimeChannel? _channel;

  Stream<RealtimeEvent> get events => _controller.stream;

  SupabaseService({required this.logger});

  static Future<void> initialize() async {
    await Supabase.initialize(
      url: const String.fromEnvironment('SUPABASE_URL'),
      anonKey: const String.fromEnvironment('SUPABASE_ANON_KEY'),
    );
  }

  void subscribeToRoom(String roomCode) {
    logger.i('[SupabaseService] subscribing to room:$roomCode');
    _channel = Supabase.instance.client.channel('room:$roomCode')
      .onBroadcast(event: 'room:state',          callback: (p) => _emit(RealtimeEventType.roomState, p))
      .onBroadcast(event: 'game:start',          callback: (p) => _emit(RealtimeEventType.gameStart, p))
      .onBroadcast(event: 'question:new',        callback: (p) {
        if (p.containsKey('correct_answer_index')) {
          logger.e('[SupabaseService] SECURITY VIOLATION: correct_answer_index in question:new!');
        }
        _emit(RealtimeEventType.questionNew, p);
      })
      .onBroadcast(event: 'round:update',        callback: (p) => _emit(RealtimeEventType.roundUpdate, p))
      .onBroadcast(event: 'round:reveal',        callback: (p) => _emit(RealtimeEventType.roundReveal, p))
      .onBroadcast(event: 'game:end',            callback: (p) => _emit(RealtimeEventType.gameEnd, p))
      .onBroadcast(event: 'player:disconnected', callback: (p) => _emit(RealtimeEventType.playerDisconnected, p))
      .subscribe((status, err) {
        if (status == RealtimeSubscribeStatus.subscribed) {
          logger.i('[SupabaseService] subscribed to room:$roomCode');
        } else if (err != null) {
          logger.e('[SupabaseService] ERROR subscription | err=$err');
        }
      });
  }

  void _emit(RealtimeEventType type, Map<String, dynamic> data) {
    logger.i('[SupabaseService] event | type=${type.name}');
    _controller.add(RealtimeEvent(type, data));
  }

  void unsubscribe() {
    _channel?.unsubscribe();
    _channel = null;
    logger.i('[SupabaseService] unsubscribed');
  }

  void dispose() {
    unsubscribe();
    _controller.close();
  }
}
```

**`lib/services/api_service.dart`**:
```dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:logger/logger.dart';

/// Handles all client→server REST calls to the Node.js backend.
class ApiService {
  final String baseUrl;
  final Logger logger;

  ApiService({required this.logger})
    : baseUrl = const String.fromEnvironment('API_URL', defaultValue: 'http://localhost:3000');

  Future<Map<String, dynamic>> createRoom(String subject, int maxPlayers) async {
    logger.i('[ApiService] POST /api/rooms | subject=$subject maxPlayers=$maxPlayers');
    final res = await http.post(
      Uri.parse('$baseUrl/api/rooms'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'subject': subject, 'maxPlayers': maxPlayers}),
    );
    if (res.statusCode != 201) throw Exception('createRoom failed: ${res.body}');
    return jsonDecode(res.body) as Map<String, dynamic>;
    // Returns: { code: 'A9X' }
  }

  Future<Map<String, dynamic>> joinRoom(String roomCode) async {
    logger.i('[ApiService] POST /api/rooms/$roomCode/join');
    final res = await http.post(
      Uri.parse('$baseUrl/api/rooms/${roomCode.toUpperCase()}/join'),
      headers: {'Content-Type': 'application/json'},
    );
    if (res.statusCode != 200) throw Exception('joinRoom failed: ${res.body}');
    return jsonDecode(res.body) as Map<String, dynamic>;
    // Returns: { playerId, name, color, isCreator }
  }

  Future<void> startGame(String roomCode, String playerId) async {
    logger.i('[ApiService] POST /api/rooms/$roomCode/start | playerId=$playerId');
    final res = await http.post(
      Uri.parse('$baseUrl/api/rooms/${roomCode.toUpperCase()}/start'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'playerId': playerId}),
    );
    if (res.statusCode != 200) throw Exception('startGame failed: ${res.body}');
  }

  Future<void> submitAnswer(String roomCode, String playerId, String questionId, int answerIndex) async {
    logger.i('[ApiService] POST /api/rooms/$roomCode/answer | playerId=$playerId answerIndex=$answerIndex');
    final res = await http.post(
      Uri.parse('$baseUrl/api/rooms/${roomCode.toUpperCase()}/answer'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'playerId': playerId, 'questionId': questionId, 'answerIndex': answerIndex}),
    );
    if (res.statusCode != 200) throw Exception('submitAnswer failed: ${res.body}');
  }

  Future<List<Map<String, dynamic>>> getSubjects() async {
    final res = await http.get(Uri.parse('$baseUrl/api/subjects'));
    if (res.statusCode != 200) throw Exception('getSubjects failed: ${res.body}');
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return List<Map<String, dynamic>>.from(data['subjects'] as List);
  }
}
```

### 3.2 Failures + Typedefs

**`lib/core/failures.dart`**:
```dart
import 'package:equatable/equatable.dart';

abstract class Failure extends Equatable {
  final String message;
  const Failure(this.message);
  @override
  List<Object?> get props => [message];
}

class ServerFailure extends Failure {
  const ServerFailure(super.message);
}
class NetworkFailure extends Failure {
  const NetworkFailure(super.message);
}
class ValidationFailure extends Failure {
  const ValidationFailure(super.message);
}
```

**`lib/core/typedefs.dart`**:
```dart
import 'package:fpdart/fpdart.dart';
import 'failures.dart';

typedef FutureEither<T> = Future<Either<Failure, T>>;
typedef EitherT<T> = Either<Failure, T>;
```

### 3.3 Models

**`lib/data/models/question_model.dart`**:
```dart
class ClientQuestion {
  final String id;
  final String subject;
  final String text;
  final List<String> choices;

  const ClientQuestion({required this.id, required this.subject, required this.text, required this.choices});

  factory ClientQuestion.fromJson(Map<String, dynamic> json) => ClientQuestion(
    id: json['id'] as String,
    subject: json['subject'] as String,
    text: json['text'] as String,
    choices: List<String>.from(json['choices'] as List),
  );
}
```

**`lib/data/models/player_model.dart`**:
```dart
class PlayerModel {
  final String id;
  final String name;
  final String color;
  final int score;
  final bool isCreator;

  const PlayerModel({required this.id, required this.name, required this.color, required this.score, required this.isCreator});

  factory PlayerModel.fromJson(Map<String, dynamic> json) => PlayerModel(
    id: json['id'] as String,
    name: json['name'] as String,
    color: json['color'] as String,
    score: json['score'] as int? ?? 0,
    isCreator: json['isCreator'] as bool? ?? false,
  );
}
```

### 3.4 Cubits

**`lib/presentation/cubits/room_cubit/room_state.dart`**:
```dart
import 'package:equatable/equatable.dart';
import '../../../data/models/player_model.dart';

enum RoomStatus { initial, waiting, playing, finished, error }

class RoomState extends Equatable {
  final String code;
  final String subject;
  final RoomStatus status;
  final int maxPlayers;
  final List<PlayerModel> players;
  final String? errorMessage;

  const RoomState({
    this.code = '',
    this.subject = '',
    this.status = RoomStatus.initial,
    this.maxPlayers = 4,
    this.players = const [],
    this.errorMessage,
  });

  RoomState copyWith({String? code, String? subject, RoomStatus? status, int? maxPlayers, List<PlayerModel>? players, String? errorMessage}) =>
    RoomState(
      code: code ?? this.code,
      subject: subject ?? this.subject,
      status: status ?? this.status,
      maxPlayers: maxPlayers ?? this.maxPlayers,
      players: players ?? this.players,
      errorMessage: errorMessage,
    );

  @override
  List<Object?> get props => [code, subject, status, maxPlayers, players, errorMessage];
}
```

**`lib/presentation/cubits/room_cubit/room_cubit.dart`**:
```dart
import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:logger/logger.dart';
import '../../../data/models/player_model.dart';
import '../../../services/supabase_service.dart';
import '../../../services/api_service.dart';
import 'room_state.dart';

class RoomCubit extends Cubit<RoomState> {
  final SupabaseService supabaseService;
  final ApiService apiService;
  final Logger logger;
  late StreamSubscription<RealtimeEvent> _sub;

  // Set on joinRoom() response — used by QuizCubit to identify "my" answers
  String? myPlayerId;
  String? myName;
  bool myIsCreator = false;

  RoomCubit({required this.supabaseService, required this.apiService, required this.logger})
      : super(const RoomState()) {
    _sub = supabaseService.events.listen(_handleEvent);
  }

  Future<void> joinRoom(String roomCode) async {
    logger.i('[RoomCubit] joining room | roomCode=$roomCode');
    try {
      // Subscribe to Supabase Realtime BEFORE calling REST join,
      // so we don't miss the room:state broadcast that fires on join.
      supabaseService.subscribeToRoom(roomCode.toUpperCase());

      final result = await apiService.joinRoom(roomCode);
      myPlayerId = result['playerId'] as String;
      myName = result['name'] as String;
      myIsCreator = result['isCreator'] as bool? ?? false;
      logger.i('[RoomCubit] joined | myPlayerId=$myPlayerId name=$myName isCreator=$myIsCreator');
    } catch (e) {
      logger.e('[RoomCubit] joinRoom failed | err=$e');
      emit(state.copyWith(status: RoomStatus.error, errorMessage: e.toString()));
    }
  }

  Future<void> startGame() async {
    if (myPlayerId == null) return;
    logger.i('[RoomCubit] starting game | roomCode=${state.code}');
    try {
      await apiService.startGame(state.code, myPlayerId!);
    } catch (e) {
      logger.e('[RoomCubit] startGame failed | err=$e');
      emit(state.copyWith(status: RoomStatus.error, errorMessage: e.toString()));
    }
  }

  void _handleEvent(RealtimeEvent event) {
    switch (event.type) {
      case RealtimeEventType.roomState:
        _handleRoomState(event.data);
        break;
      case RealtimeEventType.gameStart:
        logger.i('[RoomCubit] game:start received | transitioning to playing');
        emit(state.copyWith(status: RoomStatus.playing));
        break;
      case RealtimeEventType.playerDisconnected:
        final playerId = event.data['playerId'] as String?;
        logger.w('[RoomCubit] player disconnected | playerId=$playerId');
        if (playerId != null) {
          emit(state.copyWith(players: state.players.where((p) => p.id != playerId).toList()));
        }
        break;
      default:
        break;
    }
  }

  void _handleRoomState(Map<String, dynamic> data) {
    final players = (data['players'] as List? ?? [])
        .map((p) => PlayerModel.fromJson(p as Map<String, dynamic>))
        .toList();
    final statusStr = data['status'] as String? ?? 'waiting';
    final status = switch (statusStr) {
      'playing'  => RoomStatus.playing,
      'finished' => RoomStatus.finished,
      _          => RoomStatus.waiting,
    };
    logger.i('[RoomCubit] room:state | status=$statusStr players=${players.length}');
    emit(state.copyWith(
      code: data['code'] as String? ?? state.code,
      subject: data['subject'] as String? ?? state.subject,
      status: status,
      maxPlayers: data['maxPlayers'] as int? ?? state.maxPlayers,
      players: players,
    ));
  }

  @override
  Future<void> close() {
    _sub.cancel();
    supabaseService.unsubscribe();
    return super.close();
  }
}
```

**`lib/presentation/cubits/quiz_cubit/quiz_state.dart`**:
```dart
import 'package:equatable/equatable.dart';
import '../../../data/models/question_model.dart';
import '../../../data/models/player_model.dart';

abstract class QuizState extends Equatable {
  const QuizState();
}

class QuizInitial extends QuizState {
  const QuizInitial();
  @override List<Object?> get props => [];
}

class QuizQuestion extends QuizState {
  final ClientQuestion question;
  final int questionIndex;
  final int totalQuestions;
  final Duration timeRemaining;
  final int? myAnswer;
  final Map<String, int?> playerAnswers;

  const QuizQuestion({
    required this.question, required this.questionIndex, required this.totalQuestions,
    required this.timeRemaining, this.myAnswer, this.playerAnswers = const {},
  });

  QuizQuestion copyWith({Duration? timeRemaining, int? myAnswer, Map<String, int?>? playerAnswers}) =>
    QuizQuestion(
      question: question, questionIndex: questionIndex, totalQuestions: totalQuestions,
      timeRemaining: timeRemaining ?? this.timeRemaining,
      myAnswer: myAnswer ?? this.myAnswer,
      playerAnswers: playerAnswers ?? this.playerAnswers,
    );

  @override List<Object?> get props => [question, questionIndex, timeRemaining, myAnswer, playerAnswers];
}

class QuizReveal extends QuizState {
  final ClientQuestion question;
  final int correctIndex;
  final Map<String, int?> playerAnswers;
  final Map<String, int> scores;
  final int? myAnswer;

  const QuizReveal({required this.question, required this.correctIndex, required this.playerAnswers, required this.scores, this.myAnswer});

  @override List<Object?> get props => [question, correctIndex, playerAnswers, scores, myAnswer];
}

class QuizGameEnded extends QuizState {
  final List<Map<String, dynamic>> scoreboard;
  const QuizGameEnded({required this.scoreboard});
  @override List<Object?> get props => [scoreboard];
}

class QuizError extends QuizState {
  final String message;
  const QuizError(this.message);
  @override List<Object?> get props => [message];
}
```

**`lib/presentation/cubits/quiz_cubit/quiz_cubit.dart`**:
```dart
import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:logger/logger.dart';
import '../../../data/models/question_model.dart';
import '../../../services/supabase_service.dart';
import '../../../services/api_service.dart';
import 'quiz_state.dart';

class QuizCubit extends Cubit<QuizState> {
  final SupabaseService supabaseService;
  final ApiService apiService;
  final Logger logger;
  late StreamSubscription<RealtimeEvent> _sub;
  Timer? _timer;
  ClientQuestion? _currentQuestion;
  String? _myPlayerId;
  String? _roomCode;
  int _questionIndex = 0;
  int _totalQuestions = 10;

  QuizCubit({required this.supabaseService, required this.apiService, required this.logger})
      : super(const QuizInitial()) {
    _sub = supabaseService.events.listen(_handleEvent);
  }

  void setContext(String myPlayerId, String roomCode) {
    _myPlayerId = myPlayerId;
    _roomCode = roomCode;
  }

  void _handleEvent(RealtimeEvent event) {
    switch (event.type) {
      case RealtimeEventType.gameStart:
        _totalQuestions = event.data['totalQuestions'] as int? ?? 10;
        _questionIndex = 0;
        break;
      case RealtimeEventType.questionNew:
        _handleNewQuestion(event.data);
        break;
      case RealtimeEventType.roundUpdate:
        _handleRoundUpdate(event.data);
        break;
      case RealtimeEventType.roundReveal:
        _handleReveal(event.data);
        break;
      case RealtimeEventType.gameEnd:
        logger.i('[QuizCubit] game ended | scoreboard=${event.data['scoreboard']}');
        _timer?.cancel();
        emit(QuizGameEnded(scoreboard: List<Map<String, dynamic>>.from(event.data['scoreboard'] as List)));
        break;
      default:
        break;
    }
  }

  void _handleNewQuestion(Map<String, dynamic> data) {
    _questionIndex++;
    _currentQuestion = ClientQuestion.fromJson(data);
    logger.i('[QuizCubit] question:new received | questionId=${_currentQuestion!.id} choicesCount=${_currentQuestion!.choices.length} timerMs=300000');

    emit(QuizQuestion(
      question: _currentQuestion!,
      questionIndex: _questionIndex,
      totalQuestions: _totalQuestions,
      timeRemaining: const Duration(minutes: 5),
    ));
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    var remaining = const Duration(minutes: 5);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      remaining -= const Duration(seconds: 1);
      if (remaining.isNegative) { _timer?.cancel(); return; }
      final s = state;
      if (s is QuizQuestion) emit(s.copyWith(timeRemaining: remaining));
    });
  }

  void _handleRoundUpdate(Map<String, dynamic> data) {
    final raw = data['playerAnswers'] as Map<String, dynamic>? ?? {};
    final answers = raw.map((k, v) => MapEntry(k, v as int?));
    final s = state;
    if (s is QuizQuestion) emit(s.copyWith(playerAnswers: answers));
  }

  void _handleReveal(Map<String, dynamic> data) {
    _timer?.cancel();
    final correctIndex = data['correctIndex'] as int;
    final raw = data['playerAnswers'] as Map<String, dynamic>? ?? {};
    final answers = raw.map((k, v) => MapEntry(k, v as int?));
    final scores = Map<String, int>.from(data['scores'] as Map);
    final myAnswer = _myPlayerId != null ? answers[_myPlayerId] : null;

    logger.i('[QuizCubit] round:reveal received | correctIndex=$correctIndex myAnswer=$myAnswer isCorrect=${myAnswer == correctIndex} scoreGained=${myAnswer == correctIndex ? 10 : 0}');
    emit(QuizReveal(
      question: _currentQuestion!,
      correctIndex: correctIndex,
      playerAnswers: answers,
      scores: scores,
      myAnswer: myAnswer,
    ));
  }

  Future<void> submitAnswer(int answerIndex) async {
    final s = state;
    if (s is! QuizQuestion || _myPlayerId == null || _roomCode == null) return;
    logger.i('[QuizCubit] answer submitted | questionId=${s.question.id} selectedIndex=$answerIndex');
    // Optimistic UI update — lock button immediately
    emit(s.copyWith(myAnswer: answerIndex));
    // Send to Node.js REST (not via Supabase — server must validate)
    await apiService.submitAnswer(_roomCode!, _myPlayerId!, s.question.id, answerIndex);
  }

  @override
  Future<void> close() {
    _sub.cancel();
    _timer?.cancel();
    return super.close();
  }
}
```

### 3.5 GameCubit (create room HTTP call)

**`lib/presentation/cubits/game_cubit/game_state.dart`**:
```dart
import 'package:equatable/equatable.dart';

abstract class GameState extends Equatable {
  const GameState();
}

class GameInitial extends GameState {
  const GameInitial();
  @override List<Object?> get props => [];
}

class GameCreating extends GameState {
  const GameCreating();
  @override List<Object?> get props => [];
}

class GameCreated extends GameState {
  final String roomCode;
  const GameCreated(this.roomCode);
  @override List<Object?> get props => [roomCode];
}

class GameError extends GameState {
  final String message;
  const GameError(this.message);
  @override List<Object?> get props => [message];
}
```

**`lib/presentation/cubits/game_cubit/game_cubit.dart`**:
```dart
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:logger/logger.dart';
import '../../../services/api_service.dart';
import 'game_state.dart';

class GameCubit extends Cubit<GameState> {
  final ApiService apiService;
  final Logger logger;

  GameCubit({required this.apiService, required this.logger}) : super(const GameInitial());

  Future<void> createRoom(String subject, int maxPlayers) async {
    emit(const GameCreating());
    try {
      final data = await apiService.createRoom(subject, maxPlayers);
      final code = data['code'] as String;
      logger.i('[GameCubit] room created | code=$code');
      emit(GameCreated(code));
    } catch (e) {
      logger.e('[GameCubit] ERROR create room failed | err=$e');
      emit(const GameError('Не вдалося створити кімнату'));
    }
  }
}
```

### 3.6 go_router + main.dart

**`lib/config/router.dart`**:
```dart
import 'package:go_router/go_router.dart';
import '../presentation/pages/home_screen.dart';
import '../presentation/pages/create_room_screen.dart';
import '../presentation/pages/room_lobby_screen.dart';
import '../presentation/pages/gameplay_screen.dart';
import '../presentation/pages/round_reveal_screen.dart';
import '../presentation/pages/results_screen.dart';

final goRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(path: '/', builder: (_, __) => const HomeScreen()),
    GoRoute(path: '/create', builder: (_, __) => const CreateRoomScreen()),
    GoRoute(
      path: '/room/:roomCode',
      builder: (_, state) => RoomLobbyScreen(roomCode: state.pathParameters['roomCode']!),
      routes: [
        GoRoute(path: 'game',    builder: (_, state) => GameplayScreen(roomCode: state.pathParameters['roomCode']!)),
        GoRoute(path: 'reveal',  builder: (_, state) => RoundRevealScreen(roomCode: state.pathParameters['roomCode']!)),
        GoRoute(path: 'results', builder: (_, state) => ResultsScreen(roomCode: state.pathParameters['roomCode']!)),
      ],
    ),
  ],
);
```

**`lib/main.dart`** — wire everything together:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:logger/logger.dart';
import 'config/router.dart';
import 'services/supabase_service.dart';
import 'services/api_service.dart';
import 'presentation/cubits/room_cubit/room_cubit.dart';
import 'presentation/cubits/quiz_cubit/quiz_cubit.dart';
import 'presentation/cubits/game_cubit/game_cubit.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Supabase (reads SUPABASE_URL + SUPABASE_ANON_KEY from --dart-define)
  await SupabaseService.initialize();

  final logger = Logger();
  final supabaseService = SupabaseService(logger: logger);
  final apiService     = ApiService(logger: logger);

  final roomCubit = RoomCubit(supabaseService: supabaseService, apiService: apiService, logger: logger);
  final quizCubit = QuizCubit(supabaseService: supabaseService, apiService: apiService, logger: logger);

  // Forward playerId + roomCode to QuizCubit after join so it can track "my" answer
  roomCubit.stream.listen((_) {
    if (roomCubit.myPlayerId != null && roomCubit.state.code.isNotEmpty) {
      quizCubit.setContext(roomCubit.myPlayerId!, roomCubit.state.code);
    }
  });

  runApp(
    MultiBlocProvider(
      providers: [
        BlocProvider.value(value: roomCubit),
        BlocProvider.value(value: quizCubit),
        BlocProvider(create: (_) => GameCubit(apiService: apiService, logger: logger)),
      ],
      child: const NmtQuizApp(),
    ),
  );
}

class NmtQuizApp extends StatelessWidget {
  const NmtQuizApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'НМТ Квіз',
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF4ECDC4), brightness: Brightness.dark),
      ),
      routerConfig: goRouter,
      debugShowCheckedModeBanner: false,
    );
  }
}
```

### 3.7 Screens to Implement

The following screens must be created. Use the Cubit states + SocketService events described above. Each screen should `BlocProvider` its required Cubit and `BlocBuilder`/`BlocListener` for state-driven UI.

| File | Route | Key BlocBuilders | Notes |
|---|---|---|---|
| `pages/home_screen.dart` | `/` | — | Two buttons: navigate to `/create`, or show bottom sheet with text field for room code then navigate to `/room/:code` |
| `pages/create_room_screen.dart` | `/create` | `GameCubit` | POST `/api/rooms`, then navigate to `/room/:code` |
| `pages/room_lobby_screen.dart` | `/room/:code` | `RoomCubit` | Auto-join on `initState`. Show players list. Creator sees "Почати гру" (emit `game:start`). On `room:state` with `status=playing`, navigate to `/room/:code/game` |
| `pages/gameplay_screen.dart` | `/room/:code/game` | `QuizCubit`, `RoomCubit` | `TimerBar` + question text + answer buttons. On `QuizReveal` state, navigate to `/room/:code/reveal` |
| `pages/round_reveal_screen.dart` | `/room/:code/reveal` | `QuizCubit` | Show correct answer (green), wrong answers (red), score delta. After 3s auto-navigate back to `/room/:code/game` for next question (or to `/room/:code/results` if `QuizGameEnded`) |
| `pages/results_screen.dart` | `/room/:code/results` | `QuizCubit`, `RoomCubit` | Scoreboard. Confetti. Creator: "Грати знову" + "Нова тема". Others: "Приєднатися" |

> **Agent instruction:** Implement all screens before running the Phase 3 Gate Check. Use `BlocListener` inside `RoomLobbyScreen` to auto-navigate when `RoomStatus.playing` is emitted.

### 3.8 Key Widgets

**`lib/presentation/widgets/timer_bar.dart`**:
```dart
import 'package:flutter/material.dart';
import 'package:percent_indicator/linear_percent_indicator.dart';

class TimerBar extends StatelessWidget {
  final Duration remaining;
  static const total = Duration(minutes: 5);

  const TimerBar({super.key, required this.remaining});

  double get percent => (remaining.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);

  Color get color {
    if (percent > 0.5) return Colors.greenAccent;
    if (percent > 0.25) return Colors.orangeAccent;
    return Colors.redAccent;
  }

  @override
  Widget build(BuildContext context) {
    final secs = remaining.inSeconds;
    final label = secs >= 60
        ? '${secs ~/ 60}:${(secs % 60).toString().padLeft(2, '0')}'
        : '${secs}с';

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        LinearPercentIndicator(
          percent: percent,
          lineHeight: 8,
          animation: true,
          animationDuration: 800,
          progressColor: color,
          backgroundColor: Colors.grey.shade800,
          barRadius: const Radius.circular(4),
          padding: EdgeInsets.zero,
        ),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(fontSize: 14, color: color, fontWeight: FontWeight.bold)),
      ],
    );
  }
}
```

**`lib/presentation/widgets/answer_button.dart`**:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

enum AnswerState { idle, selected, correct, wrong }

class AnswerButton extends StatelessWidget {
  final String text;
  final AnswerState state;
  final VoidCallback? onTap;

  const AnswerButton({super.key, required this.text, this.state = AnswerState.idle, this.onTap});

  Color _bgColor(BuildContext ctx) {
    return switch (state) {
      AnswerState.correct  => Colors.green.shade700,
      AnswerState.wrong    => Colors.red.shade700,
      AnswerState.selected => Theme.of(ctx).colorScheme.primary.withOpacity(0.6),
      AnswerState.idle     => Theme.of(ctx).colorScheme.surfaceContainerHighest,
    };
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: state == AnswerState.idle ? onTap : null,
      child: AnimatedContainer(
        duration: 300.ms,
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: _bgColor(context),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white12),
        ),
        child: Text(text, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
      ),
    )
    .animate(target: state == AnswerState.selected ? 1 : 0)
    .scaleXY(begin: 1.0, end: 0.97, duration: 150.ms, curve: Curves.easeIn)
    .then()
    .scaleXY(begin: 0.97, end: 1.0, duration: 300.ms, curve: Curves.elasticOut);
  }
}
```

**`lib/presentation/widgets/player_chip.dart`**:
```dart
import 'package:flutter/material.dart';
import '../../data/models/player_model.dart';

class PlayerChip extends StatelessWidget {
  final PlayerModel player;
  final bool hasAnswered;

  const PlayerChip({super.key, required this.player, this.hasAnswered = false});

  Color get _color => Color(int.parse(player.color.replaceFirst('#', '0xFF')));

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: _color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: hasAnswered ? _color : Colors.white24, width: hasAnswered ? 2 : 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(radius: 14, backgroundColor: _color, child: Text(player.name[0], style: const TextStyle(fontSize: 12, color: Colors.white))),
          const SizedBox(width: 6),
          Text(player.name, style: const TextStyle(fontSize: 13)),
          if (hasAnswered) ...[const SizedBox(width: 4), const Icon(Icons.check_circle, size: 14, color: Colors.greenAccent)],
        ],
      ),
    );
  }
}
```

---

### ✅ Phase 3 Gate Check

```bash
# Flutter web builds without errors
cd frontend && flutter build web --debug

# Dev run (Flutter web dev server)
flutter run -d chrome
```

Manual test checklist in the browser:
- [ ] Home screen loads at `/` with two buttons
- [ ] "Створити кімнату" navigates to `/create`
- [ ] Subject picker shows 4 subjects with question counts
- [ ] After creating room, lobby screen shows room code + player name
- [ ] Opening `/room/A9X` in a second tab auto-joins the lobby
- [ ] Creator can tap "Почати гру" — both tabs transition to gameplay screen
- [ ] Question appears on both tabs (timer counts down visually)
- [ ] Tapping an answer locks the button (no double-submit)
- [ ] After both answer (or timer expires), reveal screen shows correct answer
- [ ] After 3s, next question auto-loads
- [ ] After 10 questions, results screen appears with scoreboard
- [ ] `correct_answer_index` is **never** visible in Flutter DevTools Network or console logs

---

## Phase 4 — Polish + Deploy

### 4.1 Results Screen with Confetti

```dart
import 'package:confetti/confetti.dart';

class ResultsScreen extends StatefulWidget {
  final String roomCode;
  const ResultsScreen({super.key, required this.roomCode});
  @override State<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends State<ResultsScreen> {
  late final ConfettiController _confetti = ConfettiController(duration: const Duration(seconds: 4));

  @override
  void initState() {
    super.initState();
    _confetti.play();
  }

  @override
  void dispose() { _confetti.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      // ... scoreboard UI
      Align(
        alignment: Alignment.topCenter,
        child: ConfettiWidget(
          confettiController: _confetti,
          blastDirection: 1.5708, // down
          emissionFrequency: 0.05,
          numberOfParticles: 30,
          gravity: 0.1,
          colors: const [Color(0xFFFF6B6B), Color(0xFF4ECDC4), Color(0xFFFFEAA7), Color(0xFFDDA0DD)],
        ),
      ),
    ]);
  }
}
```

### 4.2 Backend Deploy (Render — free tier)

1. Push `backend/` to GitHub
2. Create Render account → "New Web Service" → connect GitHub repo
3. Set environment variables in Render dashboard:
   - `SUPABASE_URL` — from Supabase project settings
   - `SUPABASE_SERVICE_KEY` — service-role key (secret, never commit)
   - `SUPABASE_ANON_KEY` — anon key (for reference, backend uses service key)
   - `CORS_ORIGIN` — your Firebase Hosting URL (e.g. `https://nmt-quiz.web.app`)
   - `NODE_ENV=production`
   - `PORT` — Render sets this automatically
4. Start command: `npx tsx src/main.ts` (no build step needed with tsx)

**`backend/render.yaml`** (optional, explicit config):
```yaml
services:
  - type: web
    name: nmt-quiz-backend
    runtime: node
    buildCommand: npm install
    startCommand: npx tsx src/main.ts
    envVars:
      - key: NODE_ENV
        value: production
```

> **Cold start:** Render free tier sleeps after 15 min inactivity (~30s wake-up). Flutter handles this gracefully — `ApiService` calls will retry on timeout, and `SupabaseService` reconnects automatically.

### 4.3 Frontend Deploy (Firebase Hosting)

```bash
# One-time setup
npm install -g firebase-tools
firebase login
firebase init hosting   # public dir: build/web, SPA rewrite: yes

# Build with runtime config injected via --dart-define
flutter build web --release --web-renderer canvaskit \
  --dart-define=API_URL=https://your-render-app.onrender.com \
  --dart-define=SUPABASE_URL=https://your-project.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=your-anon-key-here

firebase deploy
```

**`firebase.json`**:
```json
{
  "hosting": {
    "public": "build/web",
    "ignore": ["firebase.json", "**/.*"],
    "rewrites": [{ "source": "**", "destination": "/index.html" }]
  }
}
```

> **Security note:** Only `SUPABASE_ANON_KEY` goes into the Flutter build (public). Never put `SUPABASE_SERVICE_KEY` in `--dart-define` — it only lives in the Node.js backend environment variables.

---

## 🔧 Makefile — AI Self-Healing Verification

> **For AI agents:** Run `make check` after every phase before advancing. If it fails, read the output, fix the errors, and run again. Do NOT skip gate checks.

Create **`Makefile`** in the repo root:

```makefile
.PHONY: check check-be check-fe check-be-types check-fe-analyze seed-db help

# ─────────────────────────────────────────────────────────────────────────────
# Primary target: run all checks. Use this as the agent self-heal loop.
# Usage: make check
# ─────────────────────────────────────────────────────────────────────────────
check: check-be check-fe
	@echo ""
	@echo "✅ All checks passed — safe to advance to next phase."

# ─────────────────────────────────────────────────────────────────────────────
# Backend checks
# ─────────────────────────────────────────────────────────────────────────────
check-be: check-be-types
	@echo "✅ Backend OK"

check-be-types:
	@echo "--- Backend: TypeScript type check (tsc --noEmit) ---"
	cd backend && npx tsc --noEmit
	@echo "✅ Backend types OK"

# ─────────────────────────────────────────────────────────────────────────────
# Frontend checks
# ─────────────────────────────────────────────────────────────────────────────
check-fe: check-fe-analyze
	@echo "✅ Frontend OK"

check-fe-analyze:
	@echo "--- Frontend: Flutter analyze ---"
	cd frontend && flutter analyze --no-fatal-infos
	@echo "✅ Flutter analyze OK"

# ─────────────────────────────────────────────────────────────────────────────
# Build checks (slower — run before deploy)
# ─────────────────────────────────────────────────────────────────────────────
build-be:
	@echo "--- Backend: tsc build ---"
	cd backend && npm run build
	@echo "✅ Backend build OK"

build-fe:
	@echo "--- Frontend: flutter build web (debug) ---"
	cd frontend && flutter build web --debug
	@echo "✅ Frontend build OK"

build: build-be build-fe
	@echo "✅ Full build OK"

# ─────────────────────────────────────────────────────────────────────────────
# Dev helpers
# ─────────────────────────────────────────────────────────────────────────────
seed-db:
	@echo "--- Seeding MongoDB with 3,595 questions ---"
	cd backend && npm run seed

# Quick smoke test: are the REST endpoints responding?
smoke-test:
	@echo "--- Smoke test: backend REST endpoints ---"
	curl -sf http://localhost:3000/api/subjects | python3 -m json.tool
	@echo "✅ /api/subjects OK"
	curl -sf -X POST http://localhost:3000/api/rooms \
	  -H 'Content-Type: application/json' \
	  -d '{"subject":"history","maxPlayers":2}' | python3 -m json.tool
	@echo "✅ POST /api/rooms OK"

help:
	@echo "Available targets:"
	@echo "  make check          — run all type/lint checks (BE + FE)"
	@echo "  make check-be       — TypeScript tsc --noEmit only"
	@echo "  make check-fe       — Flutter analyze only"
	@echo "  make build          — full tsc + flutter build web"
	@echo "  make seed-db        — seed MongoDB from data-set/questions/all.json"
	@echo "  make smoke-test     — curl BE endpoints (server must be running)"
```

### How AI agents should use the Makefile

After writing any file, run:
```bash
make check
```

If `make check-be` fails:
1. Read the TypeScript errors (exact file + line numbers are shown)
2. Fix the reported errors
3. Run `make check-be` again — repeat until it passes
4. Then run `make check-fe`

If `make check-fe` fails:
1. Read the Flutter analyzer output (exact file + line numbers are shown)
2. Fix reported errors — common causes:
   - Missing `import` statements
   - Wrong type in `fromJson` parsing
   - Deprecated APIs (check the "use X instead" hint)
3. Run `make check-fe` again — repeat until it passes

**Never advance to the next phase with a failing `make check`.**

---

## Final Verification Checklist (Phase 4 Gate)

- [ ] `make seed-db` → Supabase shows 3,595 rows in `questions` table (`SELECT COUNT(*) FROM questions` via MCP)
- [ ] `make smoke-test` (with backend running) → both endpoints return valid JSON
- [ ] Open two browser tabs → both join same room → both see lobby with their names
- [ ] Creator taps "Почати гру" → both see first question (no `correct_answer_index` in payload — verify in DevTools Network tab)
- [ ] Both answer → `round:reveal` fires immediately with correct answer + score delta
- [ ] Let timer run out → `round:reveal` fires after 5 minutes
- [ ] Close one tab mid-game → game continues for remaining player
- [ ] Open `/room/A9X` directly in new tab → auto-joins lobby
- [ ] Mobile viewport (375px) → vertical stacked layout, readable
- [ ] Desktop viewport (1200px+) → 70/30 split layout
- [ ] `make build` passes with no errors
- [ ] Deploy → test full game flow on production URLs
