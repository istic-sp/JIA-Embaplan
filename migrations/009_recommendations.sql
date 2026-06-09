-- =============================================
-- Embaplan — 009: Recomendações do agente + eficácia
-- Cada recomendação do agente é registrada e ancorada ao
-- batch (versão) em que foi feita. O usuário marca o status
-- (feito/descartado/pendente) e pode registrar uma alteração
-- própria ("outros"). Na versão seguinte, comparamos a métrica
-- alvo para dizer se a sugestão deu certo (Épicos 1.C e 2).
-- Run AFTER 008_analysis_snapshots.sql
-- =============================================

-- =======  UP  ========

-- ---------------------------------------------
-- 1) Enum de status da recomendação
-- ---------------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'embaplan_rec_status') THEN
    CREATE TYPE embaplan_rec_status AS ENUM ('pendente', 'feito', 'descartado');
  END IF;
END$$;

-- ---------------------------------------------
-- 2) Tabela de recomendações
--    origem='agente' (sugerida pelo agente) ou 'usuario' (campo "Outros")
--    metrica_alvo: qual métrica a recomendação pretende melhorar (ex.: 'acos')
--    resultado: avaliação automática na versão seguinte
-- ---------------------------------------------
CREATE TABLE IF NOT EXISTS embaplan_recommendation (
  id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  batch_id        BIGINT REFERENCES embaplan_upload_batch (id) ON DELETE SET NULL,
  snapshot_id     BIGINT REFERENCES embaplan_analysis_snapshot (id) ON DELETE SET NULL,
  user_id         UUID,
  loja            TEXT,
  produto         TEXT,
  anuncio_indice  TEXT NOT NULL,
  origem          TEXT NOT NULL DEFAULT 'agente',  -- 'agente' | 'usuario'
  texto           TEXT NOT NULL,
  prioridade      INTEGER DEFAULT 0,
  metrica_alvo    TEXT,                            -- 'acos' | 'roas' | 'conversao' | 'lucro' | 'saude' | ...
  status          embaplan_rec_status NOT NULL DEFAULT 'pendente',
  nota_usuario    TEXT,
  resultado       TEXT,                            -- 'funcionou' | 'neutro' | 'piorou' | NULL
  resultado_batch_id BIGINT REFERENCES embaplan_upload_batch (id) ON DELETE SET NULL,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_rec_anuncio
  ON embaplan_recommendation (anuncio_indice, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_rec_batch
  ON embaplan_recommendation (batch_id);
CREATE INDEX IF NOT EXISTS idx_rec_status
  ON embaplan_recommendation (status);

-- ---------------------------------------------
-- 3) Trigger: manter updated_at
-- ---------------------------------------------
CREATE OR REPLACE FUNCTION trg_embaplan_rec_touch()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at := NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_rec_touch ON embaplan_recommendation;
CREATE TRIGGER trg_rec_touch
  BEFORE UPDATE ON embaplan_recommendation
  FOR EACH ROW
  EXECUTE FUNCTION trg_embaplan_rec_touch();

-- =============================================
-- 4) RPC: registrar recomendações em lote (vindas do agente)
--    p_rows = [{ "anuncio_indice":"L2#47", "loja":"Loja 2",
--                "produto":"Base A4", "texto":"Reduzir lance em 15%",
--                "prioridade":1, "metrica_alvo":"acos" }, ...]
-- =============================================
CREATE OR REPLACE FUNCTION sameka_embaplan_add_recommendations(
  p_batch_id BIGINT,
  p_user_id  UUID,
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
    RAISE EXCEPTION 'p_rows deve ser um array JSON de recomendações.';
  END IF;

  INSERT INTO embaplan_recommendation (
    batch_id, snapshot_id, user_id, loja, produto, anuncio_indice,
    origem, texto, prioridade, metrica_alvo
  )
  SELECT
    p_batch_id,
    (SELECT s.id FROM embaplan_analysis_snapshot s
      WHERE s.batch_id = p_batch_id
        AND s.anuncio_indice = COALESCE(r->>'anuncio_indice', r->>'indice')
      LIMIT 1),
    p_user_id,
    r->>'loja',
    r->>'produto',
    COALESCE(r->>'anuncio_indice', r->>'indice'),
    COALESCE(r->>'origem', 'agente'),
    r->>'texto',
    COALESCE(NULLIF(r->>'prioridade', '')::INTEGER, 0),
    r->>'metrica_alvo'
  FROM jsonb_array_elements(p_rows) AS r
  WHERE COALESCE(r->>'texto', '') <> ''
    AND COALESCE(r->>'anuncio_indice', r->>'indice') IS NOT NULL;

  GET DIAGNOSTICS _count = ROW_COUNT;
  RETURN _count;
END;
$$;

-- =============================================
-- 5) RPC: atualizar status de uma recomendação (usuário no front)
--    Usado pelo webhook embaplan-recommendation-status (PATCH).
-- =============================================
CREATE OR REPLACE FUNCTION sameka_embaplan_set_recommendation_status(
  p_id      BIGINT,
  p_status  TEXT,
  p_nota    TEXT DEFAULT NULL
)
RETURNS VOID
SECURITY DEFINER
SET search_path = public
LANGUAGE plpgsql
AS $$
BEGIN
  IF p_status NOT IN ('pendente', 'feito', 'descartado') THEN
    RAISE EXCEPTION 'Status inválido: %. Use pendente|feito|descartado.', p_status;
  END IF;

  UPDATE embaplan_recommendation
  SET status = p_status::embaplan_rec_status,
      nota_usuario = COALESCE(p_nota, nota_usuario)
  WHERE id = p_id;
