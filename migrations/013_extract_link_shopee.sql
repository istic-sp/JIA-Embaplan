-- =============================================
-- Embaplan — 013: corrige extração do "Link do Shopee"
-- O sub-fluxo gera o campo "Link do Shopee" no nível do anúncio
-- (mesma lógica usada pelo chat). A função de extração antiga não
-- procurava por essa chave, então o Dashboard/modal mostrava o
-- anúncio sem link ("Abrir anúncio" não direcionava).
-- Este patch torna a extração robusta para quem já rodou a 011.
-- Run AFTER 011_overview_link_metrics.sql
-- =============================================

-- =======  UP  ========

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

NOTIFY pgrst, 'reload schema';

-- =======  DOWN  ========
-- CREATE OR REPLACE FUNCTION sameka_embaplan_extract_link(p_metrics JSONB)
-- RETURNS TEXT IMMUTABLE LANGUAGE sql AS $$
--   SELECT NULLIF(TRIM(COALESCE(
--     p_metrics->>'link', p_metrics->>'url', p_metrics->>'permalink',
--     p_metrics->>'anuncio_url', p_metrics->>'link_anuncio',
--     p_metrics->>'url_anuncio', p_metrics->>'Link', p_metrics->>'URL'
--   )), '');
-- $$;
-- NOTIFY pgrst, 'reload schema';
