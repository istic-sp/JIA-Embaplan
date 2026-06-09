-- =============================================
-- Embaplan — 012: Carga incremental mês a mês
-- O modelo de snapshots já é append-only (cada upload =
-- 1 batch; a timeline acumula todos os batches). Esta
-- migration adiciona o conceito de "período" (mês de
-- referência) ao batch para:
--   - rotular o histórico por mês (jan/fev/mar...) em vez
--     de só pela data do upload;
--   - tornar o reenvio de um mesmo mês IDEMPOTENTE (substitui
--     o batch daquele mês em vez de duplicar) → Richard pode
--     mandar só "março" sem reprocessar jan+fev.
-- Run AFTER 011_overview_link_metrics.sql
-- =============================================

-- =======  UP  ========

ALTER TABLE embaplan_upload_batch
  ADD COLUMN IF NOT EXISTS periodo DATE;

CREATE INDEX IF NOT EXISTS idx_batch_periodo
  ON embaplan_upload_batch (periodo);

-- ---------------------------------------------
-- RPC: cria (ou substitui) o batch de um mês.
--   p_periodo aceita 'YYYY-MM' ou 'YYYY-MM-DD' (normaliza
--   para o 1º dia do mês). Se p_replace = TRUE e já existir
--   batch para o mesmo mês, ele é apagado (cascateando os
--   snapshots) antes de criar o novo → reenvio idempotente.
-- ---------------------------------------------
CREATE OR REPLACE FUNCTION sameka_embaplan_create_month_batch(
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
  -- Normaliza o período para o primeiro dia do mês.
  IF p_periodo IS NULL OR TRIM(p_periodo) = '' THEN
    _periodo := date_trunc('month', NOW())::DATE;
  ELSIF p_periodo ~ '^[0-9]{4}-[0-9]{2}$' THEN
    _periodo := to_date(p_periodo || '-01', 'YYYY-MM-DD');
  ELSE
    _periodo := date_trunc('month', p_periodo::DATE)::DATE;
  END IF;

  _rotulo := COALESCE(
    NULLIF(TRIM(p_rotulo), ''),
    initcap(to_char(_periodo, 'TMMonth YYYY'))
  );

  -- Reenvio idempotente: remove o batch anterior do mesmo mês.
  IF p_replace THEN
    DELETE FROM embaplan_upload_batch WHERE periodo = _periodo;
  END IF;

  INSERT INTO embaplan_upload_batch (user_id, rotulo, arquivo_nome, periodo)
  VALUES (p_user_id, _rotulo, p_arquivo_nome, _periodo)
  RETURNING id INTO _batch_id;

  RETURN _batch_id;
END;
$$;

-- ---------------------------------------------
-- Atualiza a timeline para expor o período (mês) do batch.
-- ---------------------------------------------
DROP FUNCTION IF EXISTS sameka_embaplan_ad_timeline(TEXT, INTEGER);

CREATE OR REPLACE FUNCTION sameka_embaplan_ad_timeline(
  p_anuncio_indice TEXT,
  p_limit          INTEGER DEFAULT 24
)
RETURNS TABLE(
  batch_id          BIGINT,
  rotulo            TEXT,
  periodo           DATE,
  data_upload       TIMESTAMPTZ,
  versao            BIGINT,
  loja              TEXT,
  produto           TEXT,
  titulo            TEXT,
  status            TEXT,
  link              TEXT,
  saude             NUMERIC,
  acos              NUMERIC,
  roas              NUMERIC,
  conversao         NUMERIC,
  ctr               NUMERIC,
  lucro             NUMERIC,
  receita           NUMERIC,
  vendas            NUMERIC,
  investimento_ads  NUMERIC,
  ticket_medio      NUMERIC,
  delta_saude       NUMERIC,
  delta_lucro       NUMERIC,
  delta_acos        NUMERIC,
  tendencia         TEXT
)
SECURITY DEFINER
SET search_path = public
LANGUAGE sql
STABLE
AS $$
  WITH serie AS (
    SELECT
      s.batch_id,
      b.rotulo,
      b.periodo,
      b.created_at AS data_upload,
      ROW_NUMBER() OVER (ORDER BY COALESCE(b.periodo, b.created_at::date), b.created_at) AS versao,
      s.loja, s.produto, s.titulo, s.status,
      sameka_embaplan_extract_link(s.metrics_jsonb) AS link,
      s.saude, s.acos, s.roas, s.conversao, s.ctr,
      s.lucro, s.receita, s.vendas, s.investimento_ads, s.ticket_medio,
      LAG(s.saude) OVER (ORDER BY COALESCE(b.periodo, b.created_at::date), b.created_at) AS prev_saude,
      LAG(s.lucro) OVER (ORDER BY COALESCE(b.periodo, b.created_at::date), b.created_at) AS prev_lucro,
      LAG(s.acos)  OVER (ORDER BY COALESCE(b.periodo, b.created_at::date), b.created_at) AS prev_acos
    FROM embaplan_analysis_snapshot s
    JOIN embaplan_upload_batch b ON b.id = s.batch_id
    WHERE s.anuncio_indice = p_anuncio_indice
  )
  SELECT
    batch_id, rotulo, periodo, data_upload, versao,
    loja, produto, titulo, status, link,
    saude, acos, roas, conversao, ctr,
    lucro, receita, vendas, investimento_ads, ticket_medio,
    (saude - prev_saude) AS delta_saude,
    (lucro - prev_lucro) AS delta_lucro,
    (acos  - prev_acos)  AS delta_acos,
    CASE
      WHEN prev_saude IS NULL THEN 'novo'
      WHEN (saude - prev_saude) >= 0.5 OR (lucro - prev_lucro) > 0 THEN 'evoluindo'
      WHEN (saude - prev_saude) <= -0.5 OR (lucro - prev_lucro) < 0 THEN 'piorando'
      ELSE 'estavel'
    END AS tendencia
  FROM serie
  ORDER BY COALESCE(periodo, data_upload::date), data_upload
  LIMIT p_limit;
$$;

GRANT EXECUTE ON FUNCTION sameka_embaplan_create_month_batch(UUID, TEXT, TEXT, TEXT, BOOLEAN) TO authenticated;
GRANT EXECUTE ON FUNCTION sameka_embaplan_ad_timeline(TEXT, INTEGER) TO authenticated;

NOTIFY pgrst, 'reload schema';

-- =======  DOWN  ========
-- DROP FUNCTION IF EXISTS sameka_embaplan_create_month_batch(UUID, TEXT, TEXT, TEXT, BOOLEAN);
-- ALTER TABLE embaplan_upload_batch DROP COLUMN IF EXISTS periodo;
-- (re-aplicar 011_overview_link_metrics.sql para restaurar a timeline)
-- NOTIFY pgrst, 'reload schema';
