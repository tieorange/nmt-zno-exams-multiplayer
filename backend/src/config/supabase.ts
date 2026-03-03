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

/**
 * Broadcast an event to all Supabase Realtime subscribers of a room channel.
 *
 * Uses the documented Supabase REST broadcast endpoint
 * (POST /realtime/v1/api/broadcast) so no channel subscription is required
 * on the server side and there is no unbounded channel accumulation.
 *
 * Payload contract is unchanged — frontend listeners receive the same shape.
 */
export async function broadcastToRoom(
  roomCode: string,
  event: string,
  payload: unknown,
): Promise<void> {
  logger.info(`[Supabase] Broadcasting | roomCode=${roomCode} event=${event}`);

  const broadcastUrl = `${url}/realtime/v1/api/broadcast`;
  const body = JSON.stringify({
    messages: [
      {
        // Channel topic must match what the Flutter client subscribes to:
        // supabase.channel('room:<code>') → topic 'realtime:room:<code>'
        topic: `realtime:room:${roomCode}`,
        event,
        payload,
      },
    ],
  });

  const res = await fetch(broadcastUrl, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${key as string}`,
      'apikey': key as string,
    } satisfies Record<string, string>,
    body,
  });

  if (!res.ok) {
    const text = await res.text().catch(() => '');
    logger.error(
      `[Supabase] Broadcast failed | roomCode=${roomCode} event=${event} status=${res.status} body=${text}`,
    );
    throw new Error(`Broadcast failed: ${res.status}`);
  }

  logger.info(`[Supabase] Broadcast sent | roomCode=${roomCode} event=${event}`);
}
