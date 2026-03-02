import { createClient } from '@supabase/supabase-js';
import { logger } from './logger.js';

const url = process.env.SUPABASE_URL;
const key = process.env.SUPABASE_SERVICE_KEY;

if (!url || !key) {
  logger.error('[Supabase] SUPABASE_URL or SUPABASE_SERVICE_KEY missing in .env');
  process.exit(1);
}

// Service-role client — full DB access, bypasses RLS. NEVER expose this key to clients.
export const supabase = createClient(url, key, {
  auth: { persistSession: false },
});

logger.info('[Supabase] Client initialized');

// Broadcast an event to all Supabase Realtime subscribers of a room channel.
// Uses the REST broadcast endpoint — works from Node.js without subscribing to the channel.
export async function broadcastToRoom(
  roomCode: string,
  event: string,
  payload: unknown,
): Promise<void> {
  logger.info(`[Supabase] Broadcasting | roomCode=${roomCode} event=${event}`);

  // Use Supabase client's channel to broadcast - more reliable than REST API
  const channel = supabase.channel(`room:${roomCode}`);

  try {
    // The realtime client warns to use httpSend for REST delivery when not subscribed
    await (channel as any).httpSend(event, payload);
    logger.info(`[Supabase] Broadcast sent | roomCode=${roomCode} event=${event}`);
  } catch (err) {
    logger.error(`[Supabase] Broadcast failed | roomCode=${roomCode} event=${event} error=${err}`);
    throw err;
  }
}
