# Upload em múltiplas datas — Tasks

**Design:** `.specs/features/upload-multidatas/design.md`
**Spec:** `.specs/features/upload-multidatas/spec.md`
**Status:** Draft

> Tasks atômicas e auto-contidas, pensadas para modelos pequenos. Cada task tem caminho exato, código/SQL pronto e verificação manual (o projeto não tem testes automatizados — ver `.specs/codebase/TESTING.md`).

---

## Execution Plan

### Phase 1: Banco (Sequential)

```
T1 → T2
```

### Phase 2: Workflows n8n (Sequential — dependem do banco corrigido)

```
T2 → T3 → T4
```

### Phase 3: Frontend (Parallel após T2)

```
T2 → T5 [P]
```

### Phase 4: Verificação (Sequential)

```
T1, T2, T3, T4, T5 → T6
```

---

## Parallel Execution Map

```
Phase 1 (Sequential):  T1 ──→ T2
Phase 2 (Sequential):  T2 ──→ T3 ──→ T4
Phase 3 (Parallel):    T2 ──→ T5 [P]
Phase 4 (Sequential):  (T3,T4,T5) ──→ T6
```

> **Nota de paralelismo:** `[P]` só em T5 (frontend, arquivo diferente). T3 e T4 editam workflows distintos mas têm dependência lógica de fluxo, portanto sequenciais. Sem testes automatizados → não há gate de testes paralelos.

---

## Task Breakdown

### T1: Criar migration 020 — `embaplan_create_month_batch` robusto

**What**: Criar a migration que reescreve a RPC para (a) falhar quando `periodo` ausente em vez de assumir hoje, e (b) escopar o replace por `periodo` + `user_id`.
**Where**: `migrations/020_fix_create_month_batch.sql` (criar novo arquivo)
**Depends on**: None
**Reuses**: corpo da função em `migrations/019_chronology_by_period.sql`
**Requirement**: UPDATE-02, UPDATE-03, FLOW-03

**Tools**:

- MCP: `filesystem` (criar arquivo)
- Skill: NONE

**Conteúdo exato do arquivo** (copiar como está):

```sql
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

-- =======  DOWN  ========
-- (reaplicar 019_chronology_by_period.sql para reverter)
```

**Done when**:

- [ ] Arquivo `migrations/020_fix_create_month_batch.sql` criado com o conteúdo acima
- [ ] A função ainda tem a MESMA assinatura `(UUID, TEXT, TEXT, TEXT, BOOLEAN)`
- [ ] Não usa `NOW()` para preencher `periodo`

**Tests**: none (sem framework; validação em T6)
**Gate**: none (revisão manual do SQL)

---

### T2: Adicionar unicidade de `periodo` na migration 020

**What**: Acrescentar ao final de `020_fix_create_month_batch.sql` a consolidação de duplicatas e o índice único parcial por data.
**Where**: `migrations/020_fix_create_month_batch.sql` (editar — anexar antes do bloco DOWN)
**Depends on**: T1
**Reuses**: `idx_batch_periodo` de `migrations/012_incremental_monthly.sql` (substituído por índice único)
**Requirement**: UNIQ-01

**Tools**:

- MCP: `filesystem`
- Skill: NONE

**Trecho a inserir** (logo após `NOTIFY pgrst, 'reload schema';` da T1, antes do bloco DOWN):

```sql
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
```

**Done when**:

- [ ] Trecho anexado ao arquivo `020`
- [ ] `DELETE` de consolidação preserva o batch de maior `id` por data
- [ ] Índice `uniq_batch_periodo_user` criado como UNIQUE e parcial (`WHERE periodo IS NOT NULL`)

**Tests**: none
**Gate**: none (revisão manual do SQL)

**Commit**: `fix(db): create_month_batch robusto + unicidade por periodo`

---

### T3: Corrigir perda de `periodo` no workflow de upload

**What**: No workflow de upload, garantir que `periodo`/`rotulo` cheguem ao nó de captura sem virar `null`; falhar explicitamente se ausentes.
**Where**: `workspaces/Embaplan-Upload-Planilha-Anuncios.json` (editar o nó **Preparar Captura**)
**Depends on**: T2
**Reuses**: nó `Validar Arquivo` (já extrai `periodo`/`rotulo`), nó `Capturar Snapshot`
**Requirement**: FLOW-01

**Tools**:

- MCP: `filesystem`
- Skill: NONE

**Instruções precisas**:

1. Localizar no JSON o nó com `"name": "Preparar Captura"` e seu campo de código (`jsCode` / `functionCode`).
2. Substituir a leitura frágil por uma versão que valida a `periodo` e falha se ausente. O código deve ficar equivalente a:

