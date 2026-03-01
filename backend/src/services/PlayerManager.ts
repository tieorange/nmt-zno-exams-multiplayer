import { removePlayer, getPlayers, setCreator, deleteRoom, getRoom } from '../data/repositories/RoomRepository.js';
import { broadcastToRoom } from '../config/supabase.js';
import { logger } from '../config/logger.js';
import { clearRoom } from './NameGenerator.js';

interface PlayerSession {
    playerId: string;
    roomCode: string;
    lastPing: number;
}

const sessions = new Map<string, PlayerSession>(); // Key: sessionId
const pings = new Map<string, PlayerSession>(); // Key: playerId

export function registerPlayerSession(sessionId: string, playerId: string, roomCode: string) {
    const session = { playerId, roomCode, lastPing: Date.now() };
    sessions.set(sessionId, session);
    pings.set(playerId, session);
}

// Register heartbeat tracking only — used when no sessionId is available (no duplicate-tab protection)
export function registerPingOnly(playerId: string, roomCode: string) {
    const session = { playerId, roomCode, lastPing: Date.now() };
    pings.set(playerId, session);
}

export function getPlayerBySession(sessionId: string): string | undefined {
    return sessions.get(sessionId)?.playerId;
}

export function pingHeartbeat(playerId: string) {
    const session = pings.get(playerId);
    if (session) {
        session.lastPing = Date.now();
    }
}

const DISCONNECT_TIMEOUT_MS = 60000;

setInterval(() => {
    const now = Date.now();
    for (const [playerId, session] of pings.entries()) {
        if (now - session.lastPing > DISCONNECT_TIMEOUT_MS) {
            handlePlayerDisconnect(playerId, session.roomCode).catch(e => logger.error(`Error in handlePlayerDisconnect: ${e}`));
        }
    }
}, 30000);

export async function handlePlayerDisconnect(playerId: string, roomCode: string) {
    pings.delete(playerId);
    for (const [sid, sess] of sessions.entries()) {
        if (sess.playerId === playerId) sessions.delete(sid);
    }

    logger.info(`[PlayerManager] Player disconnected | roomCode=${roomCode} playerId=${playerId}`);

    try {
        await removePlayer(roomCode, playerId);

        const players = await getPlayers(roomCode);
        if (players.length === 0) {
            // Room is empty, delete it
            await deleteRoom(roomCode);
            clearRoom(roomCode);
            logger.info(`[PlayerManager] Room deleted due to zero players | roomCode=${roomCode}`);
            return;
        }

        // Check if we need to reassign creator
        const hasCreator = players.some((p) => p.is_creator);
        if (!hasCreator) {
            const oldestPlayer = players.sort((a, b) => new Date(a.joined_at).getTime() - new Date(b.joined_at).getTime())[0];
            await setCreator(roomCode, oldestPlayer.id);
            logger.info(`[PlayerManager] Reassigned creator | roomCode=${roomCode} newCreatorId=${oldestPlayer.id}`);
        }

        // Broadcast room state update
        const room = await getRoom(roomCode);
        if (room) {
            const updatedPlayers = await getPlayers(roomCode);
            await broadcastToRoom(roomCode, 'room:state', {
                code: room.code,
                subject: room.subject,
                status: room.status,
                maxPlayers: room.max_players,
                currentQuestionIndex: room.current_question_index,
                players: updatedPlayers.map((p) => ({
                    id: p.id, name: p.name, color: p.color, score: p.score, isCreator: p.is_creator
                })),
            });
            // Also broadcast explicit player disconnected so client can show a toast
            await broadcastToRoom(roomCode, 'player:disconnected', { playerId });
        }

    } catch (err) {
        logger.error(`[PlayerManager] Disconnect handling failed | err=${String(err)}`);
    }
}
