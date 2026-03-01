import { z } from 'zod';
import { SUBJECTS } from '../../domain/types.js';
import type { QuestionSubject } from '../../domain/types.js';

// Derive subject keys from the canonical SUBJECTS list so they never go out of sync
const subjectKeys = SUBJECTS.map((s) => s.subject) as [QuestionSubject, ...QuestionSubject[]];

export const CreateRoomSchema = z.object({
  subject: z.enum(subjectKeys),
  maxPlayers: z.number().int().min(1).max(4),
});

export const StartGameSchema = z.object({
  playerId: z.string().uuid(),
});

export const SubmitAnswerSchema = z.object({
  playerId: z.string().uuid(),
  questionId: z.string().min(1),
  // Max 4 = 0-based index for up to 5 choices. Actual bounds are validated in
  // GameEngine.submitAnswer() against the real question's choices.length.
  answerIndex: z.number().int().min(0).max(4),
});
