import { broadcastToRoom } from '../config/supabase.js';
import {
  getRoom,
  updateRoom,
  getPlayers,
  incrementPlayerScore,
  deleteRoom,
  resetScores,
  saveRoundAnswer,
  getRoundAnswers,
} from '../data/repositories/RoomRepository.js';
import {
  getRandomQuestions,
  type Question,
} from '../data/repositories/QuestionRepository.js';
import { clearRoom } from './NameGenerator.js';
import { logger } from '../config/logger.js';
import { serializeError } from '../utils/serializeError.js';
import { isPlayerOffline } from './PlayerManager.js';

const QUESTION_COUNT = 5;
// Override with env var for testing (e.g. ROUND_TIMER_MS=10000 for 10s rounds)
const ROUND_TIMER_MS = parseInt(process.env.ROUND_TIMER_MS ?? '') || 5 * 60 * 1000;
// Safety fallback: auto-advance to next question if creator doesn't press the button.
// Override with env var for testing (e.g. PENDING_ROUND_TIMEOUT_MS=30000 for 30s).
const PENDING_ROUND_TIMEOUT_MS = parseInt(process.env.PENDING_ROUND_TIMEOUT_MS ?? '') || 5 * 60 * 1000;
const CORRECT_ANSWER_POINTS = 10;

interface RoundState {
  answers: Map<string, number | null>;
  timer: ReturnType<typeof setTimeout>;
  questions: Question[];   // stored here so submitAnswer can validate answerIndex inline
  questionIndex: number;
  roundStartedAt: string;  // ISO timestamp — used by rejoin snapshot to compute remaining time
}

// Holds state between revealRound and the creator pressing "next question".
// Cleared when creator advances, or by the fallback safety timer.
interface PendingNextRound {
  nextIndex: number;
  questions: Question[];
  fallbackTimer: ReturnType<typeof setTimeout>;
}

// In-memory: roomCode → round state
// This state lives in Node.js — intentional. Keeps game logic server-authoritative.
const roundState = new Map<string, RoundState>();

// In-memory: roomCode → pending next-round state (between reveal and creator pressing next)
const pendingNextRound = new Map<string, PendingNextRound>();

// Cache of reveal data so polling clients can catch a missed round:reveal broadcast.
// Populated by revealRound(), cleared by advanceToNextRound().
interface RevealCache {
  correctIndex: number;
  playerAnswers: Record<string, number | null>;
  scores: Record<string, number>;
  scoreDeltas: Record<string, number>;
}
const pendingRevealCache = new Map<string, RevealCache>();

// Track cleanup timeouts so we can cancel if a room gets reused
const cleanupTimeouts = new Map<string, ReturnType<typeof setTimeout>>();

// Mutex to prevent multiple startGame calls for the same room simultaneously
const startingMutex = new Set<string>();

export async function startGame(roomCode: string): Promise<void> {
  if (startingMutex.has(roomCode)) return;
  startingMutex.add(roomCode);
  try {
    const room = await getRoom(roomCode);
    if (!room || room.status !== 'waiting') return;
    await runGame(roomCode, room.subject, 'Game started');
  } finally {
    startingMutex.delete(roomCode);
  }
}

export async function restartGame(roomCode: string): Promise<void> {
  if (startingMutex.has(roomCode)) return;
  startingMutex.add(roomCode);
  try {
    const room = await getRoom(roomCode);
    if (!room || room.status !== 'finished') return;

    // Cancel any pending "waiting for next question" state from the previous game
    const existingPending = pendingNextRound.get(roomCode);
    if (existingPending) {
      clearTimeout(existingPending.fallbackTimer);
      pendingNextRound.delete(roomCode);
    }

    await resetScores(roomCode);
    await runGame(roomCode, room.subject, 'Game restarted');
  } finally {
    startingMutex.delete(roomCode);
  }
}

// Shared: fetch questions, update DB to 'playing', broadcast game:start, begin round 0.
// Called by both startGame and restartGame after their status checks and prereqs.
async function runGame(roomCode: string, subject: string, logLabel: string): Promise<void> {
  const questions = await getRandomQuestions(subject, QUESTION_COUNT);
  if (questions.length < QUESTION_COUNT) {
    logger.warn({ event: 'game.questions.insufficient', roomCode, subject, got: questions.length, need: QUESTION_COUNT });
  }

  // Cancel any leftover cleanup timeout (e.g. 1-hour post-game cleanup)
  const existingCleanup = cleanupTimeouts.get(roomCode);
  if (existingCleanup) {
    clearTimeout(existingCleanup);
    cleanupTimeouts.delete(roomCode);
  }

  await updateRoom(roomCode, {
    status: 'playing',
    question_ids: questions.map((q) => q.id),
    current_question_index: 0,
  });

  logger.info({ event: 'game.run', roomCode, label: logLabel, questionCount: questions.length });
  await safeBroadcast(roomCode, 'game:start', { totalQuestions: questions.length, timerMs: ROUND_TIMER_MS });
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
  const roundStartedAt = new Date().toISOString();
  await updateRoom(roomCode, {
    current_question_index: questionIndex,
    round_started_at: roundStartedAt,
  });

  // SECURITY CRITICAL: strip correct_answer_index before broadcasting
  const clientQuestion = {
    id: questionDoc.id,
    subject: questionDoc.subject,
    text: questionDoc.text,
    choices: questionDoc.choices,
  };

  logger.info({ event: 'game.round.start', roomCode, questionIndex, questionId: questionDoc.id, choicesCount: questionDoc.choices.length });

  await safeBroadcast(roomCode, 'question:new', clientQuestion);

  // Initialize answer tracking — null means "not answered yet"
  const players = await getPlayers(roomCode);
  const answers = new Map<string, number | null>();
  players.forEach((p) => answers.set(p.id, null));

  const timer = setTimeout(() => void revealRound(roomCode), ROUND_TIMER_MS);
  roundState.set(roomCode, { answers, timer, questions, questionIndex, roundStartedAt });
}

