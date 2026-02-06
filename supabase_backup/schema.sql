-- =============================================================================
-- Studyly Supabase Schema Backup
-- Backed up: 2026-02-06
-- Project: kzvscyzgzvwyhlhyssvz (us-east-2)
-- =============================================================================

-- =====================
-- EXTENSIONS
-- =====================
CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS "pgcrypto" WITH SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS "pg_stat_statements" WITH SCHEMA extensions;

-- =====================
-- TABLES
-- =====================

-- user_profiles
CREATE TABLE public.user_profiles (
    user_id UUID PRIMARY KEY REFERENCES auth.users(id),
    display_name TEXT NOT NULL,
    email TEXT NOT NULL,
    avatar_url TEXT NOT NULL,
    active_plan TEXT NOT NULL,
    focus_areas INTEGER[] NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now(),
    profile_bg_color TEXT DEFAULT '#6366F1',
    profile_emoji TEXT DEFAULT '😊'
);

-- study_sets
CREATE TABLE public.study_sets (
    id UUID PRIMARY KEY DEFAULT extensions.uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES auth.users(id),
    title TEXT NOT NULL,
    flashcards INTEGER NOT NULL DEFAULT 0,
    explanations INTEGER NOT NULL DEFAULT 0,
    exercises INTEGER NOT NULL DEFAULT 0,
    views TEXT NOT NULL,
    border_color INTEGER NOT NULL,
    tag INTEGER NOT NULL,
    description TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- study_plan_tasks
CREATE TABLE public.study_plan_tasks (
    id UUID PRIMARY KEY DEFAULT extensions.uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES auth.users(id),
    title TEXT NOT NULL,
    due_date TIMESTAMPTZ NOT NULL,
    content_type INTEGER NOT NULL,
    is_completed BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- study_documents
CREATE TABLE public.study_documents (
    id UUID PRIMARY KEY DEFAULT extensions.uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES auth.users(id),
    title TEXT NOT NULL,
    size_label TEXT NOT NULL,
    source TEXT NOT NULL,
    category INTEGER NOT NULL,
    type INTEGER NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- chat_messages
CREATE TABLE public.chat_messages (
    id UUID PRIMARY KEY DEFAULT extensions.uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES auth.users(id),
    text TEXT NOT NULL,
    sender INTEGER NOT NULL,
    "timestamp" TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now(),
    image_url TEXT,
    feedback_type TEXT CHECK (feedback_type = ANY (ARRAY['thumbs_up', 'thumbs_down'])),
    is_flagged BOOLEAN DEFAULT false,
    flag_reason TEXT,
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- scanned_items
CREATE TABLE public.scanned_items (
    id UUID PRIMARY KEY DEFAULT extensions.uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES auth.users(id),
    local_image_path TEXT NOT NULL,
    remote_image_url TEXT,
    status INTEGER NOT NULL,
    ocr_text TEXT,
    selected_action TEXT,
    error_message TEXT,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- flashcards
CREATE TABLE public.flashcards (
    id UUID PRIMARY KEY DEFAULT extensions.uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES auth.users(id),
    study_set_id UUID NOT NULL REFERENCES public.study_sets(id),
    front TEXT NOT NULL,
    back TEXT NOT NULL,
    hint TEXT,
    difficulty INTEGER NOT NULL DEFAULT 3,
    srs_ease_factor DOUBLE PRECISION,
    srs_interval INTEGER,
    srs_repetitions INTEGER,
    srs_next_review_date TIMESTAMPTZ,
    srs_last_review_date TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- explanation_docs
CREATE TABLE public.explanation_docs (
    id UUID PRIMARY KEY DEFAULT extensions.uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES auth.users(id),
    study_set_id UUID NOT NULL REFERENCES public.study_sets(id),
    title TEXT NOT NULL,
    summary TEXT NOT NULL,
    key_points TEXT[] NOT NULL,
    content TEXT NOT NULL,
    source_image_url TEXT,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- exercises
CREATE TABLE public.exercises (
    id UUID PRIMARY KEY DEFAULT extensions.uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES auth.users(id),
    study_set_id UUID NOT NULL REFERENCES public.study_sets(id),
    question TEXT NOT NULL,
    options TEXT[] NOT NULL,
    correct_answer TEXT NOT NULL,
    explanation TEXT NOT NULL,
    type INTEGER NOT NULL,
    difficulty INTEGER NOT NULL DEFAULT 3,
    user_answer TEXT,
    is_correct BOOLEAN,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- generation_results
CREATE TABLE public.generation_results (
    id UUID PRIMARY KEY DEFAULT extensions.uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES auth.users(id),
    scanned_item_id UUID NOT NULL REFERENCES public.scanned_items(id),
    type INTEGER NOT NULL,
    status INTEGER NOT NULL,
    input_text TEXT,
    image_url TEXT,
    result JSONB,
    error_message TEXT,
    created_at TIMESTAMPTZ DEFAULT now(),
    completed_at TIMESTAMPTZ
);

-- =====================
-- FUNCTIONS
-- =====================

-- Auto-update updated_at column
CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;

-- Auto-create profile on user signup
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  random_color TEXT;
  random_emoji TEXT;
  color_options TEXT[] := ARRAY['#3B82F6', '#6366F1', '#8B5CF6', '#0EA5E9', '#06B6D4', '#A855F7', '#D946EF', '#EC4899', '#9333EA', '#C026D3', '#10B981', '#22C55E', '#84CC16', '#14B8A6', '#059669', '#F59E0B', '#F97316', '#EF4444', '#FB923C', '#DC2626', '#6B7280', '#374151', '#1F2937', '#78716C', '#57534E'];
  emoji_options TEXT[] := ARRAY['😊', '😃', '😄', '😁', '😆', '😅', '🤣', '😂', '🙂', '😉', '😇', '🥰', '😍', '🤩', '😘', '😎', '🤓', '🐶', '🐱', '🐭', '🐹', '🐰', '🦊', '🐻', '🐼', '🐨', '🐯', '🦁', '🌸', '🌺', '🌻', '🌷', '🌹', '⭐', '🌟', '✨', '💫', '🔥'];
BEGIN
  random_color := color_options[1 + floor(random() * array_length(color_options, 1))::int];
  random_emoji := emoji_options[1 + floor(random() * array_length(emoji_options, 1))::int];

  INSERT INTO public.user_profiles (user_id, email, display_name, avatar_url, active_plan, focus_areas, profile_bg_color, profile_emoji)
  VALUES (
    NEW.id,
    NEW.email,
    COALESCE(split_part(NEW.email, '@', 1), 'User'),
    'https://api.dicebear.com/7.x/avataaars/svg?seed=' || NEW.id::text,
    'Free',
    ARRAY[0, 1, 2],
    random_color,
    random_emoji
  );
  RETURN NEW;
END;
$$;

-- =====================
-- TRIGGERS
-- =====================

-- Auto-create profile trigger (on auth.users)
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_user();

-- updated_at triggers for all public tables
CREATE TRIGGER update_user_profiles_updated_at BEFORE UPDATE ON public.user_profiles FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_study_sets_updated_at BEFORE UPDATE ON public.study_sets FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_study_plan_tasks_updated_at BEFORE UPDATE ON public.study_plan_tasks FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_study_documents_updated_at BEFORE UPDATE ON public.study_documents FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_chat_messages_updated_at BEFORE UPDATE ON public.chat_messages FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_scanned_items_updated_at BEFORE UPDATE ON public.scanned_items FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_flashcards_updated_at BEFORE UPDATE ON public.flashcards FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_explanation_docs_updated_at BEFORE UPDATE ON public.explanation_docs FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_exercises_updated_at BEFORE UPDATE ON public.exercises FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- =====================
-- ROW LEVEL SECURITY
-- =====================

-- Enable RLS on all public tables
ALTER TABLE public.user_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.study_sets ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.study_plan_tasks ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.study_documents ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.chat_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.scanned_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.flashcards ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.explanation_docs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.exercises ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.generation_results ENABLE ROW LEVEL SECURITY;

-- user_profiles policies
CREATE POLICY "Users can view own profile" ON public.user_profiles FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Users can insert own profile" ON public.user_profiles FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can update own profile" ON public.user_profiles FOR UPDATE USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

-- study_sets policies
CREATE POLICY "Users can view own study sets" ON public.study_sets FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Users can insert own study sets" ON public.study_sets FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can update own study sets" ON public.study_sets FOR UPDATE USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can delete own study sets" ON public.study_sets FOR DELETE USING (auth.uid() = user_id);

-- study_plan_tasks policies
CREATE POLICY "Users can view own tasks" ON public.study_plan_tasks FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Users can insert own tasks" ON public.study_plan_tasks FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can update own tasks" ON public.study_plan_tasks FOR UPDATE USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can delete own tasks" ON public.study_plan_tasks FOR DELETE USING (auth.uid() = user_id);

-- study_documents policies
CREATE POLICY "Users can view own documents" ON public.study_documents FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Users can insert own documents" ON public.study_documents FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can update own documents" ON public.study_documents FOR UPDATE USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can delete own documents" ON public.study_documents FOR DELETE USING (auth.uid() = user_id);

-- chat_messages policies
CREATE POLICY "Users can view own messages" ON public.chat_messages FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Users can insert own messages" ON public.chat_messages FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can delete own messages" ON public.chat_messages FOR DELETE USING (auth.uid() = user_id);

-- scanned_items policies
CREATE POLICY "Users can view own scanned items" ON public.scanned_items FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Users can insert own scanned items" ON public.scanned_items FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can update own scanned items" ON public.scanned_items FOR UPDATE USING (auth.uid() = user_id);
CREATE POLICY "Users can delete own scanned items" ON public.scanned_items FOR DELETE USING (auth.uid() = user_id);

-- flashcards policies
CREATE POLICY "Users can view own flashcards" ON public.flashcards FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Users can insert own flashcards" ON public.flashcards FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can update own flashcards" ON public.flashcards FOR UPDATE USING (auth.uid() = user_id);
CREATE POLICY "Users can delete own flashcards" ON public.flashcards FOR DELETE USING (auth.uid() = user_id);

-- explanation_docs policies
CREATE POLICY "Users can view own explanation docs" ON public.explanation_docs FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Users can insert own explanation docs" ON public.explanation_docs FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can update own explanation docs" ON public.explanation_docs FOR UPDATE USING (auth.uid() = user_id);
CREATE POLICY "Users can delete own explanation docs" ON public.explanation_docs FOR DELETE USING (auth.uid() = user_id);

-- exercises policies
CREATE POLICY "Users can view own exercises" ON public.exercises FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Users can insert own exercises" ON public.exercises FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can update own exercises" ON public.exercises FOR UPDATE USING (auth.uid() = user_id);
CREATE POLICY "Users can delete own exercises" ON public.exercises FOR DELETE USING (auth.uid() = user_id);

-- generation_results policies
CREATE POLICY "Users can view own generation results" ON public.generation_results FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Users can insert own generation results" ON public.generation_results FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can update own generation results" ON public.generation_results FOR UPDATE USING (auth.uid() = user_id);
CREATE POLICY "Users can delete own generation results" ON public.generation_results FOR DELETE USING (auth.uid() = user_id);

-- =====================
-- STORAGE
-- =====================

-- Create scans bucket (private)
INSERT INTO storage.buckets (id, name, public) VALUES ('scans', 'scans', false);

-- Storage RLS policies for scans bucket
CREATE POLICY "Users can read own scans" ON storage.objects FOR SELECT
  USING (bucket_id = 'scans' AND (auth.uid())::text = (storage.foldername(name))[1]);

CREATE POLICY "Users can upload own scans" ON storage.objects FOR INSERT
  WITH CHECK (bucket_id = 'scans' AND (auth.uid())::text = (storage.foldername(name))[1]);

CREATE POLICY "Users can update own scans" ON storage.objects FOR UPDATE
  USING (bucket_id = 'scans' AND (auth.uid())::text = (storage.foldername(name))[1]);

CREATE POLICY "Users can delete own scans" ON storage.objects FOR DELETE
  USING (bucket_id = 'scans' AND (auth.uid())::text = (storage.foldername(name))[1]);