```javascript
const meta = $("Validar Arquivo").first().json || {};
const sumario = $json; // saída do sub-fluxo de sumário
const fileName = meta.received_file || null;
const periodo = meta.periodo || null;
const rotulo = meta.rotulo || null;

// Falhar cedo: NUNCA seguir sem a data de referência.
if (!periodo) {
  throw new Error(
    "periodo ausente no upload — data de referência obrigatória.",
  );
}

return [
  {
    json: {
      _capturar: true,
      produtos: sumario.produtos,
      arquivo_nome: fileName,
      periodo: periodo,
      rotulo: rotulo,
      user_id: null,
    },
  },
];
```

3. Confirmar que o nó **Capturar Snapshot** (HTTP) já envia `periodo: $json.periodo` e `rotulo: $json.rotulo` no `jsonBody` (não alterar se já estiver assim).
4. Preservar a estrutura JSON do n8n (não quebrar `id`, `type`, `position`, conexões).

**Done when**:

- [ ] `Preparar Captura` lança erro quando `periodo` ausente
- [ ] `periodo` e `rotulo` continuam sendo enviados ao `embaplan-capture-snapshot`
- [ ] JSON do workflow continua válido (parseável) e os nós/conexões intactos

**Tests**: none (validação manual no n8n em T6)
**Gate**: none

**Commit**: `fix(n8n): nao perder periodo no fluxo de upload`

---

### T4: Validar `periodo` antes de criar o batch no workflow de snapshots

**What**: No workflow de snapshots, garantir que a chamada a `embaplan_create_month_batch` use a `periodo` real e não prossiga com `periodo` vazia.
**Where**: `workspaces/Embaplan-Historico-Snapshots.json` (nós **Flatten Snapshots** e **Create Batch (RPC)**)
**Depends on**: T3
**Reuses**: nó `Flatten Snapshots` (já lê `body.periodo`), RPC corrigida em T1
**Requirement**: FLOW-02, FLOW-03

**Tools**:

- MCP: `filesystem`
- Skill: NONE

**Instruções precisas**:

1. No nó **Flatten Snapshots**, após montar o objeto de saída, adicionar guarda:

```javascript
if (!output.periodo) {
  throw new Error(
    "periodo ausente na captura de snapshot — abortando para nao gravar na data errada.",
  );
}
```

(onde `output` é o objeto `{ SUPABASE_URL, periodo, rotulo, arquivo_nome, user_id, rows }` retornado). 2. No nó **Create Batch (RPC)**, confirmar que os parâmetros são exatamente:

```
[$json.user_id || null, $json.periodo, $json.rotulo || null, $json.arquivo_nome || null, true]
```

> Importante: usar `$json.periodo` (sem `|| null`) — a guarda do passo 1 já garante presença. `p_replace` permanece `true` (idempotência por data agora é segura graças a T1). 3. Não alterar o nó **Insert Snapshots (RPC)** (continua `embaplan_insert_snapshots($json.batch_id, rows)`). 4. Preservar a estrutura JSON do n8n.

**Done when**:

- [ ] `Flatten Snapshots` aborta se `periodo` ausente
- [ ] `Create Batch (RPC)` passa `$json.periodo` como `$2` (p_periodo)
- [ ] `p_replace` permanece `true`
- [ ] JSON do workflow válido e nós/conexões intactos

**Tests**: none
**Gate**: none

**Commit**: `fix(n8n): validar periodo antes de criar batch`

---

### T5: Endurecer validação de data no frontend [P]

**What**: No handler de upload do `front.html`, impedir envio sem `periodo` e exibir erros do backend de forma clara.
**Where**: `front.html` (handler `pendingAction === "uploadSheet"`, aprox. linhas 6840–6905)
**Depends on**: T2
**Reuses**: `setStatus`, modal de upload existente, `<input id="uploadPeriodo">`
**Requirement**: FLOW-03 (UX)

**Tools**:

- MCP: `filesystem`
- Skill: NONE

**Instruções precisas**:

1. Após ler `const periodo = periodoInput && periodoInput.value ? periodoInput.value : "";`, adicionar antes de `hideDeleteModal()`:

```javascript
if (!periodo) {
  setStatus("Selecione a data de referência antes de enviar.", "error");
  return; // não fecha o modal, não envia
}
```

2. No `catch (err)` do upload, manter a exibição da mensagem do backend (já existe `setStatus(`Falha ao atualizar planilha: ${err.message || err}`, "error")`) — garantir que o texto do erro HTTP seja propagado (o `throw new Error(txt || ...)` já faz isso).
3. Não alterar o restante do fluxo.

**Done when**:

