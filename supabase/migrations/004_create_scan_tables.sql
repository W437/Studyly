-- Scanned items table
CREATE TABLE IF NOT EXISTS scanned_items (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  local_image_path TEXT NOT NULL,
  remote_image_url TEXT,
  status INTEGER NOT NULL,
  ocr_text TEXT,
  selected_action TEXT,
  error_message TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Flashcards table
CREATE TABLE IF NOT EXISTS flashcards (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  study_set_id UUID NOT NULL REFERENCES study_sets(id) ON DELETE CASCADE,
  front TEXT NOT NULL,
  back TEXT NOT NULL,
  hint TEXT,
  difficulty INTEGER NOT NULL DEFAULT 3,
  srs_ease_factor DOUBLE PRECISION,
  srs_interval INTEGER,
  srs_repetitions INTEGER,
  srs_next_review_date TIMESTAMP WITH TIME ZONE,
  srs_last_review_date TIMESTAMP WITH TIME ZONE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Explanation documents table
CREATE TABLE IF NOT EXISTS explanation_docs (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  study_set_id UUID NOT NULL REFERENCES study_sets(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  summary TEXT NOT NULL,
  key_points TEXT[] NOT NULL,
  content TEXT NOT NULL,
  source_image_url TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Exercises table
CREATE TABLE IF NOT EXISTS exercises (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  study_set_id UUID NOT NULL REFERENCES study_sets(id) ON DELETE CASCADE,
  question TEXT NOT NULL,
  options TEXT[] NOT NULL,
  correct_answer TEXT NOT NULL,
  explanation TEXT NOT NULL,
  type INTEGER NOT NULL,
  difficulty INTEGER NOT NULL DEFAULT 3,
  user_answer TEXT,
  is_correct BOOLEAN,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Generation results table (for offline queue)
CREATE TABLE IF NOT EXISTS generation_results (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  scanned_item_id UUID NOT NULL REFERENCES scanned_items(id) ON DELETE CASCADE,
  type INTEGER NOT NULL,
  status INTEGER NOT NULL,
  input_text TEXT,
  image_url TEXT,
  result JSONB,
  error_message TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  completed_at TIMESTAMP WITH TIME ZONE
);

-- Indices for faster queries
CREATE INDEX IF NOT EXISTS idx_scanned_items_user_id ON scanned_items(user_id);
CREATE INDEX IF NOT EXISTS idx_scanned_items_status ON scanned_items(user_id, status);
CREATE INDEX IF NOT EXISTS idx_flashcards_user_study_set ON flashcards(user_id, study_set_id);
CREATE INDEX IF NOT EXISTS idx_flashcards_srs_review ON flashcards(user_id, srs_next_review_date);
CREATE INDEX IF NOT EXISTS idx_explanation_docs_user_study_set ON explanation_docs(user_id, study_set_id);
CREATE INDEX IF NOT EXISTS idx_exercises_user_study_set ON exercises(user_id, study_set_id);
CREATE INDEX IF NOT EXISTS idx_generation_results_user_status ON generation_results(user_id, status);

-- Triggers for auto-updating updated_at
CREATE TRIGGER update_scanned_items_updated_at BEFORE UPDATE ON scanned_items
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_flashcards_updated_at BEFORE UPDATE ON flashcards
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_explanation_docs_updated_at BEFORE UPDATE ON explanation_docs
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_exercises_updated_at BEFORE UPDATE ON exercises
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
