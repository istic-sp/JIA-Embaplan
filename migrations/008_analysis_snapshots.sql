-- =============================================
-- Embaplan — 008: Histórico de anúncios (linha do tempo)
-- Cada upload de planilha vira um "batch" (versão/rodada).
-- Para cada anúncio do SUMARIO_PRE_CALCULADO grava-se um
-- snapshot append-only, permitindo timeline e comparação
-- "antes x depois" (Épico 1 do PRD).
-- Run AFTER 007_add_user_to_chat.sql
-- =============================================

-- =======  UP  ========

-- ---------------------------------------------
-- 1) Tabela de lotes de upload (1 linha por upload = 1 versão)
-- ---------------------------------------------
CREATE TABLE IF NOT EXISTS embaplan_upload_batch (
  id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id        UUID,
  rotulo         TEXT,
  arquivo_nome   TEXT,
  total_anuncios INTEGER NOT NULL DEFAULT 0,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ---------------------------------------------
-- 2) Tabela de snapshots por anúncio (append-only)
-- ---------------------------------------------
CREATE TABLE IF NOT EXISTS embaplan_analysis_snapshot (
  id                 BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  batch_id           BIGINT NOT NULL REFERENCES embaplan_upload_batch (id) ON DELETE CASCADE,
  loja               TEXT,
  produto            TEXT,
  anuncio_indice     TEXT NOT NULL,
  titulo             TEXT,
  status             TEXT,
  saude              NUMERIC(4,1),
  vendas             NUMERIC,
  receita            NUMERIC,
  lucro              NUMERIC,
  investimento_ads   NUMERIC,
  acos               NUMERIC,
  ctr                NUMERIC,
  conversao          NUMERIC,
  roas               NUMERIC,
  roi                NUMERIC,
  margem_liquida     NUMERIC,
  ticket_medio       NUMERIC,
  metrics_jsonb      JSONB,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ---------------------------------------------
-- 3) Índices (timeline + "último por anúncio")
-- ---------------------------------------------
CREATE INDEX IF NOT EXISTS idx_snapshot_serie
  ON embaplan_analysis_snapshot (loja, produto, anuncio_indice, batch_id);

CREATE INDEX IF NOT EXISTS idx_snapshot_indice_data
  ON embaplan_analysis_snapshot (anuncio_indice, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_snapshot_batch
  ON embaplan_analysis_snapshot (batch_id);

-- =============================================
-- 4) RPC: criar um batch e retornar o ID
--    Chamado pelo fluxo de upload (n8n) logo após
--    atualizar a planilha no Drive.
-- =============================================
CREATE OR REPLACE FUNCTION sameka_embaplan_create_batch(
  p_user_id      UUID DEFAULT NULL,
  p_rotulo       TEXT DEFAULT NULL,
  p_arquivo_nome TEXT DEFAULT NULL
)
RETURNS BIGINT
SECURITY DEFINER
SET search_path = public
LANGUAGE plpgsql
AS $$
DECLARE
  _batch_id BIGINT;
BEGIN
  INSERT INTO embaplan_upload_batch (user_id, rotulo, arquivo_nome)
  VALUES (p_user_id, NULLIF(TRIM(p_rotulo), ''), p_arquivo_nome)
  RETURNING id INTO _batch_id;

  RETURN _batch_id;
END;
$$;

-- =============================================
-- 5) RPC: gravar snapshots em lote (bulk insert)
--    p_rows = array JSON, um objeto por anúncio, ex.:
--    [{ "loja":"Loja 2", "produto":"Base A4", "anuncio_indice":"L2#47",
--       "titulo":"...", "status":"🚀 Escalável", "saude":9.2,
--       "vendas":575, "receita":18534.15, "lucro":7400.10,
--       "investimento_ads":1268.6, "acos":6.85, "ctr":1.67,
--       "conversao":6.3, "roas":14.6, "roi":1361.0,
--       "margem_liquida":39.9, "ticket_medio":32.2,
--       "metrics": { ...objeto _metricas completo... } }, ...]
-- =============================================
CREATE OR REPLACE FUNCTION sameka_embaplan_insert_snapshots(
  p_batch_id BIGINT,
  p_rows     JSONB
)
RETURNS INTEGER
SECURITY DEFINER
SET search_path = public
LANGUAGE plpgsql
AS $$
DECLARE
  _count INTEGER;
