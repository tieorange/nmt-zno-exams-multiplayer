import { broadcastToRoom } from '../config/supabase.js';
import {
  getRoom,
  updateRoom,
  getPlayers,
  incrementPlayerScore,
  deleteRoom,
} from '../data/repositories/RoomRepository.js';
import {
  getRandomQuestions,
  getQuestionsByIds,
  type Question,
} from '../data/repositories/QuestionRepository.js';
import { clearRoom } from './NameGenerator.js';
import { logger } from '../config/logger.js';

const QUESTION_COUNT = 10;
// Override with env var for testing (e.g. ROUND_TIMER_MS=10000 for 10s rounds)
const ROUND_TIMER_MS = parseInt(process.env.ROUND_TIMER_MS ?? '') || 5 * 60 * 1000;
const REVEAL_DELAY_MS = parseInt(process.env.REVEAL_DELAY_MS ?? '') || 3000;
const CORRECT_ANSWER_POINTS = 10;

interface RoundState {
  answers: Map<string, number | null>;
  timer: ReturnType<typeof setTimeout>;
  questions: Question[];   // stored here so submitAnswer can validate answerIndex inline
  questionIndex: number;
}

// In-memory: roomCode → round state
// This state lives in Node.js — intentional. Keeps game logic server-authoritative.
const roundState = new Map<string, RoundState>();

// Track cleanup timeouts so we can cancel if a room gets reused
const cleanupTimeouts = new Map<string, ReturnType<typeof setTimeout>>();

export async function startGame(roomCode: string): Promise<void> {
  const room = await getRoom(roomCode);
  if (!room || room.status !== 'waiting') return;

  const questions = await getRandomQuestions(room.subject, QUESTION_COUNT);
  if (questions.length < QUESTION_COUNT) {
    logger.warn(
      `[GameEngine] Not enough questions | roomCode=${roomCode} subject=${room.subject} got=${questions.length} need=${QUESTION_COUNT}`,
    );
  }

  const questionIds = questions.map((q) => q.id);

  // Cancel any leftover cleanup timeout for this room (e.g. restart scenario)
  const existingCleanup = cleanupTimeouts.get(roomCode);
  if (existingCleanup) {
    clearTimeout(existingCleanup);
    cleanupTimeouts.delete(roomCode);
  }

  await updateRoom(roomCode, {
    status: 'playing',
    question_ids: questionIds,
    current_question_index: 0,
  });

  logger.info(
    `[GameEngine] Game started | roomCode=${roomCode} questions=${questions.length}`,
  );

  await safeBroadcast(roomCode, 'game:start', { totalQuestions: questions.length });
  await startRound(roomCode, 0, questions);
}

export async function restartGame(roomCode: string): Promise<void> {
  const room = await getRoom(roomCode);
  if (!room || room.status !== 'finished') return;

  const questions = await getRandomQuestions(room.subject, QUESTION_COUNT);
  if (questions.length < QUESTION_COUNT) {
    logger.warn(`[GameEngine] Not enough questions | roomCode=${roomCode} subject=${room.subject} got=${questions.length} need=${QUESTION_COUNT}`);
  }

  const questionIds = questions.map((q) => q.id);

  const existingCleanup = cleanupTimeouts.get(roomCode);
  if (existingCleanup) {
    clearTimeout(existingCleanup);
    cleanupTimeouts.delete(roomCode);
  }

  await updateRoom(roomCode, {
    status: 'playing',
    question_ids: questionIds,
    current_question_index: 0,
  });

  logger.info(`[GameEngine] Game restarted | roomCode=${roomCode} questions=${questions.length}`);
  await safeBroadcast(roomCode, 'game:start', { totalQuestions: questions.length });
  await startRound(roomCode, 0, questions);
}

async function startRound(
  roomCode: string,
  questionIndex: number,
  questions: Question[],
): Promise<void> {
  const room = await getRoom(roomCode);
  if (!room || room.status !== 'playing') return;

  const questionDoc = questions[questionIndex];
  await updateRoom(roomCode, {
    current_question_index: questionIndex,
    round_started_at: new Date().toISOString(),
  });

  // SECURITY CRITICAL: strip correct_answer_index before broadcasting
  const clientQuestion = {
    id: questionDoc.id,
    subject: questionDoc.subject,
    text: questionDoc.text,
    choices: questionDoc.choices,
  };

  logger.info(
    `[GameEngine] Round started | roomCode=${roomCode} questionIndex=${questionIndex} questionId=${questionDoc.id} choicesCount=${questionDoc.choices.length}`,
  );

  await safeBroadcast(roomCode, 'question:new', clientQuestion);

  // Initialize answer tracking — null means "not answered yet"
  const players = await getPlayers(roomCode);
  const answers = new Map<string, number | null>();
  players.forEach((p) => answers.set(p.id, null));

  const timer = setTimeout(
    () => void revealRound(roomCode, questions, questionIndex),
    ROUND_TIMER_MS,
  );
  roundState.set(roomCode, { answers, timer, questions, questionIndex });
}

