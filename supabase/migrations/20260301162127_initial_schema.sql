-- Initial Database Schema

-- questions table
CREATE TABLE questions (
  id                   TEXT PRIMARY KEY,   -- e.g. "osy_history_42"
  subject              TEXT NOT NULL,
  text                 TEXT NOT NULL,
  choices              TEXT[] NOT NULL,
  correct_answer_index INTEGER NOT NULL,
  exam_type            TEXT
);

CREATE INDEX idx_questions_subject ON questions (subject);

-- rooms table
CREATE TABLE rooms (
  code                    TEXT PRIMARY KEY,  -- e.g. "A9X"
  subject                 TEXT NOT NULL,
  status                  TEXT NOT NULL DEFAULT 'waiting'
                            CHECK (status IN ('waiting', 'playing', 'finished')),
  max_players             INTEGER NOT NULL,
  question_ids            TEXT[] DEFAULT '{}',
  current_question_index  INTEGER DEFAULT 0,
  round_started_at        TIMESTAMPTZ,
  created_at              TIMESTAMPTZ DEFAULT now()
);

-- players table
CREATE TABLE players (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  room_code   TEXT NOT NULL REFERENCES rooms(code) ON DELETE CASCADE,
  name        TEXT NOT NULL,
  color       TEXT NOT NULL,
  score       INTEGER DEFAULT 0,
  is_creator  BOOLEAN DEFAULT false,
  joined_at   TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX idx_players_room ON players (room_code);
