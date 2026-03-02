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
  type RoundAnswer,
} from '../data/repositories/RoomRepository.js';
import {
  getRandomQuestions,
  getQuestionsByIds,
  type Question,
} from '../data/repositories/QuestionRepository.js';
import { clearRoom } from './NameGenerator.js';
import { logger } from '../config/logger.js';
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

    await safeBroadcast(roomCode, 'game:start', { totalQuestions: questions.length, timerMs: ROUND_TIMER_MS });
    await startRound(roomCode, 0, questions);
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

    // Cancel any pending "waiting for next question" state from the previous game
    const existingPending = pendingNextRound.get(roomCode);
    if (existingPending) {
      clearTimeout(existingPending.fallbackTimer);
      pendingNextRound.delete(roomCode);
    }

    await updateRoom(roomCode, {
      status: 'playing',
      question_ids: questionIds,
      current_question_index: 0,
    });

    logger.info(`[GameEngine] Game restarted | roomCode=${roomCode} questions=${questions.length}`);

    // Bug 9 Fix: Zero out scores on restart
    await resetScores(roomCode);

    await safeBroadcast(roomCode, 'game:start', { totalQuestions: questions.length, timerMs: ROUND_TIMER_MS });
    await startRound(roomCode, 0, questions);
  } finally {
    startingMutex.delete(roomCode);
  }
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
    logger.warn(
      `[GameEngine] Invalid answerIndex | roomCode=${roomCode} playerId=${playerId} answerIndex=${answerIndex} choicesCount=${currentQuestion.choices.length}`,
    );
    throw new Error('Невірний індекс відповіді');
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
  const allAnswered = players.every((p) => {
    // If the player answered OR they are currently offline, they don't block the reveal
    return state.answers.get(p.id) !== null || isPlayerOffline(p.id);
  });
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

  logger.info(
    `[GameEngine] Round reveal | roomCode=${roomCode} correctIndex=${correctIndex} scores=${JSON.stringify(freshScores)}`,
  );

  await safeBroadcast(roomCode, 'round:reveal', {
    correctIndex,
    playerAnswers: Object.fromEntries(state.answers),
    scores: freshScores,
    scoreDeltas,
  });

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

  logger.info(
    `[GameEngine] Creator advancing to next | roomCode=${roomCode} nextIndex=${pending.nextIndex}`,
  );
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
    questionIndex: state.questionIndex,
  };
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