END;
$$;

-- =============================================
-- 6) RPC: registrar uma alteração própria do usuário ("Outros")
--    Já entra como origem='usuario' e status='feito'.
-- =============================================
CREATE OR REPLACE FUNCTION sameka_embaplan_add_user_change(
  p_user_id        UUID,
  p_anuncio_indice TEXT,
  p_texto          TEXT,
  p_loja           TEXT DEFAULT NULL,
  p_produto        TEXT DEFAULT NULL,
  p_metrica_alvo   TEXT DEFAULT NULL
)
RETURNS BIGINT
SECURITY DEFINER
SET search_path = public
LANGUAGE plpgsql
AS $$
DECLARE
  _id       BIGINT;
  _batch_id BIGINT;
BEGIN
  -- ancora no batch mais recente do anúncio
  SELECT s.batch_id INTO _batch_id
  FROM embaplan_analysis_snapshot s
  WHERE s.anuncio_indice = p_anuncio_indice
  ORDER BY s.created_at DESC
  LIMIT 1;

  INSERT INTO embaplan_recommendation (
    batch_id, user_id, loja, produto, anuncio_indice,
    origem, texto, metrica_alvo, status
  )
  VALUES (
    _batch_id, p_user_id, p_loja, p_produto, p_anuncio_indice,
    'usuario', p_texto, p_metrica_alvo, 'feito'
  )
  RETURNING id INTO _id;

  RETURN _id;
END;
$$;

-- =============================================
-- 7) RPC: avaliar eficácia das recomendações de um batch
--    Compara a métrica_alvo da recomendação (no batch de origem)
--    com o valor no batch_alvo (geralmente o batch novo).
--    Marca resultado: funcionou | neutro | piorou.
--    Chamado pelo fluxo de upload logo após gravar os snapshots
--    do novo batch (passando o batch ANTERIOR como p_batch_origem).
-- =============================================
CREATE OR REPLACE FUNCTION sameka_embaplan_evaluate_recommendations(
  p_batch_origem BIGINT,
  p_batch_alvo   BIGINT
)
RETURNS INTEGER
SECURITY DEFINER
SET search_path = public
LANGUAGE plpgsql
AS $$
DECLARE
  _count INTEGER := 0;
  _rec   RECORD;
  _old   NUMERIC;
  _new   NUMERIC;
  _melhor_quando_sobe BOOLEAN;
  _resultado TEXT;
