import { Request, Response } from 'express';
import { v4 as uuid } from 'uuid';
import {
  createRoom as dbCreateRoom,
  getRoom as dbGetRoom,
  getPlayers,
  addPlayer,
} from '../../data/repositories/RoomRepository.js';
import { generateUniqueCode } from '../../services/CodeGenerator.js';
import { assignName } from '../../services/NameGenerator.js';
import { broadcastToRoom } from '../../config/supabase.js';
import { CreateRoomSchema, JoinRoomSchema, HeartbeatSchema } from '../validators/requestSchemas.js';
import { registerPlayerSession, getPlayerBySession, pingHeartbeat } from '../../services/PlayerManager.js';
import { logger } from '../../config/logger.js';

export async function createRoom(req: Request, res: Response) {
  const parsed = CreateRoomSchema.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({ error: parsed.error.flatten() });
    return;
  }

  const { subject, maxPlayers } = parsed.data;
  const code = await generateUniqueCode();
  await dbCreateRoom(code, subject, maxPlayers);

  logger.info(`[RoomController] Room created | code=${code} subject=${subject} maxPlayers=${maxPlayers}`);
  res.status(201).json({ code });
}

export async function getRoomState(req: Request, res: Response) {
  const code = String(req.params.code).toUpperCase();
  const room = await dbGetRoom(code);
  if (!room) {
    res.status(404).json({ error: 'Room not found' });
    return;
  }

  const players = await getPlayers(code);
  res.json({
    code: room.code,
    subject: room.subject,
    status: room.status,
    maxPlayers: room.max_players,
    currentQuestionIndex: room.current_question_index,
    players: players.map((p) => ({
      id: p.id,
      name: p.name,
      color: p.color,
      score: p.score,
      isCreator: p.is_creator,
    })),
  });
}

export async function joinRoom(req: Request, res: Response) {
  const code = String(req.params.code).toUpperCase();
  const parsed = JoinRoomSchema.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({ error: parsed.error.flatten() });
    return;
  }

  const sessionId = parsed.data.sessionId;

  const room = await dbGetRoom(code);
  if (!room) {
    res.status(404).json({ error: 'Кімнату не знайдено' });
    return;
  }

  // Handle re-join prevention if sessionId is provided
  if (sessionId) {
    const existingPlayerId = getPlayerBySession(sessionId);
    if (existingPlayerId) {
      const existingPlayers = await getPlayers(code);
      const player = existingPlayers.find(p => p.id === existingPlayerId);
      if (player) {
        logger.info(`[RoomController] Player rejoined via session | roomCode=${code} playerId=${existingPlayerId}`);
        res.json({ playerId: player.id, name: player.name, color: player.color, isCreator: player.is_creator });
        return;
      }
    }
  }

  if (room.status !== 'waiting') {
    res.status(400).json({ error: 'Гра вже почалась' });
    return;
  }

  const players = await getPlayers(code);
  if (players.length >= room.max_players) {
    res.status(400).json({ error: 'Кімната повна' });
    return;
  }

  const { name, color } = assignName(code);
  const playerId = uuid();
  const isCreator = players.length === 0;

  await addPlayer(code, { id: playerId, name, color, score: 0, is_creator: isCreator });

  // Register session
  if (sessionId) {
    registerPlayerSession(sessionId, playerId, code);
  } else {
    // Fallback to registering ping baseline using playerId
    registerPlayerSession(playerId, playerId, code);
  }

  const updatedPlayers = await getPlayers(code);
  await broadcastToRoom(code, 'room:state', {
    code,
    subject: room.subject,
    status: room.status,
    maxPlayers: room.max_players,
    players: updatedPlayers.map((p) => ({
      id: p.id,
      name: p.name,
      color: p.color,
      score: p.score,
      isCreator: p.is_creator,
    })),
  });

  logger.info(`[RoomController] Player joined | roomCode=${code} playerId=${playerId} name=${name} isCreator=${isCreator}`);
  res.json({ playerId, name, color, isCreator });
}

export async function heartbeat(req: Request, res: Response) {
  const parsed = HeartbeatSchema.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({ error: parsed.error.flatten() });
    return;
  }
  pingHeartbeat(parsed.data.playerId);
  res.json({ ok: true });
}
