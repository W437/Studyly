-- This file contains example seed data for testing
-- You can run this after creating a test user account

-- Note: Replace 'YOUR_USER_ID' with your actual user ID from auth.users
-- You can get this by running: SELECT id FROM auth.users WHERE email = 'your-email@example.com';

-- Example seed data (commented out by default)
/*
-- Insert sample user profile
INSERT INTO user_profiles (user_id, display_name, email, avatar_url, active_plan, focus_areas)
VALUES (
  'YOUR_USER_ID'::uuid,
  'John Doe',
  'john@example.com',
  'https://api.dicebear.com/7.x/avataaars/svg?seed=John',
  'MCAT 2025',
  ARRAY[0, 4, 5]  -- biology, mathematics, physics
);

-- Insert sample study sets
INSERT INTO study_sets (user_id, title, flashcards, explanations, exercises, views, border_color, tag, description)
VALUES
  (
    'YOUR_USER_ID'::uuid,
    'Organic Chemistry Fundamentals',
    45,
    12,
    8,
    '2.3k',
    4280391695,  -- Color value
    0,  -- biology tag
    'Master the basics of organic chemistry including nomenclature, reactions, and mechanisms.'
  ),
  (
    'YOUR_USER_ID'::uuid,
    'Physics Mechanics',
    32,
    15,
    10,
    '1.8k',
    4291611852,
    5,  -- physics tag
    'Understand classical mechanics, kinematics, and dynamics.'
  ),
  (
    'YOUR_USER_ID'::uuid,
    'Calculus I',
    28,
    20,
    15,
    '3.1k',
    4287137928,
    4,  -- mathematics tag
    'Limits, derivatives, and integrals for beginners.'
  );

-- Insert sample tasks for today
INSERT INTO study_plan_tasks (user_id, title, due_date, content_type, is_completed)
VALUES
  (
    'YOUR_USER_ID'::uuid,
    'Review Organic Chemistry Flashcards',
    CURRENT_DATE,
    1,  -- flashcards
    false
  ),
  (
    'YOUR_USER_ID'::uuid,
    'Complete Physics Problem Set',
    CURRENT_DATE,
    3,  -- exercises
    false
  ),
  (
    'YOUR_USER_ID'::uuid,
    'Read Calculus Chapter 3',
    CURRENT_DATE,
    2,  -- explanations
    true
  );

-- Insert sample documents
INSERT INTO study_documents (user_id, title, size_label, source, category, type)
VALUES
  (
    'YOUR_USER_ID'::uuid,
    'MCAT Biology Notes',
    '2.4 MB',
    'Personal Notes',
    0,  -- biology
    2   -- explanations
  ),
  (
    'YOUR_USER_ID'::uuid,
    'Physics Formula Sheet',
    '156 KB',
    'Course Materials',
    5,  -- physics
    1   -- flashcards
  );

-- Insert sample chat messages
INSERT INTO chat_messages (user_id, text, sender, timestamp)
VALUES
  (
    'YOUR_USER_ID'::uuid,
    'Hello! Can you help me understand organic chemistry nomenclature?',
    1,  -- user
    NOW() - INTERVAL '5 minutes'
  ),
  (
    'YOUR_USER_ID'::uuid,
    'Of course! Organic chemistry nomenclature follows IUPAC rules. Let me break it down for you...',
    0,  -- bot
    NOW() - INTERVAL '4 minutes'
  ),
  (
    'YOUR_USER_ID'::uuid,
    'That makes sense! Can you give me an example with alkanes?',
    1,  -- user
    NOW() - INTERVAL '2 minutes'
  );
*/
