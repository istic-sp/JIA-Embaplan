-- =============================================
-- Sameka — 005: Add coverage areas (estados/cidades)
-- Stores estados and cidades as JSONB arrays in
-- raw_user_meta_data. Admin = all.
-- Run AFTER 004_add_company_name.sql
-- =============================================

-- =======  UP  ========

-- 1) list_users: now returns estados and cidades
DROP FUNCTION IF EXISTS sameka_admin_list_users();
CREATE OR REPLACE FUNCTION sameka_admin_list_users()
RETURNS TABLE(
  user_id      UUID,
  email        TEXT,
  full_name    TEXT,
  role         TEXT,
  company_name TEXT,
  estados      JSONB,
  cidades      JSONB,
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
      COALESCE(u.raw_user_meta_data->'estados', '[]'::jsonb) AS estados,
      COALESCE(u.raw_user_meta_data->'cidades', '[]'::jsonb) AS cidades,
      u.created_at
    FROM auth.users u
    WHERE u.raw_user_meta_data->>'company_name' = 'sameka'
    ORDER BY u.created_at DESC;
END;
$$;

-- 2) update_user: now accepts estados/cidades JSONB arrays
DROP FUNCTION IF EXISTS sameka_admin_update_user(UUID, TEXT, TEXT);
CREATE OR REPLACE FUNCTION sameka_admin_update_user(
  p_user_id   UUID,
  p_full_name TEXT,
  p_role      TEXT    DEFAULT NULL,
  p_estados   JSONB   DEFAULT NULL,
  p_cidades   JSONB   DEFAULT NULL
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
  IF p_estados IS NOT NULL THEN
    new_meta := new_meta || jsonb_build_object('estados', p_estados);
  END IF;
  IF p_cidades IS NOT NULL THEN
    new_meta := new_meta || jsonb_build_object('cidades', p_cidades);
  END IF;
  UPDATE auth.users
  SET raw_user_meta_data = COALESCE(raw_user_meta_data, '{}'::jsonb) || new_meta,
      updated_at = NOW()
  WHERE id = p_user_id;
END;
$$;

GRANT EXECUTE ON FUNCTION sameka_admin_list_users() TO authenticated;
GRANT EXECUTE ON FUNCTION sameka_admin_update_user(UUID, TEXT, TEXT, JSONB, JSONB) TO authenticated;

NOTIFY pgrst, 'reload schema';

-- =======  DOWN  ========
-- Reverts to 004 signatures (no estados/cidades)
--
-- DROP FUNCTION IF EXISTS sameka_admin_list_users();
-- CREATE OR REPLACE FUNCTION sameka_admin_list_users()
-- RETURNS TABLE(
--   user_id      UUID,
--   email        TEXT,
--   full_name    TEXT,
--   role         TEXT,
--   company_name TEXT,
--   created_at   TIMESTAMPTZ
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
--       COALESCE(u.raw_user_meta_data->>'company_name', '')::TEXT AS company_name,
--       u.created_at
--     FROM auth.users u
--     WHERE u.raw_user_meta_data->>'company_name' = 'sameka'
--     ORDER BY u.created_at DESC;
-- END;
-- $$;
--
-- DROP FUNCTION IF EXISTS sameka_admin_update_user(UUID, TEXT, TEXT, JSONB, JSONB);
-- CREATE OR REPLACE FUNCTION sameka_admin_update_user(
--   p_user_id      UUID,
--   p_full_name    TEXT,
--   p_role         TEXT DEFAULT NULL
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
--   new_meta := jsonb_build_object('full_name', p_full_name, 'company_name', 'sameka');
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
-- GRANT EXECUTE ON FUNCTION sameka_admin_list_users() TO authenticated;
-- GRANT EXECUTE ON FUNCTION sameka_admin_update_user(UUID, TEXT, TEXT) TO authenticated;
--
-- NOTIFY pgrst, 'reload schema';