export async function submitAnswer(
  roomCode: string,
  playerId: string,
  questionId: string,
  answerIndex: number,
): Promise<void> {
  const state = roundState.get(roomCode);
  if (!state) throw new Error('Гру не знайдено або раунд ще не почався');

  // Bug fix: Check for undefined explicitly in case of mid-round late joins or unmapped players
  const existingAnswer = state.answers.get(playerId);
  if (existingAnswer !== undefined && existingAnswer !== null) {
    throw new Error('Ви вже відповіли на це запитання');
  }

  // Validate questionId matches current round
  const currentQuestion = state.questions[state.questionIndex];
  if (currentQuestion.id !== questionId) throw new Error('Неправильне ID запитання');

  // Validate answerIndex is within the actual choices for this question (2–5 choices)
  if (answerIndex < 0 || answerIndex >= currentQuestion.choices.length) {
    logger.warn({ event: 'game.answer.invalid_index', roomCode, playerId, answerIndex, choicesCount: currentQuestion.choices.length });
    throw new Error('Невірний індекс відповіді');
  }

  const room = await getRoom(roomCode);
  if (!room) return;

  const timeTakenMs = room.round_started_at
    ? Date.now() - new Date(room.round_started_at).getTime()
    : 0;

  state.answers.set(playerId, answerIndex);
  logger.info({ event: 'game.answer.received', roomCode, playerId, answerIndex, timeTakenMs });

  await safeBroadcast(roomCode, 'round:update', {
    playerAnswers: Object.fromEntries(state.answers),
  });

  // Check if all active players have answered → early reveal
  const players = await getPlayers(roomCode);
  const allAnswered = players.every((p) => {
    // If the player answered OR they are currently offline, they don't block the reveal
    return state.answers.get(p.id) !== null || isPlayerOffline(p.id);
  });
  if (allAnswered) {
    clearTimeout(state.timer);
    await revealRound(roomCode);
  }
}

async function revealRound(roomCode: string): Promise<void> {
  // Delete from roundState IMMEDIATELY to prevent double-reveal from concurrent calls
  // (race: timer fires and submitAnswer both trigger reveal at same async tick)
  const state = roundState.get(roomCode);
  if (!state) return;
  roundState.delete(roomCode);

  const { questions, questionIndex } = state;
  const questionDoc = questions[questionIndex];
  const correctIndex = questionDoc.correct_answer_index;
  const unanswered = [...state.answers.entries()]
    .filter(([, v]) => v === null)
    .map(([k]) => k);

  if (unanswered.length > 0) {
    logger.warn({ event: 'game.round.timer_expired', roomCode, questionIndex, unansweredCount: unanswered.length, unansweredPlayerIds: unanswered });
  }

  // Update scores in parallel to reduce broadcast latency
  const players = await getPlayers(roomCode);
  const scoreUpdates: Promise<void>[] = [];
  const answerSaves: Promise<void>[] = [];

  const scoreDeltas: Record<string, number> = {};

  for (const player of players) {
    const answer = state.answers.get(player.id);
    let points = 0;

    if (answer === correctIndex) {
      points = CORRECT_ANSWER_POINTS;
      scoreUpdates.push(incrementPlayerScore(roomCode, player.id, points));
    }

    scoreDeltas[player.id] = points;

    // Persist answer to database (null answer means player didn't answer)
    if (answer !== null && answer !== undefined) {
      answerSaves.push(
        saveRoundAnswer(
          roomCode,
          questionIndex,
          player.id,
          questionDoc.id,
          answer,
          answer === correctIndex,
        ),
      );
    }
  }

  if (scoreUpdates.length > 0) {
    await Promise.all(scoreUpdates);
  }
  if (answerSaves.length > 0) {
    await Promise.all(answerSaves);
  }

  // Re-fetch fresh scores from DB after all increments complete — avoids broadcasting
  // stale pre-increment values that make the scoreboard look one round behind.
  const freshPlayers = await getPlayers(roomCode);
  const freshScores: Record<string, number> = {};
  for (const p of freshPlayers) freshScores[p.id] = p.score;

  logger.info({ event: 'game.round.reveal', roomCode, questionIndex, correctIndex, answeredCount: players.length - unanswered.length, scores: freshScores });

  const revealPayload = {
    correctIndex,
    playerAnswers: Object.fromEntries(state.answers),
    scores: freshScores,
    scoreDeltas,
  };

  // Cache reveal data for polls (clients that missed the WebSocket broadcast)
  pendingRevealCache.set(roomCode, revealPayload);

  await safeBroadcast(roomCode, 'round:reveal', revealPayload);

  // Store pending state so creator can manually advance with nextQuestion().
  // Safety fallback fires automatically in case creator disconnects.
  const fallbackTimer = setTimeout(
    () => void advanceToNextRound(roomCode),
    PENDING_ROUND_TIMEOUT_MS,
  );
  pendingNextRound.set(roomCode, { nextIndex: questionIndex + 1, questions, fallbackTimer });
}

