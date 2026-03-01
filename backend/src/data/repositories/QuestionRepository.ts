import { supabase } from '../../config/supabase.js';

export interface Question {
  id: string;
  subject: string;
  text: string;
  choices: string[];
  correct_answer_index: number;
  exam_type: string;
}

export async function getRandomQuestions(subject: string, count: number): Promise<Question[]> {
  const { data, error } = await supabase
    .from('questions')
    .select('id, subject, text, choices, correct_answer_index, exam_type')
    .eq('subject', subject);
  if (error) throw new Error(`[QuestionRepo] getRandomQuestions failed: ${error.message}`);
  const shuffled = (data ?? []).sort(() => Math.random() - 0.5);
  return shuffled.slice(0, count);
}

export async function getQuestionsByIds(ids: string[]): Promise<Question[]> {
  const { data, error } = await supabase
    .from('questions')
    .select('id, subject, text, choices, correct_answer_index, exam_type')
    .in('id', ids);
  if (error) throw new Error(`[QuestionRepo] getQuestionsByIds failed: ${error.message}`);
  return data ?? [];
}

export async function getSubjectCounts(): Promise<Record<string, number>> {
  const subjects = ['ukrainian_language', 'history', 'math', 'geography'];
  const counts: Record<string, number> = {};

  await Promise.all(
    subjects.map(async (subject) => {
      const { count, error } = await supabase
        .from('questions')
        .select('*', { count: 'exact', head: true })
        .eq('subject', subject);

      if (error) throw new Error(`[QuestionRepo] getSubjectCounts failed for ${subject}: ${error.message}`);
      counts[subject] = count ?? 0;
    })
  );

  return counts;
}
