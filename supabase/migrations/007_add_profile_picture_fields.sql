-- Add profile picture fields to user_profiles table
ALTER TABLE user_profiles
ADD COLUMN IF NOT EXISTS profile_bg_color TEXT DEFAULT '#6366F1',
ADD COLUMN IF NOT EXISTS profile_emoji TEXT DEFAULT '😊';

-- Update existing users to have random profile pictures
-- This will be handled by the application layer for new signups
