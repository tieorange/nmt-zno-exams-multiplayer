-- Migration: atomic score increment function
-- Run this in Supabase SQL editor or via supabase CLI:
--   supabase db reset   (or just paste into SQL editor)
--
-- Required by Bug 2 fix: RoomRepository.incrementPlayerScore now calls this
-- RPC instead of doing a non-atomic read-modify-write in JavaScript.

CREATE OR REPLACE FUNCTION increment_player_score(player_id uuid, delta int, r_code text)
RETURNS void AS $$
  UPDATE players
  SET score = score + delta
  WHERE id = player_id AND room_code = r_code;
$$ LANGUAGE sql;