- [ ] Enviar sem data exibe erro e não dispara o `fetch`
- [ ] Erro do backend aparece para o usuário via `setStatus`
- [ ] Nenhuma regressão visível no modal de upload

**Tests**: none (verificação manual no navegador em T6)
**Gate**: none

**Commit**: `fix(front): exigir data de referencia no upload`

---

### T6: Verificação manual (UAT) end-to-end

**What**: Roteiro de verificação manual cobrindo adicionar datas anteriores/posteriores, replace de mesma data e falha sem data.
**Where**: ambiente de teste (Supabase + n8n importados, `front.html` no navegador)
**Depends on**: T1, T2, T3, T4, T5
**Reuses**: planilhas de exemplo no repo (`*.xlsx`)
**Requirement**: UPDATE-01, UPDATE-02, UPDATE-03, FLOW-01, FLOW-02, FLOW-03, UNIQ-01

**Tools**:

- MCP: NONE
- Skill: NONE

**Passos**:

1. Aplicar `migrations/020_fix_create_month_batch.sql` no Supabase (SQL editor) sem erros.
2. Reimportar os dois workflows editados no n8n e ativá-los.
3. Estado inicial: garantir 2 batches (ex.: 2026-05-10 e 2026-06-10) via `SELECT id, periodo, rotulo FROM embaplan_upload_batch ORDER BY periodo;`.
4. Enviar planilha com data **anterior** (2026-04-10) → conferir 3 batches, ordenados 04→05→06, nenhum apagado.
5. Enviar planilha com data **posterior** (2026-07-10) → conferir 4 batches; dashboard mostra 07/2026 como atual.
6. Reenviar a **mesma data** (2026-07-10) → continua 4 batches (substituiu só esse dia); `SELECT COUNT(*) ... WHERE periodo='2026-07-10'` retorna 1.
7. Tentar enviar **sem data** (limpar o campo) → front bloqueia com erro; nenhum batch criado.
8. Conferir unicidade: `SELECT periodo, COUNT(*) FROM embaplan_upload_batch GROUP BY periodo HAVING COUNT(*)>1;` retorna 0 linhas.

**Done when**:

- [ ] Todos os 8 passos passam conforme descrito
- [ ] Nenhum batch de outra data é apagado ao adicionar nova data
- [ ] `periodo` no banco sempre igual à escolhida no front
- [ ] Resultados registrados em `SUMMARY.md` ou no STATE.md

**Tests**: none (UAT manual)
**Gate**: none

---

## Validation Tables (pré-aprovação)

### Check 1 — Granularidade

| Task | Deliverable único?           | Arquivo único?     | OK  |
| ---- | ---------------------------- | ------------------ | --- |
| T1   | RPC reescrita                | `020_*.sql`        | ✅  |
| T2   | Unicidade + consolidação     | `020_*.sql`        | ✅  |
| T3   | Nó `Preparar Captura`        | upload workflow    | ✅  |
| T4   | Nós `Flatten`/`Create Batch` | snapshots workflow | ✅  |
| T5   | Handler de upload            | `front.html`       | ✅  |
| T6   | UAT                          | ambiente           | ✅  |

### Check 2 — Diagrama × `Depends on`

| Task | Depends on (def) | Diagrama     | OK  |
| ---- | ---------------- | ------------ | --- |
| T1   | None             | início       | ✅  |
| T2   | T1               | T1→T2        | ✅  |
| T3   | T2               | T2→T3        | ✅  |
| T4   | T3               | T3→T4        | ✅  |
| T5   | T2               | T2→T5 [P]    | ✅  |
| T6   | T1,T2,T3,T4,T5   | convergência | ✅  |

### Check 3 — Co-locação de testes

| Task  | Camada           | Test type (TESTING.md) | Ação                        |
| ----- | ---------------- | ---------------------- | --------------------------- |
| T1–T6 | DB / n8n / front | none (sem framework)   | Verificação manual em T6 ✅ |

> O projeto não possui testes automatizados (ver `.specs/codebase/TESTING.md`). Recomendação futura (M3): pgTAP para a RPC e Playwright para o upload.

---

## Cobertura de Requisitos

| Requirement ID | Task(s)                                  |
| -------------- | ---------------------------------------- |
| UPDATE-01      | T6 (validação) / habilitado por T1,T3,T4 |
| UPDATE-02      | T1, T6                                   |
| UPDATE-03      | T1, T6                                   |
| FLOW-01        | T3, T6                                   |
| FLOW-02        | T4, T6                                   |
| FLOW-03        | T1, T4, T5, T6                           |
| UNIQ-01        | T2, T6                                   |

**Cobertura:** 7/7 requisitos mapeados ✅
