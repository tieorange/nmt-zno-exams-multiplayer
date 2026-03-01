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
import { registerPlayerSession, registerPingOnly, getPlayerBySession, pingHeartbeat } from '../../services/PlayerManager.js';
import { logger } from '../../config/logger.js';
import { getCurrentClientQuestion } from '../../services/GameEngine.js';

/**
 * Validates that a player belongs to a room by checking the database.
 * This provides defense-in-depth against identity spoofing attacks.
 * @returns true if the player exists in the room, false otherwise
 */
export async function validatePlayerInRoom(roomCode: string, playerId: string): Promise<boolean> {
  try {
    const players = await getPlayers(roomCode);
    return players.some(p => p.id === playerId);
  } catch (error) {
    logger.error(`[RoomController] validatePlayerInRoom error | roomCode=${roomCode} playerId=${playerId} err=${error}`);
    return false;
  }
}

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

  // Bug fix: If game is active, include the current question payload for reconnection sync
  const currentQuestion = room.status === 'playing' ? getCurrentClientQuestion(code) : null;

  res.json({
    code: room.code,
    subject: room.subject,
    status: room.status,
    maxPlayers: room.max_players,
    currentQuestionIndex: room.current_question_index,
    currentQuestion,
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

  if (sessionId) {
    const existingPlayerId = getPlayerBySession(sessionId);
    if (existingPlayerId) {
      const existingPlayers = await getPlayers(code);
      const player = existingPlayers.find(p => p.id === existingPlayerId);
      if (player) {
        logger.info(`[RoomController] Player rejoined via session | roomCode=${code} playerId=${existingPlayerId}`);
        // Re-register heartbeat so the player isn't swept as disconnected
        registerPlayerSession(sessionId, existingPlayerId, code);

        // Broadcast room:state so others see this player is back online (if tracked) and sync the rejoining player
        await broadcastToRoom(code, 'room:state', {
          code,
          subject: room.subject,
          status: room.status,
          maxPlayers: room.max_players,
          currentQuestionIndex: room.current_question_index,
          players: existingPlayers.map((p) => ({
            id: p.id,
            name: p.name,
            color: p.color,
            score: p.score,
            isCreator: p.is_creator,
          })),
        });

        res.json({ playerId: player.id, name: player.name, color: player.color, isCreator: player.is_creator });
        return;
      }
    }
  }

  // Reject new joins if game already started
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

  // Register heartbeat tracking
  if (sessionId) {
    registerPlayerSession(sessionId, playerId, code);
  } else {
    // No sessionId provided — register heartbeat-only (no duplicate-tab protection)
    registerPingOnly(playerId, code);
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
  const code = String(req.params.code).toUpperCase();
  const parsed = HeartbeatSchema.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({ error: parsed.error.flatten() });
    return;
  }

  // Validate player belongs to room - defense against identity spoofing
  const isValidPlayer = await validatePlayerInRoom(code, parsed.data.playerId);
  if (!isValidPlayer) {
    res.status(403).json({ error: 'Player does not belong to this room' });
    return;
  }

  const result = pingHeartbeat(parsed.data.playerId, code);
  if (!result) {
    res.status(400).json({ error: 'Invalid room or session for heartbeat' });
    return;
  }

  res.json({ ok: true });
}
