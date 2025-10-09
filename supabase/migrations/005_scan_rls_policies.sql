-- Enable RLS on scan-related tables
ALTER TABLE scanned_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE flashcards ENABLE ROW LEVEL SECURITY;
ALTER TABLE explanation_docs ENABLE ROW LEVEL SECURITY;
ALTER TABLE exercises ENABLE ROW LEVEL SECURITY;
ALTER TABLE generation_results ENABLE ROW LEVEL SECURITY;

-- Scanned items policies
CREATE POLICY "Users can view own scanned items" ON scanned_items
  FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Users can insert own scanned items" ON scanned_items
  FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can update own scanned items" ON scanned_items
  FOR UPDATE USING (auth.uid() = user_id);
CREATE POLICY "Users can delete own scanned items" ON scanned_items
  FOR DELETE USING (auth.uid() = user_id);

-- Flashcards policies
CREATE POLICY "Users can view own flashcards" ON flashcards
  FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Users can insert own flashcards" ON flashcards
  FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can update own flashcards" ON flashcards
  FOR UPDATE USING (auth.uid() = user_id);
CREATE POLICY "Users can delete own flashcards" ON flashcards
  FOR DELETE USING (auth.uid() = user_id);

-- Explanation docs policies
CREATE POLICY "Users can view own explanation docs" ON explanation_docs
  FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Users can insert own explanation docs" ON explanation_docs
  FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can update own explanation docs" ON explanation_docs
  FOR UPDATE USING (auth.uid() = user_id);
CREATE POLICY "Users can delete own explanation docs" ON explanation_docs
  FOR DELETE USING (auth.uid() = user_id);

-- Exercises policies
CREATE POLICY "Users can view own exercises" ON exercises
  FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Users can insert own exercises" ON exercises
  FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can update own exercises" ON exercises
  FOR UPDATE USING (auth.uid() = user_id);
CREATE POLICY "Users can delete own exercises" ON exercises
  FOR DELETE USING (auth.uid() = user_id);

-- Generation results policies
CREATE POLICY "Users can view own generation results" ON generation_results
  FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Users can insert own generation results" ON generation_results
  FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can update own generation results" ON generation_results
  FOR UPDATE USING (auth.uid() = user_id);
CREATE POLICY "Users can delete own generation results" ON generation_results
  FOR DELETE USING (auth.uid() = user_id);
