import { Request, Response } from 'express';
import { getRoom, getPlayers } from '../../data/repositories/RoomRepository.js';
import { validatePlayerInRoom } from './RoomController.js';
import {
  startGame as engineStartGame,
  submitAnswer as engineSubmitAnswer,
  restartGame as engineRestartGame,
  nextQuestion as engineNextQuestion,
} from '../../services/GameEngine.js';
import { StartGameSchema, SubmitAnswerSchema, RestartGameSchema, NextQuestionSchema } from '../validators/requestSchemas.js';
import { logger } from '../../config/logger.js';
import { serializeError } from '../../utils/serializeError.js';

export async function startGame(req: Request, res: Response) {
  const requestId = res.locals['requestId'] as string;
  const code = String(req.params.code).toUpperCase();
  const parsed = StartGameSchema.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({ error: parsed.error.flatten() });
    return;
  }

  const room = await getRoom(code);
  if (!room) {
    logger.warn({ event: 'game.start.failed', requestId, roomCode: code, reason: 'room_not_found', outcome: 'failure' });
    res.status(404).json({ error: 'Кімнату не знайдено' });
    return;
  }
  if (room.status !== 'waiting') {
    logger.warn({ event: 'game.start.failed', requestId, roomCode: code, reason: 'game_already_started', roomStatus: room.status, outcome: 'failure' });
    res.status(400).json({ error: 'Гра вже почалась' });
    return;
  }

  const players = await getPlayers(code);
  const player = players.find((p) => p.id === parsed.data.playerId);
  if (!player?.is_creator) {
    logger.warn({ event: 'game.start.failed', requestId, roomCode: code, playerId: parsed.data.playerId, reason: 'not_creator', outcome: 'failure' });
    res.status(403).json({ error: 'Тільки творець може почати гру' });
    return;
  }

  logger.info({ event: 'game.start', requestId, roomCode: code, playerId: parsed.data.playerId, playerCount: players.length });
  await engineStartGame(code);
  res.json({ ok: true });
}

export async function submitAnswer(req: Request, res: Response) {
  const requestId = res.locals['requestId'] as string;
  const code = String(req.params.code).toUpperCase();
  const parsed = SubmitAnswerSchema.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({ error: parsed.error.flatten() });
    return;
  }

  const { playerId, questionId, answerIndex } = parsed.data;

  // Validate player belongs to room - defense against identity spoofing
  const isValidPlayer = await validatePlayerInRoom(code, playerId);
  if (!isValidPlayer) {
    res.status(403).json({ error: 'Player does not belong to this room' });
    return;
  }

  try {
    await engineSubmitAnswer(code, playerId, questionId, answerIndex);
    logger.info({ event: 'game.answer.accepted', requestId, roomCode: code, playerId, answerIndex, outcome: 'success' });
    res.json({ ok: true });
  } catch (err: unknown) {
    const serialized = serializeError(err);
    logger.warn({ event: 'game.answer.rejected', requestId, roomCode: code, playerId, answerIndex, reason: serialized.message, outcome: 'failure' });
    res.status(400).json({ error: serialized.message || 'Помилка валідації відповіді' });
  }
}

export async function restartGame(req: Request, res: Response) {
  const requestId = res.locals['requestId'] as string;
  const code = String(req.params.code).toUpperCase();
  const parsed = RestartGameSchema.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({ error: parsed.error.flatten() });
    return;
  }

  const room = await getRoom(code);
  if (!room) {
    res.status(404).json({ error: 'Кімнату не знайдено' });
    return;
  }
  if (room.status !== 'finished') {
    res.status(400).json({ error: 'Гру ще не завершено' });
    return;
  }

  const players = await getPlayers(code);
  const player = players.find((p) => p.id === parsed.data.playerId);
  if (!player?.is_creator) {
    res.status(403).json({ error: 'Тільки творець може почати нову гру' });
    return;
  }

  logger.info({ event: 'game.restart', requestId, roomCode: code, playerId: parsed.data.playerId });
  await engineRestartGame(code);
  res.json({ ok: true });
}

export async function nextQuestion(req: Request, res: Response) {
  const requestId = res.locals['requestId'] as string;
  const code = String(req.params.code).toUpperCase();
  const parsed = NextQuestionSchema.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({ error: parsed.error.flatten() });
    return;
  }

  try {
    await engineNextQuestion(code, parsed.data.playerId);
    logger.info({ event: 'game.next_question', requestId, roomCode: code, playerId: parsed.data.playerId, outcome: 'success' });
    res.json({ ok: true });
  } catch (err: unknown) {
    const serialized = serializeError(err);
    logger.warn({ event: 'game.next_question.failed', requestId, roomCode: code, playerId: parsed.data.playerId, reason: serialized.message, outcome: 'failure' });
    res.status(400).json({ error: serialized.message });
  }
}