async function advanceToNextRound(roomCode: string): Promise<void> {
  const pending = pendingNextRound.get(roomCode);
  if (!pending) return; // Already advanced (creator pressed button or fallback already ran)
  pendingRevealCache.delete(roomCode); // Clear reveal cache — new round starting
  pendingNextRound.delete(roomCode);
  clearTimeout(pending.fallbackTimer);

  if (pending.nextIndex >= pending.questions.length) {
    await endGame(roomCode);
  } else {
    await startRound(roomCode, pending.nextIndex, pending.questions);
  }
}

export async function nextQuestion(roomCode: string, playerId: string): Promise<void> {
  const players = await getPlayers(roomCode);
  const player = players.find((p) => p.id === playerId);
  if (!player?.is_creator) {
    throw new Error('Тільки творець може перейти до наступного питання');
  }

  const pending = pendingNextRound.get(roomCode);
  if (!pending) {
    throw new Error('Немає очікуваного наступного питання');
  }

  logger.info({ event: 'game.next_question.creator_advance', roomCode, nextIndex: pending.nextIndex });
  await advanceToNextRound(roomCode);
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

  logger.info({ event: 'game.end', roomCode, playerCount: scoreboard.length, scoreboard });
  await safeBroadcast(roomCode, 'game:end', { scoreboard });

  // Schedule room cleanup after 1 hour; store handle so we can cancel if needed
  const handle = setTimeout(() => {
    void (async () => {
      await deleteRoom(roomCode);
      clearRoom(roomCode);
      cleanupTimeouts.delete(roomCode);
      logger.info({ event: 'game.room.cleanup', roomCode });
    })();
  }, 60 * 60 * 1000);
  cleanupTimeouts.set(roomCode, handle);
}

// Wraps broadcastToRoom with error logging — a Supabase outage shouldn't crash the server
async function safeBroadcast(roomCode: string, event: string, payload: unknown): Promise<void> {
  try {
    await broadcastToRoom(roomCode, event, payload);
  } catch (err) {
    logger.error({ event: 'game.broadcast.failed', roomCode, broadcastEvent: event, error: serializeError(err) });
  }
}

/**
 * Returns the current question payload for a given room if a round is active.
 * Used for mid-game reconnections to sync the client UI.
 */
export function getCurrentClientQuestion(roomCode: string) {
  const state = roundState.get(roomCode);
  if (!state) return null;

  const q = state.questions[state.questionIndex];
  return {
    id: q.id,
    subject: q.subject,
    text: q.text,
    choices: q.choices,
    // questionIndex is 0-based (matches the questions array index).
    // The Flutter QuizCubit converts this to 1-based for display.
    questionIndex: state.questionIndex,
    // Include total so the frontend can show "Q x / total" correctly on rejoin.
    totalQuestions: state.questions.length,
    // Timer metadata so the frontend can compute how much time is left on rejoin.
    roundStartedAt: state.roundStartedAt,
    timerMs: ROUND_TIMER_MS,
  };
}

/**
 * Returns the current live player answers for an active round.
 * Returns null if no round is in progress (between rounds or game not started).
 * Used by the polling REST endpoint so clients can update answer chips.
 */
export function getActivePlayerAnswers(roomCode: string): Record<string, number | null> | null {
  const state = roundState.get(roomCode);
  if (!state) return null;
  return Object.fromEntries(state.answers);
}

/**
 * Returns the cached reveal payload if a round was revealed but the next question hasn't
 * started yet (i.e. creator hasn't pressed "Next question").
 * Returns null otherwise.
 * Used by the polling REST endpoint so clients that missed round:reveal can catch up.
 */
export function getPendingRevealData(roomCode: string): RevealCache | null {
  return pendingRevealCache.get(roomCode) ?? null;
}

/**
 * Loads round answers from the database for a specific room and round.
 * Returns a Map of playerId -> answerIndex for the given round.
 * Used for recovering answer state if needed.
 */
export async function loadRoundAnswersFromDb(
  roomCode: string,
  roundNumber: number,
): Promise<Map<string, number>> {
  const answers = await getRoundAnswers(roomCode, roundNumber);
  const answerMap = new Map<string, number>();
  for (const a of answers) {
    answerMap.set(a.player_id, a.answer_index);
  }
  return answerMap;
}
