/**
 * TypeScript type definitions for the NMT Quiz dataset.
 * Copy this file into your Node.js backend or Flutter-generated API layer.
 */

/**
 * The subject topics available in the game.
 * Each maps directly to a JSON file in the `questions/` directory.
 */
export type QuestionSubject =
    | 'ukrainian_language'
    | 'history'
    | 'math'
    | 'geography';

/**
 * The exam series the question originated from.
 */
export type ExamType = 'ZNO_NMT_General';

/**
 * A single multiple-choice NMT/ZNO question.
 * This is the raw shape stored in the JSON files and in MongoDB.
 */
export interface Question {
    /** Unique question ID. e.g. "osy_ukrainian_language_42" or "nlp_math_1743" */
    id: string;

    /** Subject topic this question belongs to. */
    subject: QuestionSubject;

    /** Full question text in Ukrainian. May contain plain-text math expressions (e.g. x^2, log_2(x)). */
    text: string;

    /**
     * Answer option texts. Always 2–5 items.
     * Index 0 = А, 1 = Б, 2 = В, 3 = Г, 4 = Д.
     */
    choices: string[];

    /**
     * Zero-based index into `choices` pointing to the correct answer.
     *
     * ⚠️  SECURITY: Strip this field BEFORE sending a question to any client.
     *     Only emit it via a server-side Socket.io event AFTER the round timer expires.
     */
    correct_answer_index: number;

    /** Exam series this question came from. */
    exam_type: ExamType;
}

/**
 * Safe version of Question sent to clients during active gameplay.
 * The `correct_answer_index` is omitted — never exposed before timer ends.
 */
export type ClientQuestion = Omit<Question, 'correct_answer_index'>;

/**
 * Payload emitted by the server when a round ends,
 * revealing the correct answer and all player selections.
 */
export interface RoundReveal {
    question_id: string;
    correct_answer_index: number;
    /** Map of playerId → chosen index (or null if they did not answer in time) */
    player_answers: Record<string, number | null>;
}

/**
 * Metadata describing a subject topic available in the lobby.
 */
export interface SubjectMeta {
    subject: QuestionSubject;
    /** Human-readable Ukrainian display name shown in the UI */
    display_name: string;
    /** Total number of questions available for this subject */
    question_count: number;
    /** Whether this subject is currently playable (math is limited, kept for demo) */
    enabled: boolean;
}

/**
 * Static metadata for all subjects.
 * Keep in sync with the actual question counts in `questions/`.
 */
export const SUBJECTS: SubjectMeta[] = [
    {
        subject: 'ukrainian_language',
        display_name: 'Українська мова та література',
        question_count: 1923,
        enabled: true,
    },
    {
        subject: 'history',
        display_name: 'Історія України',
        question_count: 1138,
        enabled: true,
    },
    {
        subject: 'geography',
        display_name: 'Географія',
        question_count: 476,
        enabled: true,
    },
    {
        subject: 'math',
        display_name: 'Математика',
        question_count: 58,
        enabled: true, // limited pool — suitable for demo games
    },
];
