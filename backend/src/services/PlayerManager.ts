import { removePlayer, getPlayers, setCreator, clearAllCreators, deleteRoom, getRoom } from '../data/repositories/RoomRepository.js';
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

export function pingHeartbeat(playerId: string, roomCode: string): boolean {
    const session = pings.get(playerId);
    if (session && session.roomCode === roomCode) {
        session.lastPing = Date.now();
        return true;
    }
    return false;
}

const DISCONNECT_TIMEOUT_MS = 60000;

setInterval(() => {
    const now = Date.now();
    for (const [playerId, session] of pings.entries()) {
        if (now - session.lastPing > DISCONNECT_TIMEOUT_MS) {
            handlePlayerDisconnect(playerId, session.roomCode).catch(e => {
                logger.error(`[PlayerManager] Error in handlePlayerDisconnect for ${playerId}: ${e}`);
            });
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
        const room = await getRoom(roomCode);
        if (!room) return;

        // Bug fix: If game is active, DO NOT remove the player from the DB.
        // This preserves their score and allows them to rejoin later.
        // We only remove them if the game hasn't started yet.
        if (room.status === 'waiting') {
            await removePlayer(roomCode, playerId);
        }

        const players = await getPlayers(roomCode);

        // Count actually "online" players (those who still have a ping entry)
        const onlinePlayers = players.filter(p => pings.has(p.id));

        if (onlinePlayers.length === 0) {
            // Room is empty/all offline, delete it
            await deleteRoom(roomCode);
            clearRoom(roomCode);
            logger.info(`[PlayerManager] Room deleted due to zero online players | roomCode=${roomCode}`);
            return;
        }

        // Check if there is an ONLINE creator (not just any player with is_creator flag in DB).
        // During active games, disconnected players stay in DB, so hasCreator would be true
        // even if the creator is offline — we must check pings liveness.
        const hasOnlineCreator = players.some((p) => p.is_creator && pings.has(p.id));
        if (!hasOnlineCreator) {
            // Clear stale creator flag(s) before assigning a new one
            await clearAllCreators(roomCode);
            // Reassign to the oldest remaining ONLINE player, or oldest overall as fallback
            const candidates = onlinePlayers.length > 0 ? onlinePlayers : players;
            const oldestPlayer = candidates.sort((a, b) => new Date(a.joined_at).getTime() - new Date(b.joined_at).getTime())[0];
            await setCreator(roomCode, oldestPlayer.id);
            logger.info(`[PlayerManager] Reassigned creator | roomCode=${roomCode} newCreatorId=${oldestPlayer.id}`);
        }

        // Broadcast room state update
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

    } catch (err) {
        logger.error(`[PlayerManager] Disconnect handling failed | err=${String(err)}`);
    }
}

/**
 * Returns true if the player is considered offline (missed heartbeats)
 */
export function isPlayerOffline(playerId: string): boolean {
    return !pings.has(playerId);
}
