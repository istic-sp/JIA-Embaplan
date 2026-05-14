-- =============================================
-- Sameka — 004: Add company_name filter
-- Differentiates users between projects using
-- raw_user_meta_data->>'company_name'.
-- list_users now returns only 'sameka' users.
-- Run AFTER 003_admin_guards.sql
-- =============================================

-- =======  UP  ========

-- 1) is_admin: also require company_name = 'sameka'
CREATE OR REPLACE FUNCTION sameka_is_admin()
RETURNS BOOLEAN
SECURITY DEFINER
SET search_path = auth, public
LANGUAGE sql
STABLE
AS $$
  SELECT COALESCE(
    (SELECT raw_user_meta_data->>'role' = 'admin'
            AND raw_user_meta_data->>'company_name' = 'sameka'
     FROM auth.users
     WHERE id = auth.uid()),
    false
  );
$$;

-- 2) list_users: filter by company_name = 'sameka', expose company_name column
DROP FUNCTION IF EXISTS sameka_admin_list_users();
CREATE OR REPLACE FUNCTION sameka_admin_list_users()
RETURNS TABLE(
  user_id      UUID,
  email        TEXT,
  full_name    TEXT,
  role         TEXT,
  company_name TEXT,
  created_at   TIMESTAMPTZ
)
SECURITY DEFINER
SET search_path = auth, public
LANGUAGE plpgsql
STABLE
AS $$
BEGIN
  IF NOT sameka_is_admin() THEN
    RAISE EXCEPTION 'Acesso negado: apenas administradores.' USING ERRCODE = '42501';
  END IF;
  RETURN QUERY
    SELECT
      u.id AS user_id,
      u.email::TEXT,
      COALESCE(u.raw_user_meta_data->>'full_name', '')::TEXT AS full_name,
      COALESCE(u.raw_user_meta_data->>'role', 'visualizador')::TEXT AS role,
      COALESCE(u.raw_user_meta_data->>'company_name', '')::TEXT AS company_name,
      u.created_at
    FROM auth.users u
    WHERE u.raw_user_meta_data->>'company_name' = 'sameka'
    ORDER BY u.created_at DESC;
END;
$$;

-- 3) update_user: persist company_name in metadata
DROP FUNCTION IF EXISTS sameka_admin_update_user(UUID, TEXT, TEXT);
CREATE OR REPLACE FUNCTION sameka_admin_update_user(
  p_user_id      UUID,
  p_full_name    TEXT,
  p_role         TEXT DEFAULT NULL
)
RETURNS VOID
SECURITY DEFINER
SET search_path = auth, public
LANGUAGE plpgsql
AS $$
DECLARE
  new_meta JSONB;
BEGIN
  IF NOT sameka_is_admin() THEN
    RAISE EXCEPTION 'Acesso negado: apenas administradores.' USING ERRCODE = '42501';
  END IF;
  new_meta := jsonb_build_object('full_name', p_full_name, 'company_name', 'sameka');
  IF p_role IS NOT NULL THEN
    new_meta := new_meta || jsonb_build_object('role', p_role);
  END IF;
  UPDATE auth.users
  SET raw_user_meta_data = COALESCE(raw_user_meta_data, '{}'::jsonb) || new_meta,
      updated_at = NOW()
  WHERE id = p_user_id;
END;
$$;

-- 4) Backfill: stamp all existing users that don't have company_name yet
-- with 'sameka' so they appear in list_users after migration.
UPDATE auth.users
SET raw_user_meta_data = COALESCE(raw_user_meta_data, '{}'::jsonb)
                         || '{"company_name": "sameka"}'::jsonb,
    updated_at = NOW()
WHERE raw_user_meta_data->>'company_name' IS NULL
   OR raw_user_meta_data->>'company_name' = '';

-- Re-grant (signatures unchanged for confirm/delete, new signature for list/update)
GRANT EXECUTE ON FUNCTION sameka_is_admin() TO authenticated;
GRANT EXECUTE ON FUNCTION sameka_admin_list_users() TO authenticated;
GRANT EXECUTE ON FUNCTION sameka_admin_update_user(UUID, TEXT, TEXT) TO authenticated;

NOTIFY pgrst, 'reload schema';

-- =======  DOWN  ========
-- Reverts to 003 versions (no company_name filter)
--
-- CREATE OR REPLACE FUNCTION sameka_is_admin()
-- RETURNS BOOLEAN
-- SECURITY DEFINER
-- SET search_path = auth, public
-- LANGUAGE sql
-- STABLE
-- AS $$
--   SELECT COALESCE(
--     (SELECT raw_user_meta_data->>'role'
--      FROM auth.users
--      WHERE id = auth.uid()) = 'admin',
--     false
--   );
-- $$;
--
-- DROP FUNCTION IF EXISTS sameka_admin_list_users();
-- CREATE OR REPLACE FUNCTION sameka_admin_list_users()
-- RETURNS TABLE(
--   user_id    UUID,
--   email      TEXT,
--   full_name  TEXT,
--   role       TEXT,
--   created_at TIMESTAMPTZ
-- )
-- SECURITY DEFINER
-- SET search_path = auth, public
-- LANGUAGE plpgsql
-- STABLE
-- AS $$
-- BEGIN
--   IF NOT sameka_is_admin() THEN
--     RAISE EXCEPTION 'Acesso negado: apenas administradores.' USING ERRCODE = '42501';
--   END IF;
--   RETURN QUERY
--     SELECT
--       u.id AS user_id,
--       u.email::TEXT,
--       COALESCE(u.raw_user_meta_data->>'full_name', '')::TEXT AS full_name,
--       COALESCE(u.raw_user_meta_data->>'role', 'visualizador')::TEXT AS role,
--       u.created_at
--     FROM auth.users u
--     ORDER BY u.created_at DESC;
-- END;
-- $$;
--
-- DROP FUNCTION IF EXISTS sameka_admin_update_user(UUID, TEXT, TEXT);
-- CREATE OR REPLACE FUNCTION sameka_admin_update_user(
--   p_user_id   UUID,
--   p_full_name TEXT,
--   p_role      TEXT DEFAULT NULL
-- )
-- RETURNS VOID
-- SECURITY DEFINER
-- SET search_path = auth, public
-- LANGUAGE plpgsql
-- AS $$
-- DECLARE
--   new_meta JSONB;
-- BEGIN
--   IF NOT sameka_is_admin() THEN
--     RAISE EXCEPTION 'Acesso negado: apenas administradores.' USING ERRCODE = '42501';
--   END IF;
--   new_meta := jsonb_build_object('full_name', p_full_name);
--   IF p_role IS NOT NULL THEN
--     new_meta := new_meta || jsonb_build_object('role', p_role);
--   END IF;
--   UPDATE auth.users
--   SET raw_user_meta_data = COALESCE(raw_user_meta_data, '{}'::jsonb) || new_meta,
--       updated_at = NOW()
--   WHERE id = p_user_id;
-- END;
-- $$;
--
-- GRANT EXECUTE ON FUNCTION sameka_is_admin() TO authenticated;
-- GRANT EXECUTE ON FUNCTION sameka_admin_list_users() TO authenticated;
-- GRANT EXECUTE ON FUNCTION sameka_admin_update_user(UUID, TEXT, TEXT) TO authenticated;
--
-- NOTIFY pgrst, 'reload schema';
