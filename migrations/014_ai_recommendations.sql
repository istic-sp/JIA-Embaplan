-- =============================================
-- Embaplan — 014: Recomendações geradas por IA (dedicada)
-- Suporte ao novo workflow `Embaplan-Recomendacoes-IA`:
--   • Função de CONTEXTO: entrega para a IA o estado atual do anúncio,
--     a linha do tempo recente e as recomendações já existentes — tudo
--     em JSON, para a IA gerar sugestões fundamentadas (sem alucinar).
--   • Função de GESTÃO: apagar uma recomendação (limpeza manual no front).
-- As recomendações geradas continuam sendo gravadas pela função já
-- existente `sameka_embaplan_add_agent_recommendations` (migration 010),
-- com origem='agente'.
-- Run AFTER 010_agent_recommendations.sql
-- =============================================

-- =======  UP  ========

-- ---------------------------------------------
-- 1) CONTEXTO PARA A IA
--    Devolve um único JSON com:
--      • atual: métricas do snapshot mais recente do anúncio
--      • historico: até 6 snapshots (mais antigo -> mais novo) para a IA
--        enxergar tendência (melhorou/piorou)
--      • recomendacoes_existentes: o que já foi sugerido/feito, para a IA
--        NÃO repetir e poder evoluir as orientações
-- ---------------------------------------------
CREATE OR REPLACE FUNCTION sameka_embaplan_ad_context_for_ai(
  p_anuncio_indice TEXT
)
RETURNS JSONB
SECURITY DEFINER
SET search_path = public
LANGUAGE sql
STABLE
AS $$
  WITH atual AS (
    SELECT *
    FROM embaplan_analysis_snapshot
    WHERE anuncio_indice = p_anuncio_indice
    ORDER BY created_at DESC
    LIMIT 1
  ),
  hist AS (
    SELECT *
    FROM (
      SELECT *
      FROM embaplan_analysis_snapshot
      WHERE anuncio_indice = p_anuncio_indice
      ORDER BY created_at DESC
      LIMIT 6
    ) h
    ORDER BY created_at ASC
  )
  SELECT jsonb_build_object(
    'anuncio_indice', p_anuncio_indice,
    'encontrado', (SELECT COUNT(*) FROM atual) > 0,
    'atual', (
      SELECT jsonb_build_object(
        'loja', a.loja,
        'produto', a.produto,
        'titulo', a.titulo,
        'status', a.status,
        'saude', a.saude,
        'vendas', a.vendas,
        'receita', a.receita,
        'lucro', a.lucro,
        'investimento_ads', a.investimento_ads,
        'acos', a.acos,
        'ctr', a.ctr,
        'conversao', a.conversao,
        'roas', a.roas,
        'roi', a.roi,
        'margem_liquida', a.margem_liquida,
        'ticket_medio', a.ticket_medio,
        'link', a.metrics_jsonb->>'link',
        'batch_id', a.batch_id,
        'data', a.created_at
      )
      FROM atual a
    ),
    'historico', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'data', h.created_at,
        'saude', h.saude,
        'acos', h.acos,
        'roas', h.roas,
        'conversao', h.conversao,
        'ctr', h.ctr,
        'lucro', h.lucro,
        'receita', h.receita,
        'status', h.status
      ))
      FROM hist h
    ), '[]'::jsonb),
    'recomendacoes_existentes', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'texto', r.texto,
        'origem', r.origem,
        'status', r.status,
        'metrica_alvo', r.metrica_alvo,
        'resultado', r.resultado
      ) ORDER BY r.created_at DESC)
      FROM embaplan_recommendation r
      WHERE r.anuncio_indice = p_anuncio_indice
    ), '[]'::jsonb)
  );
$$;

GRANT EXECUTE ON FUNCTION sameka_embaplan_ad_context_for_ai(TEXT) TO authenticated;

-- ---------------------------------------------
-- 2) GESTÃO: apagar uma recomendação
-- ---------------------------------------------
CREATE OR REPLACE FUNCTION sameka_embaplan_delete_recommendation(
  p_id BIGINT
)
RETURNS VOID
SECURITY DEFINER
SET search_path = public
LANGUAGE plpgsql
AS $$
BEGIN
  DELETE FROM embaplan_recommendation WHERE id = p_id;
END;
$$;

GRANT EXECUTE ON FUNCTION sameka_embaplan_delete_recommendation(BIGINT) TO authenticated;

NOTIFY pgrst, 'reload schema';

-- =======  DOWN  ========
-- DROP FUNCTION IF EXISTS sameka_embaplan_ad_context_for_ai(TEXT);
-- DROP FUNCTION IF EXISTS sameka_embaplan_delete_recommendation(BIGINT);
-- NOTIFY pgrst, 'reload schema';
