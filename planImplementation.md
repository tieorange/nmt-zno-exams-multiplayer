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

### 0.1 Backend

```bash
mkdir backend && cd backend
npm init -y
npm install express socket.io mongoose nanoid zod pino pino-pretty cors helmet express-rate-limit dotenv uuid
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
MONGODB_URI=mongodb+srv://USER:PASS@cluster.mongodb.net/nmt-quiz
CORS_ORIGIN=http://localhost:5000
NODE_ENV=development
LOG_LEVEL=info
```

> **⚠️ Before running any backend command:** copy and fill in your `.env` file:
> ```bash
> cp .env.example .env
> # Edit .env → set MONGODB_URI from your MongoDB Atlas connection string
> # Without this, the server crashes on startup with "URI missing"
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
flutter pub add flutter_bloc fpdart go_router socket_io_client flutter_animate percent_indicator confetti logger equatable url_launcher shadcn_flutter http
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

### 1.3 MongoDB Connection

**`src/config/db.ts`**:
```typescript
import mongoose from 'mongoose';
import { logger } from './logger.js';

export async function connectDB(): Promise<void> {
  const uri = process.env.MONGODB_URI!;
  await mongoose.connect(uri);
  logger.info('[DB] Connected to MongoDB');
}
```

### 1.4 Mongoose Models

**`src/data/models/QuestionModel.ts`**:
```typescript
import mongoose from 'mongoose';

const questionSchema = new mongoose.Schema(
  {
    _id: String,           // uses the JSON "id" field directly (e.g. "osy_history_42")
    subject: { type: String, required: true, index: true },
    text: { type: String, required: true },
    choices: [String],
    correct_answer_index: { type: Number, required: true },
    exam_type: String,
  },
  { _id: false }           // disable auto ObjectId, we supply _id from the JSON id field
);

questionSchema.index({ subject: 1 });

export const QuestionModel = mongoose.model('Question', questionSchema, 'questions');
```

**`src/data/models/RoomModel.ts`**:
```typescript
import mongoose from 'mongoose';

const playerSchema = new mongoose.Schema({
  id: String,              // generated player UUID
  socketId: String,        // current socket connection id
  name: String,
  color: String,
  score: { type: Number, default: 0 },
  isCreator: Boolean,
  joinedAt: Date,
  lastSeen: Date,
}, { _id: false });

const roomSchema = new mongoose.Schema({
  code: { type: String, required: true, unique: true },
  subject: { type: String, required: true },
  status: { type: String, enum: ['waiting', 'playing', 'finished'], default: 'waiting' },
  maxPlayers: { type: Number, required: true },
  players: [playerSchema],
  questionIds: [String],
  currentQuestionIndex: { type: Number, default: 0 },
  roundStartedAt: Date,
  createdAt: { type: Date, default: Date.now },
});

// Auto-delete rooms 1 hour after creation
roomSchema.index({ createdAt: 1 }, { expireAfterSeconds: 3600 });

export const RoomModel = mongoose.model('Room', roomSchema, 'rooms');
```

### 1.5 Seed Script

**`src/scripts/seed.ts`**:
```typescript
import 'dotenv/config';
import mongoose from 'mongoose';
import { readFileSync } from 'fs';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';
import { QuestionModel } from '../data/models/QuestionModel.js';
import { logger } from '../config/logger.js';

const __dirname = dirname(fileURLToPath(import.meta.url));
const JSON_PATH = join(__dirname, '../../../data-set/questions/all.json');

async function seed() {
  await mongoose.connect(process.env.MONGODB_URI!);
  logger.info('[Seed] Connected to MongoDB');

  const raw = JSON.parse(readFileSync(JSON_PATH, 'utf-8')) as Array<{
    id: string; subject: string; text: string;
    choices: string[]; correct_answer_index: number; exam_type: string;
  }>;
  logger.info(`[Seed] Loaded ${raw.length} questions from JSON`);

  const BATCH = 500;
  for (let i = 0; i < raw.length; i += BATCH) {
    const batch = raw.slice(i, i + BATCH);
    await QuestionModel.bulkWrite(
      batch.map((q) => ({
        updateOne: {
          filter: { _id: q.id },
          update: { $set: { subject: q.subject, text: q.text, choices: q.choices, correct_answer_index: q.correct_answer_index, exam_type: q.exam_type } },
          upsert: true,
        },
      }))
    );
    logger.info(`[Seed] Progress: ${Math.min(i + BATCH, raw.length)} / ${raw.length}`);
  }

  logger.info('[Seed] Done. Creating subject index...');
  await QuestionModel.collection.createIndex({ subject: 1 });
  logger.info('[Seed] Index created. Disconnecting.');
  await mongoose.disconnect();
}

