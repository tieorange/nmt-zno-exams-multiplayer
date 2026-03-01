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
  const { data: p } = await supabase
    .from('players').select('score').eq('id', playerId).single();
  const newScore = (p?.score ?? 0) + delta;
  const { error } = await supabase
    .from('players').update({ score: newScore }).eq('id', playerId).eq('room_code', roomCode);
  if (error) throw new Error(`[RoomRepo] incrementPlayerScore failed: ${error.message}`);
}