BEGIN
  FOR _rec IN
    SELECT * FROM embaplan_recommendation
    WHERE batch_id = p_batch_origem
      AND resultado IS NULL
      AND status = 'feito'
      AND metrica_alvo IS NOT NULL
  LOOP
    -- valor antigo (batch origem) e novo (batch alvo) da métrica alvo
    SELECT CASE _rec.metrica_alvo
             WHEN 'acos' THEN acos WHEN 'roas' THEN roas
             WHEN 'conversao' THEN conversao WHEN 'ctr' THEN ctr
             WHEN 'lucro' THEN lucro WHEN 'saude' THEN saude
             WHEN 'receita' THEN receita WHEN 'ticket_medio' THEN ticket_medio
             ELSE NULL END
      INTO _old
      FROM embaplan_analysis_snapshot
     WHERE batch_id = p_batch_origem AND anuncio_indice = _rec.anuncio_indice
     LIMIT 1;

    SELECT CASE _rec.metrica_alvo
             WHEN 'acos' THEN acos WHEN 'roas' THEN roas
             WHEN 'conversao' THEN conversao WHEN 'ctr' THEN ctr
             WHEN 'lucro' THEN lucro WHEN 'saude' THEN saude
             WHEN 'receita' THEN receita WHEN 'ticket_medio' THEN ticket_medio
             ELSE NULL END
      INTO _new
      FROM embaplan_analysis_snapshot
     WHERE batch_id = p_batch_alvo AND anuncio_indice = _rec.anuncio_indice
     LIMIT 1;

    IF _old IS NULL OR _new IS NULL THEN
      CONTINUE;
    END IF;

    -- ACOS é a única métrica em que MENOR é melhor
    _melhor_quando_sobe := (_rec.metrica_alvo <> 'acos');

    IF _new = _old THEN
      _resultado := 'neutro';
    ELSIF (_new > _old) = _melhor_quando_sobe THEN
      _resultado := 'funcionou';
    ELSE
      _resultado := 'piorou';
    END IF;

    UPDATE embaplan_recommendation
    SET resultado = _resultado,
        resultado_batch_id = p_batch_alvo
    WHERE id = _rec.id;

    _count := _count + 1;
  END LOOP;

  RETURN _count;
END;
$$;

-- =============================================
-- 8) RPC: listar recomendações de um anúncio (timeline de ações)
-- =============================================
CREATE OR REPLACE FUNCTION sameka_embaplan_recommendations_for_ad(
  p_anuncio_indice TEXT
)
RETURNS TABLE(
  id             BIGINT,
  batch_id       BIGINT,
  origem         TEXT,
  texto          TEXT,
  prioridade     INTEGER,
  metrica_alvo   TEXT,
  status         TEXT,
  nota_usuario   TEXT,
  resultado      TEXT,
  created_at     TIMESTAMPTZ,
  updated_at     TIMESTAMPTZ
)
SECURITY DEFINER
SET search_path = public
LANGUAGE sql
STABLE
AS $$
  SELECT
    id, batch_id, origem, texto, prioridade, metrica_alvo,
    status::TEXT, nota_usuario, resultado, created_at, updated_at
  FROM embaplan_recommendation
  WHERE anuncio_indice = p_anuncio_indice
  ORDER BY created_at DESC, prioridade ASC;
$$;

-- ---------------------------------------------
-- 9) Permissões
-- ---------------------------------------------
GRANT EXECUTE ON FUNCTION sameka_embaplan_add_recommendations(BIGINT, UUID, JSONB) TO authenticated;
GRANT EXECUTE ON FUNCTION sameka_embaplan_set_recommendation_status(BIGINT, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION sameka_embaplan_add_user_change(UUID, TEXT, TEXT, TEXT, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION sameka_embaplan_evaluate_recommendations(BIGINT, BIGINT) TO authenticated;
GRANT EXECUTE ON FUNCTION sameka_embaplan_recommendations_for_ad(TEXT) TO authenticated;

NOTIFY pgrst, 'reload schema';

-- =======  DOWN  ========
-- DROP FUNCTION IF EXISTS sameka_embaplan_recommendations_for_ad(TEXT);
-- DROP FUNCTION IF EXISTS sameka_embaplan_evaluate_recommendations(BIGINT, BIGINT);
-- DROP FUNCTION IF EXISTS sameka_embaplan_add_user_change(UUID, TEXT, TEXT, TEXT, TEXT, TEXT);
-- DROP FUNCTION IF EXISTS sameka_embaplan_set_recommendation_status(BIGINT, TEXT, TEXT);
-- DROP FUNCTION IF EXISTS sameka_embaplan_add_recommendations(BIGINT, UUID, JSONB);
-- DROP TRIGGER IF EXISTS trg_rec_touch ON embaplan_recommendation;
-- DROP FUNCTION IF EXISTS trg_embaplan_rec_touch();
-- DROP TABLE IF EXISTS embaplan_recommendation;
-- DROP TYPE IF EXISTS embaplan_rec_status;
-- NOTIFY pgrst, 'reload schema';
