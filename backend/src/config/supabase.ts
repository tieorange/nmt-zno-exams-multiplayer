import { createClient } from '@supabase/supabase-js';
import { logger } from './logger.js';
import { serializeError } from '../utils/serializeError.js';

const url = process.env.SUPABASE_URL;
const key = process.env.SUPABASE_SERVICE_KEY;

if (!url || !key) {
  logger.error({ event: 'supabase.config.missing', message: 'SUPABASE_URL or SUPABASE_SERVICE_KEY missing in .env' });
  process.exit(1);
}

// Service-role client — full DB access, bypasses RLS. NEVER expose this key to clients.
export const supabase = createClient(url, key, {
  auth: { persistSession: false },
});

logger.info({ event: 'supabase.client.initialized' });

// Broadcast an event to all Supabase Realtime subscribers of a room channel.
// Uses the realtime client's HTTP send path, which is verified to work in local setup.
export async function broadcastToRoom(
  roomCode: string,
  event: string,
  payload: unknown,
): Promise<void> {
  const start = Date.now();
  logger.debug({ event: 'supabase.broadcast.start', roomCode, broadcastEvent: event });

  // Send via channel helper (same behavior as main branch).
  const channel = supabase.channel(`room:${roomCode}`);
  try {
    await (channel as any).httpSend(event, payload);
    const durationMs = Date.now() - start;
    logger.info({ event: 'supabase.broadcast.ok', roomCode, broadcastEvent: event, durationMs, outcome: 'success' });
  } catch (err) {
    const durationMs = Date.now() - start;
    logger.error({ event: 'supabase.broadcast.failed', roomCode, broadcastEvent: event, durationMs, outcome: 'failure', error: serializeError(err) });
    throw err;
  }
}
