-- Add feedback and flag fields to chat_messages table
ALTER TABLE chat_messages
ADD COLUMN IF NOT EXISTS image_url TEXT,
ADD COLUMN IF NOT EXISTS feedback_type TEXT CHECK (feedback_type IN ('thumbs_up', 'thumbs_down')),
ADD COLUMN IF NOT EXISTS is_flagged BOOLEAN DEFAULT FALSE,
ADD COLUMN IF NOT EXISTS flag_reason TEXT,
ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW();

-- Add index for flagged messages (for admin review)
CREATE INDEX IF NOT EXISTS idx_chat_messages_flagged ON chat_messages(user_id, is_flagged) WHERE is_flagged = TRUE;

-- Add index for feedback analytics
CREATE INDEX IF NOT EXISTS idx_chat_messages_feedback ON chat_messages(feedback_type) WHERE feedback_type IS NOT NULL;

-- Add trigger for auto-updating updated_at
CREATE TRIGGER update_chat_messages_updated_at BEFORE UPDATE ON chat_messages
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Optional: Create a view for admins to review flagged messages
CREATE OR REPLACE VIEW flagged_messages AS
SELECT
    cm.id,
    cm.user_id,
    up.email as user_email,
    cm.text as message_text,
    cm.sender,
    cm.feedback_type,
    cm.flag_reason,
    cm.timestamp,
    cm.created_at
FROM chat_messages cm
JOIN user_profiles up ON cm.user_id = up.user_id
WHERE cm.is_flagged = TRUE
ORDER BY cm.timestamp DESC;
