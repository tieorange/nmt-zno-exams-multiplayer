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
  const res = await fetch(`${url}/realtime/v1/api/broadcast`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${key}`,
      'apikey': key as string,
    },
    body: JSON.stringify({
      messages: [{ topic: `room:${roomCode}`, event, payload }],
    }),
  });
  if (!res.ok) {
    throw new Error(`[Supabase] broadcastToRoom failed | event=${event} status=${res.status} body=${await res.text()}`);
  }
}