BEGIN
  IF p_rows IS NULL OR jsonb_typeof(p_rows) <> 'array' THEN
    RAISE EXCEPTION 'p_rows deve ser um array JSON de anúncios.';
  END IF;

  INSERT INTO embaplan_analysis_snapshot (
    batch_id, loja, produto, anuncio_indice, titulo, status, saude,
    vendas, receita, lucro, investimento_ads, acos, ctr, conversao,
    roas, roi, margem_liquida, ticket_medio, metrics_jsonb
  )
  SELECT
    p_batch_id,
    r->>'loja',
    r->>'produto',
    COALESCE(r->>'anuncio_indice', r->>'indice'),
    r->>'titulo',
    r->>'status',
    NULLIF(r->>'saude', '')::NUMERIC,
    NULLIF(r->>'vendas', '')::NUMERIC,
    NULLIF(r->>'receita', '')::NUMERIC,
    NULLIF(r->>'lucro', '')::NUMERIC,
    NULLIF(r->>'investimento_ads', '')::NUMERIC,
    NULLIF(r->>'acos', '')::NUMERIC,
    NULLIF(r->>'ctr', '')::NUMERIC,
    NULLIF(r->>'conversao', '')::NUMERIC,
    NULLIF(r->>'roas', '')::NUMERIC,
    NULLIF(r->>'roi', '')::NUMERIC,
    NULLIF(r->>'margem_liquida', '')::NUMERIC,
    NULLIF(r->>'ticket_medio', '')::NUMERIC,
    COALESCE(r->'metrics', r)
  FROM jsonb_array_elements(p_rows) AS r
  WHERE COALESCE(r->>'anuncio_indice', r->>'indice') IS NOT NULL;

  GET DIAGNOSTICS _count = ROW_COUNT;

  UPDATE embaplan_upload_batch
  SET total_anuncios = _count
  WHERE id = p_batch_id;

  RETURN _count;
END;
$$;

-- =============================================
-- 6) RPC: timeline de um anúncio (série temporal)
--    Retorna 1 ponto por batch, em ordem cronológica,
--    com o delta da métrica de saúde e lucro vs. ponto anterior.
-- =============================================
CREATE OR REPLACE FUNCTION sameka_embaplan_ad_timeline(
  p_anuncio_indice TEXT,
  p_limit          INTEGER DEFAULT 24
)
RETURNS TABLE(
  batch_id         BIGINT,
  rotulo           TEXT,
  data_upload      TIMESTAMPTZ,
  versao           BIGINT,
  loja             TEXT,
  produto          TEXT,
  titulo           TEXT,
  status           TEXT,
  saude            NUMERIC,
  acos             NUMERIC,
  roas             NUMERIC,
  conversao        NUMERIC,
  ctr              NUMERIC,
  lucro            NUMERIC,
  receita          NUMERIC,
  vendas           NUMERIC,
  ticket_medio     NUMERIC,
  delta_saude      NUMERIC,
  delta_lucro      NUMERIC,
  delta_acos       NUMERIC,
  tendencia        TEXT
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
      b.created_at AS data_upload,
      ROW_NUMBER() OVER (ORDER BY b.created_at) AS versao,
      s.loja, s.produto, s.titulo, s.status,
      s.saude, s.acos, s.roas, s.conversao, s.ctr,
      s.lucro, s.receita, s.vendas, s.ticket_medio,
      LAG(s.saude) OVER (ORDER BY b.created_at) AS prev_saude,
      LAG(s.lucro) OVER (ORDER BY b.created_at) AS prev_lucro,
      LAG(s.acos)  OVER (ORDER BY b.created_at) AS prev_acos
    FROM embaplan_analysis_snapshot s
    JOIN embaplan_upload_batch b ON b.id = s.batch_id
    WHERE s.anuncio_indice = p_anuncio_indice
  )
  SELECT
    batch_id, rotulo, data_upload, versao,
    loja, produto, titulo, status,
    saude, acos, roas, conversao, ctr,
    lucro, receita, vendas, ticket_medio,
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
  ORDER BY data_upload
  LIMIT p_limit;
