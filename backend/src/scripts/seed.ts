import 'dotenv/config';
import { readFileSync } from 'fs';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';
import { supabase } from '../config/supabase.js';
import { logger } from '../config/logger.js';

const __dirname = dirname(fileURLToPath(import.meta.url));
const JSON_PATH = join(__dirname, '../../../data-set/questions/all.json');

async function seed() {
  const raw = JSON.parse(readFileSync(JSON_PATH, 'utf-8')) as Array<{
    id: string; subject: string; text: string;
    choices: string[]; correct_answer_index: number; exam_type: string;
  }>;
  logger.info(`[Seed] Loaded ${raw.length} questions from JSON`);

  const BATCH = 500;
  for (let i = 0; i < raw.length; i += BATCH) {
    const batch = raw.slice(i, i + BATCH).map((q) => ({
      id: q.id,
      subject: q.subject,
      text: q.text,
      choices: q.choices,
      correct_answer_index: q.correct_answer_index,
      exam_type: q.exam_type,
    }));

    const { error } = await supabase
      .from('questions')
      .upsert(batch, { onConflict: 'id' });

    if (error) throw new Error(`[Seed] Batch failed: ${error.message}`);
    logger.info(`[Seed] Progress: ${Math.min(i + BATCH, raw.length)} / ${raw.length}`);
  }

  logger.info('[Seed] Done.');
}

seed().catch((e) => { logger.error(e, '[Seed] Failed'); process.exit(1); });