export async function submitAnswer(
  roomCode: string,
  playerId: string,
  questionId: string,
  answerIndex: number,
): Promise<void> {
  const state = roundState.get(roomCode);
  if (!state) return;
  if (state.answers.get(playerId) !== null) return; // already answered

  // Validate questionId matches current round
  const currentQuestion = state.questions[state.questionIndex];
  if (currentQuestion.id !== questionId) return;

  // Validate answerIndex is within the actual choices for this question (2–5 choices)
  if (answerIndex < 0 || answerIndex >= currentQuestion.choices.length) {
    logger.warn(
      `[GameEngine] Invalid answerIndex | roomCode=${roomCode} playerId=${playerId} answerIndex=${answerIndex} choicesCount=${currentQuestion.choices.length}`,
    );
    return;
  }

  const room = await getRoom(roomCode);
  if (!room) return;

  const timeTakenMs = room.round_started_at
    ? Date.now() - new Date(room.round_started_at).getTime()
    : 0;

  state.answers.set(playerId, answerIndex);
  logger.info(
    `[GameEngine] Answer recv | roomCode=${roomCode} playerId=${playerId} answerIndex=${answerIndex} timeTakenMs=${timeTakenMs}`,
  );

  await safeBroadcast(roomCode, 'round:update', {
    playerAnswers: Object.fromEntries(state.answers),
  });

  // Check if all active players have answered → early reveal
  const players = await getPlayers(roomCode);
  const allAnswered = players.every((p) => state.answers.get(p.id) !== null);
  if (allAnswered) {
    clearTimeout(state.timer);
    await revealRound(roomCode, state.questions, state.questionIndex);
  }
}

async function revealRound(
  roomCode: string,
  questions: Question[],
  questionIndex: number,
): Promise<void> {
  // Delete from roundState IMMEDIATELY to prevent double-reveal from concurrent calls
  // (race: timer fires and submitAnswer both trigger reveal at same async tick)
  const state = roundState.get(roomCode);
  if (!state) return;
  roundState.delete(roomCode);

  const questionDoc = questions[questionIndex];
  const correctIndex = questionDoc.correct_answer_index;
  const unanswered = [...state.answers.entries()]
    .filter(([, v]) => v === null)
    .map(([k]) => k);

  if (unanswered.length > 0) {
    logger.warn(
      `[GameEngine] Timer expired | roomCode=${roomCode} questionIndex=${questionIndex} unanswered=${JSON.stringify(unanswered)}`,
    );
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

  logger.info(
    `[GameEngine] Round reveal | roomCode=${roomCode} correctIndex=${correctIndex} scores=${JSON.stringify(scores)}`,
  );

  await safeBroadcast(roomCode, 'round:reveal', {
    correctIndex,
    playerAnswers: Object.fromEntries(state.answers),
    scores,
  });

  setTimeout(() => {
    void (async () => {
      if (questionIndex + 1 >= questions.length) {
        await endGame(roomCode);
      } else {
        await startRound(roomCode, questionIndex + 1, questions);
      }
    })();
  }, REVEAL_DELAY_MS);
}

async function endGame(roomCode: string): Promise<void> {
  await updateRoom(roomCode, { status: 'finished' });
  const players = await getPlayers(roomCode);

  const scoreboard = [...players]
    .sort((a, b) => b.score - a.score)
    .map((p, i) => ({
      rank: i + 1,
      id: p.id,
      name: p.name,
      color: p.color,
      score: p.score,
    }));

  logger.info(
    `[GameEngine] Game ended | roomCode=${roomCode} scoreboard=${JSON.stringify(scoreboard)}`,
  );
  await safeBroadcast(roomCode, 'game:end', { scoreboard });

  // Schedule room cleanup after 1 hour; store handle so we can cancel if needed
  const handle = setTimeout(() => {
    void (async () => {
      await deleteRoom(roomCode);
      clearRoom(roomCode);
      cleanupTimeouts.delete(roomCode);
      logger.info(`[GameEngine] Room cleaned up | roomCode=${roomCode}`);
    })();
  }, 60 * 60 * 1000);
  cleanupTimeouts.set(roomCode, handle);
}

// Wraps broadcastToRoom with error logging — a Supabase outage shouldn't crash the server
async function safeBroadcast(roomCode: string, event: string, payload: unknown): Promise<void> {
  try {
    await broadcastToRoom(roomCode, event, payload);
  } catch (err) {
    logger.error(
      `[GameEngine] Broadcast failed | roomCode=${roomCode} event=${event} err=${String(err)}`,
    );
  }
}

// Preserves the original random order from startGame (do NOT sort by id)
async function fetchQuestionsOrdered(questionIds: string[]): Promise<Question[]> {
  const docs = await getQuestionsByIds(questionIds);
  const docMap = new Map(docs.map((d) => [d.id, d]));
  return questionIds.map((id) => docMap.get(id)!);
}

// Public export for testing/admin use
export { fetchQuestionsOrdered };