$$;

-- =============================================
-- 7) RPC: estado atual de todos os anúncios (último batch)
--    com a tendência vs. o batch imediatamente anterior.
--    Base para o Dashboard (Épico 3).
-- =============================================
CREATE OR REPLACE FUNCTION sameka_embaplan_latest_overview(
  p_loja TEXT DEFAULT NULL
)
RETURNS TABLE(
  anuncio_indice  TEXT,
  loja            TEXT,
  produto         TEXT,
  titulo          TEXT,
  status          TEXT,
  saude           NUMERIC,
  acos            NUMERIC,
  roas            NUMERIC,
  lucro           NUMERIC,
  receita         NUMERIC,
  ticket_medio    NUMERIC,
  delta_saude     NUMERIC,
  delta_lucro     NUMERIC,
  delta_acos      NUMERIC,
  tendencia       TEXT
)
SECURITY DEFINER
SET search_path = public
LANGUAGE sql
STABLE
AS $$
  WITH ranked AS (
    SELECT
      s.*,
      b.created_at AS b_created,
      ROW_NUMBER() OVER (
        PARTITION BY s.anuncio_indice ORDER BY b.created_at DESC
      ) AS rn,
      LEAD(s.saude) OVER (
        PARTITION BY s.anuncio_indice ORDER BY b.created_at DESC
      ) AS prev_saude,
      LEAD(s.lucro) OVER (
        PARTITION BY s.anuncio_indice ORDER BY b.created_at DESC
      ) AS prev_lucro,
      LEAD(s.acos) OVER (
        PARTITION BY s.anuncio_indice ORDER BY b.created_at DESC
      ) AS prev_acos
    FROM embaplan_analysis_snapshot s
    JOIN embaplan_upload_batch b ON b.id = s.batch_id
    WHERE p_loja IS NULL OR s.loja = p_loja
  )
  SELECT
    anuncio_indice, loja, produto, titulo, status,
    saude, acos, roas, lucro, receita, ticket_medio,
    (saude - prev_saude) AS delta_saude,
    (lucro - prev_lucro) AS delta_lucro,
    (acos  - prev_acos)  AS delta_acos,
    CASE
      WHEN prev_saude IS NULL THEN 'novo'
      WHEN (saude - prev_saude) >= 0.5 OR (lucro - prev_lucro) > 0 THEN 'evoluindo'
      WHEN (saude - prev_saude) <= -0.5 OR (lucro - prev_lucro) < 0 THEN 'piorando'
      ELSE 'estavel'
    END AS tendencia
  FROM ranked
  WHERE rn = 1
  ORDER BY receita DESC NULLS LAST;
$$;

-- ---------------------------------------------
-- 8) Permissões (n8n usa o papel de serviço; mantemos
--    authenticated para uso via PostgREST/RPC se preciso)
-- ---------------------------------------------
GRANT EXECUTE ON FUNCTION sameka_embaplan_create_batch(UUID, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION sameka_embaplan_insert_snapshots(BIGINT, JSONB) TO authenticated;
GRANT EXECUTE ON FUNCTION sameka_embaplan_ad_timeline(TEXT, INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION sameka_embaplan_latest_overview(TEXT) TO authenticated;

NOTIFY pgrst, 'reload schema';

-- =======  DOWN  ========
-- DROP FUNCTION IF EXISTS sameka_embaplan_latest_overview(TEXT);
-- DROP FUNCTION IF EXISTS sameka_embaplan_ad_timeline(TEXT, INTEGER);
-- DROP FUNCTION IF EXISTS sameka_embaplan_insert_snapshots(BIGINT, JSONB);
-- DROP FUNCTION IF EXISTS sameka_embaplan_create_batch(UUID, TEXT, TEXT);
-- DROP TABLE IF EXISTS embaplan_analysis_snapshot;
-- DROP TABLE IF EXISTS embaplan_upload_batch;
-- NOTIFY pgrst, 'reload schema';
