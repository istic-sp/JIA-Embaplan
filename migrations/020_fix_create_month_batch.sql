-- =============================================
-- Embaplan — 020: Corrige criação de batch para múltiplas datas
-- 1) periodo AUSENTE não vira "hoje": levanta EXCEPTION (evita
--    substituir batch existente por engano — causa raiz do bug).
-- 2) Replace escopado por (periodo, user_id): nunca apaga batch
--    de outra data ou de outro usuário.
-- Run AFTER 019_chronology_by_period.sql
-- =============================================

-- =======  UP  ========
CREATE OR REPLACE FUNCTION embaplan_create_month_batch(
  p_user_id      UUID DEFAULT NULL,
  p_periodo      TEXT DEFAULT NULL,
  p_rotulo       TEXT DEFAULT NULL,
  p_arquivo_nome TEXT DEFAULT NULL,
  p_replace      BOOLEAN DEFAULT TRUE
)
RETURNS BIGINT
SECURITY DEFINER
SET search_path = public
LANGUAGE plpgsql
AS $$
DECLARE
  _periodo  DATE;
  _batch_id BIGINT;
  _rotulo   TEXT;
BEGIN
  -- periodo é obrigatório: NÃO assumir a data de hoje.
  IF p_periodo IS NULL OR TRIM(p_periodo) = '' THEN
    RAISE EXCEPTION 'periodo obrigatório para criar batch (data de referência ausente).'
      USING ERRCODE = '22004';
  ELSIF p_periodo ~ '^[0-9]{4}-[0-9]{2}$' THEN
    _periodo := to_date(p_periodo || '-01', 'YYYY-MM-DD');
  ELSIF p_periodo ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' THEN
    _periodo := to_date(p_periodo, 'YYYY-MM-DD');
  ELSE
    _periodo := p_periodo::DATE;
  END IF;

  _rotulo := COALESCE(
    NULLIF(TRIM(p_rotulo), ''),
    initcap(to_char(_periodo, 'TMMonth YYYY'))
  );

  -- Reenvio idempotente: remove APENAS o batch da mesma data e mesmo usuário.
  IF p_replace THEN
    DELETE FROM embaplan_upload_batch
    WHERE periodo = _periodo
      AND user_id IS NOT DISTINCT FROM p_user_id;
  END IF;

  INSERT INTO embaplan_upload_batch (user_id, rotulo, arquivo_nome, periodo, created_at)
  VALUES (p_user_id, _rotulo, p_arquivo_nome, _periodo, _periodo::timestamptz)
  RETURNING id INTO _batch_id;

  RETURN _batch_id;
END;
$$;

GRANT EXECUTE ON FUNCTION embaplan_create_month_batch(UUID, TEXT, TEXT, TEXT, BOOLEAN) TO authenticated;
NOTIFY pgrst, 'reload schema';

-- ---------------------------------------------
-- Unicidade por data: consolidar duplicatas e criar índice único.
-- ---------------------------------------------
-- 1) Mantém o batch de maior id por (periodo, user_id); apaga os demais
--    (cascade remove snapshots dos batches removidos).
DELETE FROM embaplan_upload_batch b
USING (
  SELECT periodo, user_id, MAX(id) AS keep_id
  FROM embaplan_upload_batch
  WHERE periodo IS NOT NULL
  GROUP BY periodo, user_id
  HAVING COUNT(*) > 1
) dup
WHERE b.periodo = dup.periodo
  AND b.user_id IS NOT DISTINCT FROM dup.user_id
  AND b.id <> dup.keep_id;

-- 2) Índice único parcial (trata user_id NULL via COALESCE).
DROP INDEX IF EXISTS idx_batch_periodo;
CREATE UNIQUE INDEX IF NOT EXISTS uniq_batch_periodo_user
  ON embaplan_upload_batch (
    periodo,
    COALESCE(user_id, '00000000-0000-0000-0000-000000000000'::uuid)
  )
  WHERE periodo IS NOT NULL;

-- =======  DOWN  ========
-- (reaplicar 019_chronology_by_period.sql para reverter)
