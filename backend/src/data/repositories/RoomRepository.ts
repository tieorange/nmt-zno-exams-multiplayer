import { supabase } from '../../config/supabase.js';

export interface Room {
  code: string;
  subject: string;
  status: 'waiting' | 'playing' | 'finished';
  max_players: number;
  question_ids: string[];
  current_question_index: number;
  round_started_at: string | null;
  created_at: string;
}

export interface Player {
  id: string;
  room_code: string;
  name: string;
  color: string;
  score: number;
  is_creator: boolean;
  joined_at: string;
}

export async function createRoom(code: string, subject: string, maxPlayers: number): Promise<Room> {
  const { data, error } = await supabase
    .from('rooms')
    .insert({ code, subject, max_players: maxPlayers })
    .select()
    .single();
  if (error) throw new Error(`[RoomRepo] createRoom failed: ${error.message}`);
  return data;
}

export async function getRoom(code: string): Promise<Room | null> {
  const { data, error } = await supabase
    .from('rooms').select('*').eq('code', code).maybeSingle();
  if (error) throw new Error(`[RoomRepo] getRoom failed: ${error.message}`);
  return data;
}

export async function updateRoom(code: string, updates: Partial<Room>): Promise<void> {
  const { error } = await supabase.from('rooms').update(updates).eq('code', code);
  if (error) throw new Error(`[RoomRepo] updateRoom failed: ${error.message}`);
}

export async function deleteRoom(code: string): Promise<void> {
  const { error } = await supabase.from('rooms').delete().eq('code', code);
  if (error) throw new Error(`[RoomRepo] deleteRoom failed: ${error.message}`);
}

export async function getPlayers(roomCode: string): Promise<Player[]> {
  const { data, error } = await supabase
    .from('players').select('*').eq('room_code', roomCode);
  if (error) throw new Error(`[RoomRepo] getPlayers failed: ${error.message}`);
  return data ?? [];
}

export async function addPlayer(roomCode: string, player: Omit<Player, 'room_code' | 'joined_at'>): Promise<void> {
  const { error } = await supabase
    .from('players').insert({ ...player, room_code: roomCode });
  if (error) throw new Error(`[RoomRepo] addPlayer failed: ${error.message}`);
}

export async function incrementPlayerScore(roomCode: string, playerId: string, delta: number): Promise<void> {
  // Uses a PostgreSQL function for atomic increment — avoids the read-modify-write race
  // when multiple players answer correctly at the same time.
  // SQL: CREATE OR REPLACE FUNCTION increment_player_score(player_id uuid, delta int, r_code text)
  //      RETURNS void AS $$ UPDATE players SET score = score + delta
  //      WHERE id = player_id AND room_code = r_code; $$ LANGUAGE sql;
  const { error } = await supabase.rpc('increment_player_score', {
    player_id: playerId,
    delta,
    r_code: roomCode,
  });
  if (error) throw new Error(`[RoomRepo] incrementPlayerScore failed: ${error.message}`);
}

export async function removePlayer(roomCode: string, playerId: string): Promise<void> {
  const { error } = await supabase.from('players').delete().eq('id', playerId).eq('room_code', roomCode);
  if (error) throw new Error(`[RoomRepo] removePlayer failed: ${error.message}`);
}

export async function clearAllCreators(roomCode: string): Promise<void> {
  const { error } = await supabase.from('players').update({ is_creator: false }).eq('room_code', roomCode);
  if (error) throw new Error(`[RoomRepo] clearAllCreators failed: ${error.message}`);
}

export async function setCreator(roomCode: string, playerId: string): Promise<void> {
  const { error } = await supabase.from('players').update({ is_creator: true }).eq('id', playerId).eq('room_code', roomCode);
  if (error) throw new Error(`[RoomRepo] setCreator failed: ${error.message}`);
}

export async function resetScores(roomCode: string): Promise<void> {
  const { error } = await supabase.from('players').update({ score: 0 }).eq('room_code', roomCode);
  if (error) throw new Error(`[RoomRepo] resetScores failed: ${error.message}`);
}

export interface RoundAnswer {
  id: string;
  room_code: string;
  round_number: number;
  player_id: string;
  question_id: string;
  answer_index: number;
  is_correct: boolean;
  created_at: string;
}

export async function saveRoundAnswer(
  roomCode: string,
  roundNumber: number,
  playerId: string,
  questionId: string,
  answerIndex: number,
  isCorrect: boolean,
): Promise<void> {
  const { error } = await supabase.from('round_answers').insert({
    room_code: roomCode,
    round_number: roundNumber,
    player_id: playerId,
    question_id: questionId,
    answer_index: answerIndex,
    is_correct: isCorrect,
  });
  if (error) throw new Error(`[RoomRepo] saveRoundAnswer failed: ${error.message}`);
}

export async function getRoundAnswers(roomCode: string, roundNumber: number): Promise<RoundAnswer[]> {
  const { data, error } = await supabase
    .from('round_answers')
    .select('*')
    .eq('room_code', roomCode)
    .eq('round_number', roundNumber);
  if (error) throw new Error(`[RoomRepo] getRoundAnswers failed: ${error.message}`);
  return data ?? [];
}
