-- =============================================
-- Universo Tintas — 003: Admin-only guards
-- Adds role check inside SECURITY DEFINER functions
-- so only users with role='admin' can call them.
-- =============================================

-- =======  UP  ========

-- Helper: check if caller is admin
CREATE OR REPLACE FUNCTION sameka_is_admin()
RETURNS BOOLEAN
SECURITY DEFINER
SET search_path = auth, public
LANGUAGE sql
STABLE
AS $$
  SELECT COALESCE(
    (SELECT raw_user_meta_data->>'role'
     FROM auth.users
     WHERE id = auth.uid()) = 'admin',
    false
  );
$$;

-- list_users: admin-only
DROP FUNCTION IF EXISTS sameka_admin_list_users();
CREATE OR REPLACE FUNCTION sameka_admin_list_users()
RETURNS TABLE(
  user_id    UUID,
  email      TEXT,
  full_name  TEXT,
  role       TEXT,
  created_at TIMESTAMPTZ
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
      u.created_at
    FROM auth.users u
    ORDER BY u.created_at DESC;
END;
$$;

-- confirm_user: admin-only
CREATE OR REPLACE FUNCTION sameka_admin_confirm_user(p_user_id UUID)
RETURNS VOID
SECURITY DEFINER
SET search_path = auth, public
LANGUAGE plpgsql
AS $$
BEGIN
  IF NOT sameka_is_admin() THEN
    RAISE EXCEPTION 'Acesso negado: apenas administradores.' USING ERRCODE = '42501';
  END IF;
  UPDATE auth.users
  SET email_confirmed_at = NOW(),
      updated_at = NOW()
  WHERE id = p_user_id;
END;
$$;

-- update_user: admin-only
DROP FUNCTION IF EXISTS sameka_admin_update_user(UUID, TEXT, TEXT);
CREATE OR REPLACE FUNCTION sameka_admin_update_user(
  p_user_id   UUID,
  p_full_name TEXT,
  p_role      TEXT DEFAULT NULL
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
  new_meta := jsonb_build_object('full_name', p_full_name);
  IF p_role IS NOT NULL THEN
    new_meta := new_meta || jsonb_build_object('role', p_role);
  END IF;
  UPDATE auth.users
  SET raw_user_meta_data = COALESCE(raw_user_meta_data, '{}'::jsonb) || new_meta,
      updated_at = NOW()
  WHERE id = p_user_id;
END;
$$;

-- delete_user: admin-only
CREATE OR REPLACE FUNCTION sameka_admin_delete_user(p_user_id UUID)
RETURNS VOID
SECURITY DEFINER
SET search_path = auth, public
LANGUAGE plpgsql
AS $$
BEGIN
  IF NOT sameka_is_admin() THEN
    RAISE EXCEPTION 'Acesso negado: apenas administradores.' USING ERRCODE = '42501';
  END IF;
  DELETE FROM auth.users WHERE id = p_user_id;
END;
$$;

GRANT EXECUTE ON FUNCTION sameka_is_admin() TO authenticated;
GRANT EXECUTE ON FUNCTION sameka_admin_list_users() TO authenticated;
GRANT EXECUTE ON FUNCTION sameka_admin_confirm_user(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION sameka_admin_update_user(UUID, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION sameka_admin_delete_user(UUID) TO authenticated;

NOTIFY pgrst, 'reload schema';

-- =======  DOWN  ========
-- Reverts to 002 versions (no admin guard)
--
-- DROP FUNCTION IF EXISTS sameka_is_admin();
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
-- LANGUAGE sql
-- STABLE
-- AS $$
--   SELECT
--     id AS user_id,
--     email::TEXT,
--     COALESCE(raw_user_meta_data->>'full_name', '')::TEXT AS full_name,
--     COALESCE(raw_user_meta_data->>'role', 'visualizador')::TEXT AS role,
--     created_at
--   FROM auth.users
--   ORDER BY created_at DESC;
-- $$;
--
-- CREATE OR REPLACE FUNCTION sameka_admin_confirm_user(p_user_id UUID)
-- RETURNS VOID
-- SECURITY DEFINER
-- SET search_path = auth, public
-- LANGUAGE plpgsql
-- AS $$
-- BEGIN
--   UPDATE auth.users
--   SET email_confirmed_at = NOW(),
--       updated_at = NOW()
--   WHERE id = p_user_id;
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
-- CREATE OR REPLACE FUNCTION sameka_admin_delete_user(p_user_id UUID)
-- RETURNS VOID
-- SECURITY DEFINER
-- SET search_path = auth, public
-- LANGUAGE plpgsql
-- AS $$
-- BEGIN
--   DELETE FROM auth.users WHERE id = p_user_id;
-- END;
-- $$;
--
-- GRANT EXECUTE ON FUNCTION sameka_admin_list_users() TO authenticated;
-- GRANT EXECUTE ON FUNCTION sameka_admin_confirm_user(UUID) TO authenticated;
-- GRANT EXECUTE ON FUNCTION sameka_admin_update_user(UUID, TEXT, TEXT) TO authenticated;
-- GRANT EXECUTE ON FUNCTION sameka_admin_delete_user(UUID) TO authenticated;
--
-- NOTIFY pgrst, 'reload schema';
