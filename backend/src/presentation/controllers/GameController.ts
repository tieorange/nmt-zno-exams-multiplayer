import { Request, Response } from 'express';
import { getRoom, getPlayers } from '../../data/repositories/RoomRepository.js';
import {
  startGame as engineStartGame,
  submitAnswer as engineSubmitAnswer,
} from '../../services/GameEngine.js';
import { StartGameSchema, SubmitAnswerSchema } from '../validators/requestSchemas.js';
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
    res.status(404).json({ error: 'Кімнату не знайдено' });
    return;
  }
  if (room.status !== 'waiting') {
    res.status(400).json({ error: 'Гра вже почалась' });
    return;
  }

  const players = await getPlayers(code);
  const player = players.find((p) => p.id === parsed.data.playerId);
  if (!player?.is_creator) {
    res.status(403).json({ error: 'Тільки творець може почати гру' });
    return;
  }

  logger.info(`[GameController] game:start | roomCode=${code} playerId=${parsed.data.playerId}`);
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
  logger.info(
    `[GameController] answer | roomCode=${code} playerId=${playerId} answerIndex=${answerIndex}`,
  );
  await engineSubmitAnswer(code, playerId, questionId, answerIndex);
  res.json({ ok: true });
}
