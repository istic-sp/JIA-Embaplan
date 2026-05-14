-- 007 — Add user_id to sameka_chat_message + auto-fill trigger
-- Run once against the Supabase DB (SQL Editor → New query → Run)

-- =============================================
-- 1. Add column (nullable so existing rows are kept)
-- =============================================
ALTER TABLE sameka_chat_message
  ADD COLUMN IF NOT EXISTS user_id UUID;

-- 2. Index for fast lookups
CREATE INDEX IF NOT EXISTS idx_chat_message_user_id
  ON sameka_chat_message (user_id);

-- =============================================
-- 3. Trigger: auto-extract user_id on every INSERT
--    - Human messages: extracts UUID from ID="..." in [CONTEXTO DO USUÁRIO]
--    - AI messages: copies user_id from the human message in the same session
-- =============================================
CREATE OR REPLACE FUNCTION trg_set_chat_user_id()
RETURNS TRIGGER AS $$
DECLARE
  _content TEXT;
  _id_str  TEXT;
  _uid     UUID;
BEGIN
  -- Skip if already set
  IF NEW.user_id IS NOT NULL THEN
    RETURN NEW;
  END IF;

  IF NEW.message->>'type' = 'human' THEN
    -- Extract UUID from the [CONTEXTO DO USUÁRIO: ... ID="uuid"] block
    _content := NEW.message->>'content';
    _id_str  := substring(_content from 'ID="([0-9a-fA-F-]{36})"');
    IF _id_str IS NOT NULL THEN
      NEW.user_id := _id_str::UUID;
    END IF;
  ELSE
    -- AI/system message: look up user_id from an earlier human message in same session
    SELECT cm.user_id INTO _uid
      FROM sameka_chat_message cm
     WHERE cm.session_id = NEW.session_id
       AND cm.user_id IS NOT NULL
     LIMIT 1;
    IF _uid IS NOT NULL THEN
      NEW.user_id := _uid;
    END IF;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Drop if exists to allow re-running
DROP TRIGGER IF EXISTS trg_chat_set_user_id ON sameka_chat_message;

CREATE TRIGGER trg_chat_set_user_id
  BEFORE INSERT ON sameka_chat_message
  FOR EACH ROW
  EXECUTE FUNCTION trg_set_chat_user_id();

-- =============================================
-- 4. Backfill user_id for existing rows (one-time)
-- =============================================

-- 4a. Human messages: extract from content
UPDATE sameka_chat_message
   SET user_id = (substring(message->>'content' from 'ID="([0-9a-fA-F-]{36})"'))::UUID
 WHERE message->>'type' = 'human'
   AND user_id IS NULL
   AND message->>'content' LIKE '%ID="%';

-- 4b. AI messages: copy from human messages in same session
UPDATE sameka_chat_message cm
   SET user_id = (
     SELECT cm2.user_id
       FROM sameka_chat_message cm2
      WHERE cm2.session_id = cm.session_id
        AND cm2.user_id IS NOT NULL
      LIMIT 1
   )
 WHERE cm.user_id IS NULL;
