import { Request, Response } from 'express';
import { getRoom, getPlayers } from '../../data/repositories/RoomRepository.js';
import { validatePlayerInRoom } from './RoomController.js';
import {
  startGame as engineStartGame,
  submitAnswer as engineSubmitAnswer,
  restartGame as engineRestartGame,
} from '../../services/GameEngine.js';
import { StartGameSchema, SubmitAnswerSchema, RestartGameSchema } from '../validators/requestSchemas.js';
import { logger } from '../../config/logger.js';

export async function startGame(req: Request, res: Response) {
  const code = String(req.params.code).toUpperCase();
  const parsed = StartGameSchema.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({ error: parsed.error.flatten() });
    return;
  }

  const room = await getRoom(code);
  if (!room) {
    logger.warn(`[GameController] game:start failed | roomCode=${code} reason=room_not_found`);
    res.status(404).json({ error: 'Кімнату не знайдено' });
    return;
  }
  if (room.status !== 'waiting') {
    logger.warn(`[GameController] game:start failed | roomCode=${code} reason=game_already_started status=${room.status}`);
    res.status(400).json({ error: 'Гра вже почалась' });
    return;
  }

  const players = await getPlayers(code);
  logger.info(`[GameController] game:start attempt | roomCode=${code} playerId=${parsed.data.playerId} playersCount=${players.length} maxPlayers=${room.max_players}`);
  
  const player = players.find((p) => p.id === parsed.data.playerId);
  if (!player?.is_creator) {
    logger.warn(`[GameController] game:start failed | roomCode=${code} playerId=${parsed.data.playerId} reason=not_creator`);
    res.status(403).json({ error: 'Тільки творець може почати гру' });
    return;
  }

  logger.info(`[GameController] game:start | roomCode=${code} playerId=${parsed.data.playerId} starting game with ${players.length} players`);
  await engineStartGame(code);
  res.json({ ok: true });
}

export async function submitAnswer(req: Request, res: Response) {
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

  logger.info(
    `[GameController] answer | roomCode=${code} playerId=${playerId} answerIndex=${answerIndex}`,
  );
  try {
    await engineSubmitAnswer(code, playerId, questionId, answerIndex);
    res.json({ ok: true });
  } catch (err: any) {
    logger.warn(`[GameController] Invalid answer | roomCode=${code} err=${err.message}`);
    res.status(400).json({ error: err.message || 'Помилка валідації відповіді' });
  }
}

export async function restartGame(req: Request, res: Response) {
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

  logger.info(`[GameController] game:restart | roomCode=${code} playerId=${parsed.data.playerId}`);
  await engineRestartGame(code);
  res.json({ ok: true });
}
