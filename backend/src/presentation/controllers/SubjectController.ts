import { Request, Response } from 'express';
import { SUBJECTS } from '../../domain/types.js';
import { getSubjectCounts } from '../../data/repositories/QuestionRepository.js';

export async function getSubjects(_req: Request, res: Response) {
  const counts = await getSubjectCounts();
  // Return camelCase keys; questionCount is live from DB (authoritative over SUBJECTS static data)
  const subjects = SUBJECTS.map((s) => ({
    key: s.subject,
    displayName: s.display_name,
    questionCount: counts[s.subject] ?? 0,
    enabled: s.enabled,
  }));
  res.json({ subjects });
}