seed().catch((e) => { logger.error(e, '[Seed] Failed'); process.exit(1); });
```

Run: `cd backend && npm run seed`

Expected output:
```
[Seed] Connected to MongoDB
[Seed] Loaded 3595 questions from JSON
[Seed] Progress: 500 / 3595
...
[Seed] Progress: 3595 / 3595
[Seed] Done. Creating subject index...
[Seed] Index created. Disconnecting.
```

If you see errors, check `MONGODB_URI` in `backend/.env`.

### 1.6 Services

**`src/services/CodeGenerator.ts`**:
```typescript
import { customAlphabet } from 'nanoid';
import { RoomModel } from '../data/models/RoomModel.js';

const gen = customAlphabet('ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789', 3);

export async function generateUniqueCode(): Promise<string> {
  for (let attempt = 0; attempt < 10; attempt++) {
    const code = gen();
    const existing = await RoomModel.findOne({ code });
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

**`src/presentation/validators/socketSchemas.ts`**:
```typescript
import { z } from 'zod';

export const JoinRoomSchema = z.object({
  roomCode: z.string().length(3).toUpperCase(),
});

export const SubmitAnswerSchema = z.object({
  questionId: z.string().min(1),
  answerIndex: z.number().int().min(0).max(4),
});

export const CreateRoomSchema = z.object({
  subject: z.enum(['ukrainian_language', 'history', 'geography', 'math']),
  maxPlayers: z.number().int().min(1).max(4),
});
```

### 1.8 REST Routes

**`src/presentation/controllers/SubjectController.ts`**:
```typescript
import { Request, Response } from 'express';
import { SUBJECTS } from '../../domain/types.js';

export function getSubjects(_req: Request, res: Response) {
  res.json({ subjects: SUBJECTS });
}
```

**`src/presentation/controllers/RoomController.ts`**:
```typescript
import { Request, Response } from 'express';
import { RoomModel } from '../../data/models/RoomModel.js';
import { generateUniqueCode } from '../../services/CodeGenerator.js';
import { CreateRoomSchema } from '../validators/socketSchemas.js';
import { logger } from '../../config/logger.js';

export async function createRoom(req: Request, res: Response) {
  const parsed = CreateRoomSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });

  const { subject, maxPlayers } = parsed.data;
  const code = await generateUniqueCode();

  // Do NOT create a player here — players are created when they connect via socket.
  // Creating a player here AND on socket join caused duplicate player entries.
  const room = await RoomModel.create({ code, subject, maxPlayers, players: [] });

  logger.info(`[RoomController] Room created | code=${code} subject=${subject} maxPlayers=${maxPlayers}`);
  res.status(201).json({ code, roomId: room._id });
}

export async function getRoom(req: Request, res: Response) {
  const room = await RoomModel.findOne({ code: req.params.code.toUpperCase() });
  if (!room) return res.status(404).json({ error: 'Room not found' });

  // Strip sensitive data
  const safe = {
    code: room.code,
    subject: room.subject,
    status: room.status,
    maxPlayers: room.maxPlayers,
    currentQuestionIndex: room.currentQuestionIndex,
    players: room.players.map((p) => ({
      id: p.id, name: p.name, color: p.color, score: p.score, isCreator: p.isCreator,
    })),
  };
  res.json(safe);
}
```

**`src/presentation/routes/index.ts`**:
```typescript
import { Router } from 'express';
import rateLimit from 'express-rate-limit';
import { getSubjects } from '../controllers/SubjectController.js';
import { createRoom, getRoom } from '../controllers/RoomController.js';

const router = Router();

const roomCreationLimit = rateLimit({
  windowMs: 15 * 60 * 1000,  // 15 minutes
  max: 10,
  message: { error: 'Too many rooms created. Please try again later.' },
});

router.get('/subjects', getSubjects);
router.post('/rooms', roomCreationLimit, createRoom);
router.get('/rooms/:code', getRoom);

export default router;
```

### 1.9 Main Entry Point

**`src/main.ts`**:
```typescript
import 'dotenv/config';
import express from 'express';
import { createServer } from 'http';
import cors from 'cors';
import helmet from 'helmet';
import { connectDB } from './config/db.js';
import { logger } from './config/logger.js';
import routes from './presentation/routes/index.js';
import { setupSocketIO } from './presentation/handlers/SocketHandler.js';

const app = express();
const httpServer = createServer(app);

app.use(cors({ origin: process.env.CORS_ORIGIN || '*' }));
app.use(helmet());
app.use(express.json());
app.use('/api', routes);

async function start() {
  await connectDB();
  setupSocketIO(httpServer);
  const PORT = process.env.PORT || 3000;
  httpServer.listen(PORT, () => logger.info(`[Server] Listening on port ${PORT}`));
}

start().catch((e) => { logger.error(e, '[Server] Fatal startup error'); process.exit(1); });
```

---

### ✅ Phase 1 Gate Check

```bash
# Dev server starts without errors
cd backend && npm run dev
# Should print: [Server] Listening on port 3000

# In a new terminal — test REST endpoints:
curl http://localhost:3000/api/subjects
# Expected: { "subjects": [{ "key": "ukrainian_language", ... }, ...] }

curl -X POST http://localhost:3000/api/rooms \
  -H 'Content-Type: application/json' \
  -d '{"subject":"history","maxPlayers":2}'
# Expected: { "code": "A9X", "roomId": "..." }
# Note: no creatorName/creatorColor — player identity is assigned on socket join, not here

# Save the code from above and test:
curl http://localhost:3000/api/rooms/A9X
# Expected: room object WITHOUT correct_answer_index anywhere in it

# Verify question count in DB — check server log output from seed:
# Should show 3595 questions seeded
```

All 3 curl commands must return valid JSON. No 500 errors. Stop the dev server after verifying.

---

## Phase 2 — Real-time Game Engine

### 2.0 Shared IO State (breaks circular dependency)

> **Why this exists:** `GameEngine` needs the `io` server instance to emit events. Without this file, `GameEngine` would import from `SocketHandler` and `SocketHandler` would import from `GameEngine` → circular dep → `io` is `undefined` at runtime.

**`src/presentation/handlers/ioState.ts`**:
```typescript
import { Server } from 'socket.io';

// Shared singleton — set once in setupSocketIO(), read everywhere else
export let io: Server;
export const socketSessions = new Map<string, { playerId: string; roomCode: string }>();

export function setIO(instance: Server): void {
  io = instance;
}
```

### 2.1 Socket.io Setup

**`src/presentation/handlers/SocketHandler.ts`**:
```typescript
import { Server } from 'socket.io';
import { Server as HTTPServer } from 'http';
import { logger } from '../../config/logger.js';
import { registerRoomHandlers } from './RoomSocketHandler.js';
import { registerGameHandlers } from './GameSocketHandler.js';
import { setIO, socketSessions } from './ioState.js';
import { handleDisconnect } from '../../services/GameEngine.js';

export function setupSocketIO(httpServer: HTTPServer) {
  const io = new Server(httpServer, {
    cors: { origin: process.env.CORS_ORIGIN || '*' },
    pingInterval: 25000,
    pingTimeout: 20000,
    transports: ['websocket', 'polling'],
  });

  // Store in shared state so GameEngine can emit without circular import
  setIO(io);

  io.on('connection', (socket) => {
    logger.info(`[SocketHandler] Client connected | socketId=${socket.id}`);

    registerRoomHandlers(io, socket);
    registerGameHandlers(io, socket);

    socket.on('disconnect', async (reason) => {
      const session = socketSessions.get(socket.id);
      if (!session) return;
      logger.warn(`[SocketHandler] Client disconnected | socketId=${socket.id} reason=${reason} roomCode=${session.roomCode} playerId=${session.playerId}`);
      await handleDisconnect(socket.id, session);
      socketSessions.delete(socket.id);
    });
  });

  logger.info('[SocketHandler] Socket.io server initialized');
}
```

### 2.2 Room Socket Handler

**`src/presentation/handlers/RoomSocketHandler.ts`**:
```typescript
import { Server, Socket } from 'socket.io';
import { v4 as uuid } from 'uuid';
import { RoomModel } from '../../data/models/RoomModel.js';
import { assignName } from '../../services/NameGenerator.js';
import { JoinRoomSchema } from '../validators/socketSchemas.js';
import { socketSessions } from './ioState.js';
import { logger } from '../../config/logger.js';

export function registerRoomHandlers(io: Server, socket: Socket) {
  socket.on('room:join', async (payload: unknown) => {
    logger.info(`[RoomSocketHandler] room:join received | socketId=${socket.id} payload=${JSON.stringify(payload)}`);

    const parsed = JoinRoomSchema.safeParse(payload);
    if (!parsed.success) {
      socket.emit('error', { message: 'Invalid room code format' });
      return;
    }

    const { roomCode } = parsed.data;
    const room = await RoomModel.findOne({ code: roomCode });

    if (!room) {
      socket.emit('error', { message: 'Кімнату не знайдено' });
      return;
    }
    if (room.status !== 'waiting') {
      socket.emit('error', { message: 'Гра вже почалась' });
      return;
    }
    if (room.players.length >= room.maxPlayers) {
      socket.emit('error', { message: 'Кімната заповнена' });
      return;
    }

    const { name, color } = assignName(roomCode);
    const playerId = uuid();
    // First player to join via socket becomes the creator.
    // The REST endpoint creates the room with 0 players to avoid duplication.
    const isCreator = room.players.length === 0;

    room.players.push({ id: playerId, socketId: socket.id, name, color, score: 0, isCreator, joinedAt: new Date(), lastSeen: new Date() });
    await room.save();

    socketSessions.set(socket.id, { playerId, roomCode });
    socket.join(roomCode);

    logger.info(`[RoomSocketHandler] Player joined | roomCode=${roomCode} playerId=${playerId} name="${name}" isCreator=${isCreator}`);

    // Tell this socket its own identity (needed for QuizCubit to track "my" answers)
    socket.emit('room:joined', { playerId, name, color, isCreator });

    // Broadcast updated room state to ALL players in room (including the new one)
    io.to(roomCode).emit('room:state', buildRoomState(room));
  });
}

function buildRoomState(room: any) {
  return {
    code: room.code,
    subject: room.subject,
    status: room.status,
    maxPlayers: room.maxPlayers,
    players: room.players.map((p: any) => ({
      id: p.id, name: p.name, color: p.color, score: p.score, isCreator: p.isCreator,
    })),
  };
}
```

### 2.3 Game Engine

**`src/services/GameEngine.ts`**:
```typescript
// Import io from ioState (not from SocketHandler) to avoid circular dependency.
// SocketHandler → GameEngine → ioState  (no cycle)
import { io, socketSessions } from '../presentation/handlers/ioState.js';
import { RoomModel } from '../data/models/RoomModel.js';
import { QuestionModel } from '../data/models/QuestionModel.js';
import { clearRoom } from './NameGenerator.js';
import { logger } from '../config/logger.js';

const QUESTION_COUNT = 10;
const ROUND_TIMER_MS = 5 * 60 * 1000; // 5 minutes
const REVEAL_DELAY_MS = 3000;
const CORRECT_ANSWER_POINTS = 10;

// In-memory: roomCode → { answers: Map<playerId, number|null>, timer: NodeJS.Timeout }
const roundState = new Map<string, { answers: Map<string, number | null>; timer: NodeJS.Timeout }>();

export async function startGame(roomCode: string): Promise<void> {
  const room = await RoomModel.findOne({ code: roomCode });
  if (!room || room.status !== 'waiting') return;

  // Sample random questions — order is preserved in questionIds
  const questions = await QuestionModel.aggregate([
    { $match: { subject: room.subject } },
    { $sample: { size: QUESTION_COUNT } },
  ]);

  room.questionIds = questions.map((q) => q._id as string);
  room.status = 'playing';
  room.currentQuestionIndex = 0;
  await room.save();

  logger.info(`[GameEngine] Game started | roomCode=${roomCode} questions=${QUESTION_COUNT}`);
  io.to(roomCode).emit('game:start', { totalQuestions: QUESTION_COUNT });

  await startRound(roomCode, 0, questions);
}

async function startRound(roomCode: string, questionIndex: number, questions: any[]) {
  const room = await RoomModel.findOne({ code: roomCode });
  if (!room || room.status !== 'playing') return;

  const questionDoc = questions[questionIndex];
  room.currentQuestionIndex = questionIndex;
  room.roundStartedAt = new Date();
  await room.save();

  // Send question WITHOUT correct_answer_index — security critical
  const clientQuestion = {
    id: questionDoc._id,
    subject: questionDoc.subject,
    text: questionDoc.text,
    choices: questionDoc.choices,
  };

  logger.info(`[GameEngine] Round started | roomCode=${roomCode} questionIndex=${questionIndex} questionId=${questionDoc._id}`);
  io.to(roomCode).emit('question:new', clientQuestion);

  // Initialize answer tracking for all players
  const answers = new Map<string, number | null>();
  room.players.forEach((p: any) => answers.set(p.id, null));

  const timer = setTimeout(() => revealRound(roomCode, questionIndex, questions), ROUND_TIMER_MS);
  roundState.set(roomCode, { answers, timer });
}

export async function submitAnswer(roomCode: string, playerId: string, questionId: string, answerIndex: number) {
  const state = roundState.get(roomCode);
  if (!state || state.answers.get(playerId) !== null) return; // Already answered or no active round

  const room = await RoomModel.findOne({ code: roomCode });
  if (!room || room.questionIds[room.currentQuestionIndex] !== questionId) return;

  const timeTakenMs = Date.now() - (room.roundStartedAt?.getTime() ?? Date.now());
  state.answers.set(playerId, answerIndex);
  logger.info(`[GameEngine] Answer recv | roomCode=${roomCode} playerId=${playerId} answerIndex=${answerIndex} timeTakenMs=${timeTakenMs}`);

  // Broadcast updated answers (without revealing correct one)
  io.to(roomCode).emit('round:update', { playerAnswers: Object.fromEntries(state.answers) });

  // Check if all active players answered
  const room2 = await RoomModel.findOne({ code: roomCode });
  const activePlayers = room2!.players.filter((p: any) => p.socketId);
  const allAnswered = activePlayers.every((p: any) => state.answers.get(p.id) !== null);
  if (allAnswered) {
    clearTimeout(state.timer);
    // IMPORTANT: use fetchQuestions which preserves questionIds order (not sorted by _id)
    const questions = await fetchQuestionsOrdered(room2!.questionIds);
    await revealRound(roomCode, room2!.currentQuestionIndex, questions);
  }
}

async function revealRound(roomCode: string, questionIndex: number, questions: any[]) {
  const state = roundState.get(roomCode);
  const room = await RoomModel.findOne({ code: roomCode });
  if (!room || !state) return;

  const questionDoc = questions[questionIndex];
  const correctIndex = questionDoc.correct_answer_index;
  const unanswered = [...state.answers.entries()].filter(([, v]) => v === null).map(([k]) => k);

  if (unanswered.length > 0) {
    logger.warn(`[GameEngine] Timer expired | roomCode=${roomCode} questionIndex=${questionIndex} unanswered=${JSON.stringify(unanswered)}`);
  }

  // Update scores
  const scores: Record<string, number> = {};
  for (const player of room.players) {
    const answer = state.answers.get(player.id as string);
    const isCorrect = answer === correctIndex;
    if (isCorrect) player.score += CORRECT_ANSWER_POINTS;
    scores[player.id as string] = player.score;
  }
  await room.save();

  logger.info(`[GameEngine] Round reveal | roomCode=${roomCode} correctIndex=${correctIndex} scores=${JSON.stringify(scores)}`);
  io.to(roomCode).emit('round:reveal', {
    correctIndex,
    playerAnswers: Object.fromEntries(state.answers),
    scores,
  });

  roundState.delete(roomCode);

  // Advance to next question after delay
  setTimeout(async () => {
    if (questionIndex + 1 >= QUESTION_COUNT) {
      await endGame(roomCode, room.players);
    } else {
      await startRound(roomCode, questionIndex + 1, questions);
    }
  }, REVEAL_DELAY_MS);
}

async function endGame(roomCode: string, players: any[]) {
  await RoomModel.updateOne({ code: roomCode }, { $set: { status: 'finished' } });

  const scoreboard = [...players]
    .sort((a, b) => b.score - a.score)
    .map((p, i) => ({ rank: i + 1, id: p.id, name: p.name, color: p.color, score: p.score }));

  logger.info(`[GameEngine] Game ended | roomCode=${roomCode} scoreboard=${JSON.stringify(scoreboard)}`);
  io.to(roomCode).emit('game:end', { scoreboard });
}

// Returns questions in the SAME ORDER as questionIds (the original $sample order).
// Do NOT use .sort({_id:1}) — that would change the order and cause wrong correct_answer_index lookups.
async function fetchQuestionsOrdered(questionIds: string[]) {
  const docs = await QuestionModel.find({ _id: { $in: questionIds } }).lean();
  const docMap = new Map(docs.map((d) => [d._id as string, d]));
  return questionIds.map((id) => docMap.get(id)!);
}

export async function handleDisconnect(socketId: string, session: { playerId: string; roomCode: string }) {
  const { playerId, roomCode } = session;
  const room = await RoomModel.findOne({ code: roomCode });
  if (!room) return;

  const player = room.players.find((p: any) => p.id === playerId);
  if (player) {
    player.socketId = '';
    player.lastSeen = new Date();
  }

  // If all players gone, schedule room cleanup
  const anyConnected = room.players.some((p: any) => p.socketId !== '');
  if (!anyConnected) {
    setTimeout(async () => {
      const r = await RoomModel.findOne({ code: roomCode });
      if (r && !r.players.some((p: any) => p.socketId !== '')) {
        await RoomModel.deleteOne({ code: roomCode });
        clearRoom(roomCode); // free in-memory name tracking
        logger.info(`[GameEngine] Room cleaned up | roomCode=${roomCode}`);
      }
    }, 60_000);
  }

  // Assign creator to next player if creator disconnected
  if (player?.isCreator) {
    const nextPlayer = room.players.find((p: any) => p.id !== playerId && p.socketId !== '');
    if (nextPlayer) {
      player.isCreator = false;
      nextPlayer.isCreator = true;
      logger.info(`[GameEngine] Creator reassigned | roomCode=${roomCode} newCreator=${nextPlayer.id}`);
    }
  }

  await room.save();

  io.to(roomCode).emit('player:disconnected', { playerId });
  logger.warn(`[RoomService] Player disc. | roomCode=${roomCode} playerId=${playerId}`);

  // If mid-game and all remaining players answered, trigger early reveal
  const state = roundState.get(roomCode);
  if (state && room.status === 'playing') {
    const stillActive = room.players.filter((p: any) => p.socketId !== '');
    const allAnswered = stillActive.every((p: any) => state.answers.get(p.id) !== null);
    if (allAnswered && stillActive.length > 0) {
      clearTimeout(state.timer);
      const questions = await fetchQuestionsOrdered(room.questionIds);
      await revealRound(roomCode, room.currentQuestionIndex, questions);
    }
  }
}
```

### 2.4 Game Socket Handler

**`src/presentation/handlers/GameSocketHandler.ts`**:
```typescript
import { Server, Socket } from 'socket.io';
import { socketSessions } from './ioState.js';
import { startGame, submitAnswer } from '../../services/GameEngine.js';
import { SubmitAnswerSchema } from '../validators/socketSchemas.js';
import { RoomModel } from '../../data/models/RoomModel.js';
import { logger } from '../../config/logger.js';

export function registerGameHandlers(io: Server, socket: Socket) {
  socket.on('game:start', async () => {
    const session = socketSessions.get(socket.id);
    if (!session) return;

    const room = await RoomModel.findOne({ code: session.roomCode });
    const player = room?.players.find((p: any) => p.id === session.playerId);
    if (!player?.isCreator) {
      socket.emit('error', { message: 'Тільки творець може почати гру' });
      return;
    }

    logger.info(`[GameSocketHandler] game:start received | roomCode=${session.roomCode}`);
    await startGame(session.roomCode);
  });

  socket.on('player:answer', async (payload: unknown) => {
    const session = socketSessions.get(socket.id);
    if (!session) return;

    const parsed = SubmitAnswerSchema.safeParse(payload);
    if (!parsed.success) {
      socket.emit('error', { message: 'Invalid answer format' });
      return;
    }

    logger.info(`[GameSocketHandler] player:answer received | roomCode=${session.roomCode} playerId=${session.playerId} answerIndex=${parsed.data.answerIndex}`);
    await submitAnswer(session.roomCode, session.playerId, parsed.data.questionId, parsed.data.answerIndex);
  });
}
```

---

### ✅ Phase 2 Gate Check

Start the backend server (`cd backend && npm run dev`), then test the full Socket.io flow manually using two browser console sessions, or write a quick Node.js test script:

```typescript
// test_socket.mjs — run with: node test_socket.mjs
// Tests: join → room:joined identity → lobby → game:start (both directions) → question → answer → round:update → round:reveal
import { io } from 'socket.io-client';

const ROOM_CODE = 'A9X'; // replace with a code from Phase 1 gate check

const s1 = io('http://localhost:3000');
const s2 = io('http://localhost:3000');

let s1PlayerId = null;
let s1RoomJoined = false;

// ── s1 (creator — first to join) ─────────────────────────────
s1.on('connect', () => {
  console.log('[s1] connected');
  s1.emit('room:join', { roomCode: ROOM_CODE });
});

s1.on('room:joined', (data) => {
  s1PlayerId = data.playerId;
  console.log('[s1] room:joined ✅ | playerId=' + data.playerId + ' name=' + data.name + ' isCreator=' + data.isCreator);
  if (!data.isCreator) console.error('[s1] ERROR: s1 should be creator but isCreator=false!');
  s1RoomJoined = true;
});

s1.on('room:state', (data) => {
  console.log('[s1] room:state | players=' + data.players.length);
  // Once both players have joined, s1 (creator) starts the game
  if (data.players.length === 2 && s1RoomJoined) {
    console.log('[s1] Both players in lobby — emitting game:start');
    s1.emit('game:start', {});
  }
});

// game:start is also broadcast server→all once game begins
s1.on('game:start', (data) => {
  console.log('[s1] game:start received ✅ | totalQuestions=' + data.totalQuestions);
});

s1.on('question:new', (q) => {
  const hasCorrect = 'correct_answer_index' in q;
  console.log('[s1] question:new ✅ | id=' + q.id + ' has correct_answer_index? ' + hasCorrect);
  if (hasCorrect) console.error('[s1] SECURITY VIOLATION: correct_answer_index exposed in question:new!');
  s1.emit('player:answer', { questionId: q.id, answerIndex: 0 });
});

s1.on('round:update', (data) => {
  // Fires after each player answers — shows partial results before all have answered
  console.log('[s1] round:update ✅ | playerAnswers=' + JSON.stringify(data.playerAnswers));
});

s1.on('round:reveal', (data) => {
  console.log('[s1] round:reveal ✅ | correctIndex=' + data.correctIndex + ' scores=' + JSON.stringify(data.scores));
  console.log('[s1] All checks passed — exiting');
  process.exit(0);
});

// ── s2 (second player — not creator) ─────────────────────────
s2.on('connect', () => {
  console.log('[s2] connected');
  s2.emit('room:join', { roomCode: ROOM_CODE });
});

s2.on('room:joined', (data) => {
  console.log('[s2] room:joined ✅ | playerId=' + data.playerId + ' name=' + data.name + ' isCreator=' + data.isCreator);
  if (data.isCreator) console.error('[s2] ERROR: s2 should NOT be creator but isCreator=true!');
});

s2.on('question:new', (q) => {
  s2.emit('player:answer', { questionId: q.id, answerIndex: 1 });
});

setTimeout(() => { console.error('TIMEOUT: test did not complete in 30s'); process.exit(1); }, 30000);
```

Checklist before moving on:
- [ ] `room:joined` fires on join with `{ playerId, name, color, isCreator }` — only to the joining socket
- [ ] First socket to join has `isCreator: true`; second has `isCreator: false`
- [ ] Two players can join the same room (both see `room:state` with 2 players)
- [ ] `game:start` (client→server) triggers game; `game:start` (server→all) broadcasts `{ totalQuestions: 10 }`
- [ ] `question:new` payload does **NOT** contain `correct_answer_index`
- [ ] `round:update` fires with `{ playerAnswers }` after each player answers (before all answered)
- [ ] `round:reveal` fires when all players answer — contains `correctIndex`, `playerAnswers`, `scores`
- [ ] `round:reveal` fires after 5-minute timer (temporarily reduce `ROUND_TIMER_MS` for testing)
- [ ] Disconnecting a player broadcasts `player:disconnected` to remaining players

---

## Phase 3 — Flutter Frontend

### 3.1 SocketService

**`lib/services/socket_service.dart`**:
```dart
import 'dart:async';
import 'package:logger/logger.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

// roomJoined: server sends this only to the joining socket — tells you your own playerId/name/color
enum SocketEventType { roomJoined, roomState, gameStart, questionNew, roundUpdate, roundReveal, gameEnd, playerDisconnected, error }

class SocketEvent {
  final SocketEventType type;
  final Map<String, dynamic> data;
  const SocketEvent(this.type, this.data);
}

class SocketService {
  late io.Socket socket;
  final Logger logger;
  final _controller = StreamController<SocketEvent>.broadcast();

  Stream<SocketEvent> get events => _controller.stream;

  SocketService({required this.logger});

  void connect(String serverUrl) {
    socket = io.io(serverUrl, io.OptionBuilder()
      .setTransports(['websocket'])
      .enableReconnection()
      .setReconnectionAttempts(5)
      .setReconnectionDelay(1000)
      .build());

    socket.onConnect((_) => logger.i('[SocketService] connected | url=$serverUrl'));
    socket.onDisconnect((_) => logger.w('[SocketService] disconnected'));
    socket.onConnectError((e) => logger.e('[SocketService] ERROR connect failed | err=$e'));
    socket.onReconnecting((attempt) => logger.i('[SocketService] reconnecting... | attempt=$attempt'));

    socket.on('room:joined',        (d) => _emit(SocketEventType.roomJoined, d));
    socket.on('room:state',         (d) => _emit(SocketEventType.roomState, d));
    socket.on('game:start',         (d) => _emit(SocketEventType.gameStart, d));
    socket.on('question:new',       (d) => _emit(SocketEventType.questionNew, d));
    socket.on('round:update',       (d) => _emit(SocketEventType.roundUpdate, d));
    socket.on('round:reveal',       (d) => _emit(SocketEventType.roundReveal, d));
    socket.on('game:end',           (d) => _emit(SocketEventType.gameEnd, d));
    socket.on('player:disconnected',(d) => _emit(SocketEventType.playerDisconnected, d));
    socket.on('error',              (d) => _emit(SocketEventType.error, d));
  }

  void _emit(SocketEventType type, dynamic data) {
    logger.i('[SocketService] event received | type=${type.name} data=$data');
    _controller.add(SocketEvent(type, Map<String, dynamic>.from(data ?? {})));
  }

  void emit(String event, Map<String, dynamic> data) {
    logger.i('[SocketService] emit | event=$event data=$data');
    socket.emit(event, data);
  }

  void dispose() {
    socket.dispose();
    _controller.close();
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
import '../../../services/socket_service.dart';
import 'room_state.dart';

class RoomCubit extends Cubit<RoomState> {
  final SocketService socketService;
  final Logger logger;
  late StreamSubscription<SocketEvent> _sub;

  // Populated on room:joined — used by QuizCubit to identify "my" answers
  String? myPlayerId;

  RoomCubit({required this.socketService, required this.logger}) : super(const RoomState()) {
    _sub = socketService.events.listen(_handleEvent);
  }

  void joinRoom(String roomCode) {
    logger.i('[RoomCubit] joining room | roomCode=$roomCode');
    socketService.emit('room:join', {'roomCode': roomCode.toUpperCase()});
  }

  void startGame() {
    logger.i('[RoomCubit] emitting game:start');
    socketService.emit('game:start', {});
  }

  void _handleEvent(SocketEvent event) {
    switch (event.type) {
      case SocketEventType.roomJoined:
        // Only this socket receives this — tells us our own identity
        myPlayerId = event.data['playerId'] as String?;
        logger.i('[RoomCubit] room:joined | myPlayerId=$myPlayerId name=${event.data['name']}');
        break;
      case SocketEventType.roomState:
        _handleRoomState(event.data);
        break;
      case SocketEventType.gameStart:
        logger.i('[RoomCubit] game:start received | transitioning to playing');
        emit(state.copyWith(status: RoomStatus.playing));
        break;
      case SocketEventType.playerDisconnected:
        final playerId = event.data['playerId'] as String?;
        logger.w('[RoomCubit] player disconnected | playerId=$playerId');
        if (playerId != null) {
          emit(state.copyWith(players: state.players.where((p) => p.id != playerId).toList()));
        }
        break;
      case SocketEventType.error:
        final msg = event.data['message'] as String? ?? 'Невідома помилка';
        logger.e('[RoomCubit] ERROR received | message=$msg');
        emit(state.copyWith(status: RoomStatus.error, errorMessage: msg));
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
    logger.i('[RoomCubit] room:state updated | status=$statusStr players=${players.length} currentQ=${data['currentQuestionIndex'] ?? 0}/${data['totalQuestions'] ?? 10}');
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
import '../../../services/socket_service.dart';
import 'quiz_state.dart';

class QuizCubit extends Cubit<QuizState> {
  final SocketService socketService;
  final Logger logger;
  late StreamSubscription<SocketEvent> _sub;
  Timer? _timer;
  ClientQuestion? _currentQuestion;
  String? _myPlayerId;
  int _questionIndex = 0;
  int _totalQuestions = 10;

  QuizCubit({required this.socketService, required this.logger}) : super(const QuizInitial()) {
    _sub = socketService.events.listen(_handleEvent);
  }

  void setMyPlayerId(String id) => _myPlayerId = id;

  void _handleEvent(SocketEvent event) {
    switch (event.type) {
      case SocketEventType.gameStart:
        _totalQuestions = event.data['totalQuestions'] as int? ?? 10;
        _questionIndex = 0;
        break;
      case SocketEventType.questionNew:
        _handleNewQuestion(event.data);
        break;
      case SocketEventType.roundUpdate:
        _handleRoundUpdate(event.data);
        break;
      case SocketEventType.roundReveal:
        _handleReveal(event.data);
        break;
      case SocketEventType.gameEnd:
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

  void submitAnswer(int answerIndex) {
    final s = state;
    if (s is! QuizQuestion) return;
    logger.i('[QuizCubit] answer submitted | questionId=${s.question.id} selectedIndex=$answerIndex');
    socketService.emit('player:answer', {'questionId': s.question.id, 'answerIndex': answerIndex});
    emit(s.copyWith(myAnswer: answerIndex));
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
import 'dart:convert';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:http/http.dart' as http;
import 'package:logger/logger.dart';
import 'game_state.dart';

class GameCubit extends Cubit<GameState> {
  final String apiUrl;
  final Logger logger;

  GameCubit({required this.apiUrl, required this.logger}) : super(const GameInitial());

  Future<void> createRoom(String subject, int maxPlayers) async {
    emit(const GameCreating());
    try {
      final response = await http.post(
        Uri.parse('$apiUrl/api/rooms'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'subject': subject, 'maxPlayers': maxPlayers}),
      );
      if (response.statusCode == 201) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final code = data['code'] as String;
        logger.i('[GameCubit] room created | code=$code');
        emit(GameCreated(code));
      } else {
        logger.e('[GameCubit] ERROR create room failed | status=${response.statusCode} body=${response.body}');
        emit(const GameError('Не вдалося створити кімнату'));
      }
    } catch (e) {
      logger.e('[GameCubit] ERROR network exception | err=$e');
      emit(const GameError('Помилка мережі'));
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
import 'services/socket_service.dart';
import 'presentation/cubits/room_cubit/room_cubit.dart';
import 'presentation/cubits/quiz_cubit/quiz_cubit.dart';
import 'presentation/cubits/game_cubit/game_cubit.dart';

const _apiUrl = String.fromEnvironment('API_URL', defaultValue: 'http://localhost:3000');

void main() {
  final logger = Logger();
  final socketService = SocketService(logger: logger);
  socketService.connect(_apiUrl);

  final roomCubit  = RoomCubit(socketService: socketService, logger: logger);
  final quizCubit  = QuizCubit(socketService: socketService, logger: logger);

  // When RoomCubit gets room:joined, forward myPlayerId to QuizCubit so it
  // can track "my" answer vs others' answers in reveal state.
  roomCubit.stream.listen((_) {
    if (roomCubit.myPlayerId != null) {
      quizCubit.setMyPlayerId(roomCubit.myPlayerId!);
    }
  });

  runApp(
    MultiBlocProvider(
      providers: [
        BlocProvider.value(value: roomCubit),
        BlocProvider.value(value: quizCubit),
        BlocProvider(create: (_) => GameCubit(apiUrl: _apiUrl, logger: logger)),
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

### 4.2 Backend Deploy (Railway)

1. Push `backend/` to GitHub
2. Create Railway project → "Deploy from GitHub repo"
3. Set environment variables in Railway dashboard:
   - `MONGODB_URI` — from MongoDB Atlas connection string
   - `PORT` — Railway auto-sets this
   - `CORS_ORIGIN` — your Firebase Hosting URL
   - `NODE_ENV=production`
4. Railway auto-runs `npm start` → uses `dist/main.js`
5. Set start command to `tsx src/main.ts` for simplicity (no build step needed)

**`backend/railway.json`** (optional, explicit config):
```json
{
  "$schema": "https://railway.app/railway.schema.json",
  "build": { "builder": "NIXPACKS" },
  "deploy": { "startCommand": "npx tsx src/main.ts", "restartPolicyType": "ON_FAILURE" }
}
```

### 4.3 Frontend Deploy (Firebase Hosting)

```bash
# One-time setup
npm install -g firebase-tools
firebase login
firebase init hosting   # public dir: build/web, SPA rewrite: yes

# Deploy
flutter build web --release --web-renderer canvaskit
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

Set `FLUTTER_API_URL` at build time:
```bash
flutter build web --release --dart-define=API_URL=https://your-railway-app.up.railway.app
```

Then in Flutter: `const String apiUrl = String.fromEnvironment('API_URL', defaultValue: 'http://localhost:3000');`

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

- [ ] `make seed-db` → MongoDB shows 3,595 docs, `subject` index exists
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
