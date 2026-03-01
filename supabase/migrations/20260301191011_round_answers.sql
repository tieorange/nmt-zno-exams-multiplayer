-- Round answers persistence
-- Stores individual player answers for each question in a round

CREATE TABLE round_answers (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  room_code       TEXT NOT NULL REFERENCES rooms(code) ON DELETE CASCADE,
  round_number    INTEGER NOT NULL,
  player_id       UUID NOT NULL REFERENCES players(id) ON DELETE CASCADE,
  question_id     TEXT NOT NULL,
  answer_index    INTEGER NOT NULL,
  is_correct      BOOLEAN NOT NULL,
  created_at      TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX idx_round_answers_room ON round_answers (room_code, round_number);
CREATE INDEX idx_round_answers_player ON round_answers (player_id);
