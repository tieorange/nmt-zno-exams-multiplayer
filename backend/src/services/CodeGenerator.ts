import { customAlphabet } from 'nanoid';
import { getRoom } from '../data/repositories/RoomRepository.js';

const gen = customAlphabet('ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789', 3);

export async function generateUniqueCode(): Promise<string> {
  for (let attempt = 0; attempt < 10; attempt++) {
    const code = gen();
    const existing = await getRoom(code);
    if (!existing) return code;
  }
  throw new Error('Failed to generate unique room code after 10 attempts');
}
