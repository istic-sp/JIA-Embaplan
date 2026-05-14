-- =============================================
-- Sameka — 006: Prevent self-deletion
-- Users cannot delete themselves via RPC.
-- Run AFTER 005_add_coverage_areas.sql
-- =============================================

-- =======  UP  ========

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
  IF p_user_id = auth.uid() THEN
    RAISE EXCEPTION 'Você não pode excluir sua própria conta.' USING ERRCODE = '42501';
  END IF;
  DELETE FROM auth.users WHERE id = p_user_id;
END;
$$;

GRANT EXECUTE ON FUNCTION sameka_admin_delete_user(UUID) TO authenticated;

NOTIFY pgrst, 'reload schema';

-- =======  DOWN  ========
-- Reverts to 003/005 version (no self-delete guard)
--
-- CREATE OR REPLACE FUNCTION sameka_admin_delete_user(p_user_id UUID)
-- RETURNS VOID
-- SECURITY DEFINER
-- SET search_path = auth, public
-- LANGUAGE plpgsql
-- AS $$
-- BEGIN
--   IF NOT sameka_is_admin() THEN
--     RAISE EXCEPTION 'Acesso negado: apenas administradores.' USING ERRCODE = '42501';
--   END IF;
--   DELETE FROM auth.users WHERE id = p_user_id;
-- END;
-- $$;
--
-- GRANT EXECUTE ON FUNCTION sameka_admin_delete_user(UUID) TO authenticated;
--
-- NOTIFY pgrst, 'reload schema';
