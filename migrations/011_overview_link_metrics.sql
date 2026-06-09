-- =============================================
-- Embaplan — 011: Link do anúncio + métricas extras
-- Enriquece o overview e a timeline com:
--   - link  (extraído do metrics_jsonb da planilha, se existir)
--   - vendas, conversao, ctr, investimento_ads, ticket_medio
-- para o Dashboard mostrar cartões mais completos e o
-- modal de detalhe exibir todas as métricas + abrir o anúncio.
-- Run AFTER 010_agent_recommendations.sql
-- =============================================

-- =======  UP  ========

-- Helper imutável para puxar o 1º valor não-nulo dentre as
-- chaves de link mais comuns que podem vir da planilha.
CREATE OR REPLACE FUNCTION sameka_embaplan_extract_link(p_metrics JSONB)
RETURNS TEXT
IMMUTABLE
LANGUAGE sql
AS $$
  SELECT NULLIF(TRIM(COALESCE(
    p_metrics->>'Link do Shopee',
    p_metrics->>'link_shopee',
    p_metrics->>'link',
    p_metrics->>'url',
    p_metrics->>'permalink',
    p_metrics->>'anuncio_url',
    p_metrics->>'link_anuncio',
    p_metrics->>'url_anuncio',
    p_metrics->>'Link',
    p_metrics->>'URL'
  )), '');
$$;

-- ---------------------------------------------
-- Overview enriquecido (precisa DROP por mudar o RETURNS TABLE)
-- ---------------------------------------------
DROP FUNCTION IF EXISTS sameka_embaplan_latest_overview(TEXT);

CREATE OR REPLACE FUNCTION sameka_embaplan_latest_overview(
  p_loja TEXT DEFAULT NULL
)
RETURNS TABLE(
  anuncio_indice    TEXT,
  loja              TEXT,
  produto           TEXT,
  titulo            TEXT,
  status            TEXT,
  link              TEXT,
  saude             NUMERIC,
  acos              NUMERIC,
  roas              NUMERIC,
  lucro             NUMERIC,
  receita           NUMERIC,
  vendas            NUMERIC,
  conversao         NUMERIC,
  ctr               NUMERIC,
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
    sameka_embaplan_extract_link(metrics_jsonb) AS link,
    saude, acos, roas, lucro, receita, vendas, conversao, ctr,
    investimento_ads, ticket_medio,
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
-- Timeline enriquecida com link e investimento_ads
-- ---------------------------------------------
DROP FUNCTION IF EXISTS sameka_embaplan_ad_timeline(TEXT, INTEGER);

CREATE OR REPLACE FUNCTION sameka_embaplan_ad_timeline(
  p_anuncio_indice TEXT,
  p_limit          INTEGER DEFAULT 24
)
RETURNS TABLE(
  batch_id          BIGINT,
  rotulo            TEXT,
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
      b.created_at AS data_upload,
      ROW_NUMBER() OVER (ORDER BY b.created_at) AS versao,
      s.loja, s.produto, s.titulo, s.status,
      sameka_embaplan_extract_link(s.metrics_jsonb) AS link,
      s.saude, s.acos, s.roas, s.conversao, s.ctr,
      s.lucro, s.receita, s.vendas, s.investimento_ads, s.ticket_medio,
      LAG(s.saude) OVER (ORDER BY b.created_at) AS prev_saude,
      LAG(s.lucro) OVER (ORDER BY b.created_at) AS prev_lucro,
      LAG(s.acos)  OVER (ORDER BY b.created_at) AS prev_acos
    FROM embaplan_analysis_snapshot s
    JOIN embaplan_upload_batch b ON b.id = s.batch_id
    WHERE s.anuncio_indice = p_anuncio_indice
  )
  SELECT
    batch_id, rotulo, data_upload, versao,
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
  ORDER BY data_upload
  LIMIT p_limit;
$$;

GRANT EXECUTE ON FUNCTION sameka_embaplan_extract_link(JSONB) TO authenticated;
GRANT EXECUTE ON FUNCTION sameka_embaplan_latest_overview(TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION sameka_embaplan_ad_timeline(TEXT, INTEGER) TO authenticated;

NOTIFY pgrst, 'reload schema';

-- =======  DOWN  ========
-- DROP FUNCTION IF EXISTS sameka_embaplan_extract_link(JSONB);
-- (re-aplicar 008_analysis_snapshots.sql para restaurar as
--  assinaturas originais de overview/timeline)
