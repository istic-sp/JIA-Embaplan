-- =============================================
-- Embaplan — 010: Registrar recomendações do agente (auto)
-- RPC que recebe as ações corretivas extraídas da resposta do
-- agente e as registra como recomendações, resolvendo sozinha o
-- batch (versão) mais recente de cada anúncio. Inclui dedup para
-- não duplicar a mesma recomendação ao re-renderizar o histórico.
-- Run AFTER 009_recommendations.sql
-- =============================================

-- =======  UP  ========

-- p_rows = [{ "anuncio_indice":"L2#47", "loja":"Loja 2", "produto":"Base A4",
--             "texto":"Reduzir lance em 15%", "prioridade":1,
--             "metrica_alvo":"acos" }, ...]
CREATE OR REPLACE FUNCTION sameka_embaplan_add_agent_recommendations(
  p_user_id UUID,
  p_rows    JSONB
)
RETURNS INTEGER
SECURITY DEFINER
SET search_path = public
LANGUAGE plpgsql
AS $$
DECLARE
  _count   INTEGER := 0;
  _r       JSONB;
  _indice  TEXT;
  _texto   TEXT;
  _batch   BIGINT;
  _snap    BIGINT;
BEGIN
  IF p_rows IS NULL OR jsonb_typeof(p_rows) <> 'array' THEN
    RAISE EXCEPTION 'p_rows deve ser um array JSON.';
  END IF;

  FOR _r IN SELECT * FROM jsonb_array_elements(p_rows)
  LOOP
    _indice := COALESCE(_r->>'anuncio_indice', _r->>'indice');
    _texto  := _r->>'texto';
    CONTINUE WHEN _indice IS NULL OR COALESCE(_texto, '') = '';

    -- batch + snapshot mais recentes deste anúncio
    SELECT s.batch_id, s.id INTO _batch, _snap
    FROM embaplan_analysis_snapshot s
    WHERE s.anuncio_indice = _indice
    ORDER BY s.created_at DESC
    LIMIT 1;

    -- dedup: já existe a MESMA recomendação para este anúncio neste batch?
    IF EXISTS (
      SELECT 1 FROM embaplan_recommendation
      WHERE anuncio_indice = _indice
        AND texto = _texto
        AND origem = 'agente'
        AND COALESCE(batch_id, -1) = COALESCE(_batch, -1)
    ) THEN
      CONTINUE;
    END IF;

    INSERT INTO embaplan_recommendation (
      batch_id, snapshot_id, user_id, loja, produto, anuncio_indice,
      origem, texto, prioridade, metrica_alvo
    )
    VALUES (
      _batch, _snap, p_user_id, _r->>'loja', _r->>'produto', _indice,
      'agente', _texto,
      COALESCE(NULLIF(_r->>'prioridade', '')::INTEGER, 0),
      _r->>'metrica_alvo'
    );

    _count := _count + 1;
  END LOOP;

  RETURN _count;
END;
$$;

GRANT EXECUTE ON FUNCTION sameka_embaplan_add_agent_recommendations(UUID, JSONB) TO authenticated;

NOTIFY pgrst, 'reload schema';

-- =======  DOWN  ========
-- DROP FUNCTION IF EXISTS sameka_embaplan_add_agent_recommendations(UUID, JSONB);
-- NOTIFY pgrst, 'reload schema';
