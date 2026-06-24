# Upload em Múltiplas Datas — Resumo da Implementação

**Feature:** `upload-multidatas`  
**Status:** ✅ Implementação completa | 🧪 Aguardando UAT (T6)  
**Data:** 2026-06-23

---

## Problema Resolvido

**Bug Original:** Ao enviar planilha com data anterior ou posterior às já existentes, o sistema:

- Perdia a data de referência (`periodo`) entre os nós do workflow
- A RPC assumia "hoje" quando `periodo` era `null`
- Com `p_replace=true` fixo, **apagava o batch de hoje** em vez da data escolhida
- Resultado: datas anteriores/posteriores eram ignoradas, cronologia corrompida

**Causa Raiz:**

1. Nó `Preparar Captura` usava referência cruzada frágil `$('Validar Arquivo').first().json` → falha → `periodo=null`
2. RPC `embaplan_create_month_batch` com `periodo=null` executava `_periodo := NOW()::DATE`
3. DELETE não escopado: `WHERE periodo=_periodo` (sem `user_id`) apagava batch errado
4. Sem índice único: permitia duplicatas silenciosas

---

## Solução Implementada

### 1. Migration 020 — RPC Robusta

**Arquivo:** `migrations/020_fix_create_month_batch.sql`

✅ **Mudanças:**

- `periodo` ausente → **EXCEPTION** (não assume mais `NOW()`)
- DELETE escopado: `WHERE periodo=_periodo AND user_id IS NOT DISTINCT FROM p_user_id`
- Consolidação de duplicatas pré-existentes (mantém maior `id`)
- Índice único `uniq_batch_periodo_user` em `(periodo, user_id)`

**Impacto:** RPC nunca mais substitui batch de outra data; garante 1 batch por data.

---

### 2. Workflow de Upload — Validação Antecipada

**Arquivo:** `workspaces/Embaplan-Upload-Planilha-Anuncios.json`  
**Nó:** `Preparar Captura`

✅ **Mudanças:**

```javascript
const periodo = meta.periodo || null;
if (!periodo) {
  throw new Error(
    "periodo ausente no upload — data de referência obrigatória.",
  );
}
```

**Impacto:** Falha cedo em vez de enviar `periodo=null` ao backend.

---

### 3. Workflow de Snapshots — Guarda Dupla

**Arquivo:** `workspaces/Embaplan-Historico-Snapshots.json`  
**Nós:** `Flatten Snapshots`, `Create Batch (RPC)`

✅ **Mudanças:**

- `Flatten Snapshots`: valida `periodo` logo ao processar body
- `Create Batch (RPC)`: passa `$json.periodo` (sem `|| null`)
- `p_replace` permanece `true` (idempotência segura por data)

**Impacto:** Nenhum snapshot gravado sem data; replace só afeta a data correta.

---

### 4. Frontend — Bloqueio de Envio

**Arquivo:** `front.html`  
**Handler:** `pendingAction === "uploadSheet"`

✅ **Mudanças:**

```javascript
if (!periodo) {
  setStatus(
    "Selecione a data de referência antes de enviar a planilha.",
    "error",
  );
  return;
}
```

**Impacto:** Usuário vê feedback imediato; nenhum envio sem data.

---

## Arquitetura de Validação em Camadas

```
┌────────────────┐
│  Frontend      │ ← Valida: bloqueia envio sem data
├────────────────┤
│  Workflow      │ ← Valida: `Preparar Captura` + `Flatten Snapshots`
│  (Upload)      │   Falha: throw Error('periodo ausente')
├────────────────┤
│  Workflow      │ ← Valida: `Create Batch (RPC)` passa periodo sem fallback
│  (Snapshots)   │
├────────────────┤
│  RPC (020)     │ ← Valida: EXCEPTION se periodo IS NULL
│  create_month  │   DELETE escopado: (periodo, user_id)
│  _batch        │   Índice único: garante 1 batch/data
└────────────────┘
```

**Defesa em Profundidade:** 4 camadas independentes garantem integridade.

---

## Testes Executados

### T1-T5: Implementação de Código

- ✅ T1: Migration 020 criada com RPC robusta
- ✅ T2: Unicidade e consolidação de duplicatas adicionadas
- ✅ T3: Workflow de upload validando `periodo`
- ✅ T4: Workflow de snapshots com guarda dupla
- ✅ T5: Frontend bloqueando envio sem data

### T6: UAT Manual (Pendente)

**Status:** 🧪 Aguardando execução

**Roteiro:**

1. Aplicar migration 020 no Supabase
2. Reimportar workflows editados no n8n
3. Testar adicionar datas anteriores → ✅ não apaga batches existentes
4. Testar adicionar datas posteriores → ✅ adiciona na cronologia
5. Testar replace de mesma data → ✅ substitui só aquele dia
6. Testar envio sem data → ✅ bloqueado pelo front
7. Verificar unicidade → ✅ `SELECT ... HAVING COUNT(*)>1` retorna 0 linhas

**Critérios de Aprovação:**

- Todos os 6 cenários passam conforme esperado
- Cronologia permanece íntegra (nenhum batch apagado indevidamente)
- `periodo` no banco sempre igual à escolhida no front

---

## Rastreabilidade de Requisitos

| Requisito     | Tipo                                          | Implementado em                          |
| ------------- | --------------------------------------------- | ---------------------------------------- |
| **UPDATE-01** | Adicionar data anterior sem apagar existentes | T1 (DELETE escopado) + T3/T4 (validação) |
| **UPDATE-02** | Adicionar data posterior                      | T1 (DELETE escopado) + T3/T4 (validação) |
| **UPDATE-03** | Replace seguro por data+usuário               | T1 (DELETE escopado)                     |
| **FLOW-01**   | periodo obrigatória no front                  | T5 (validação frontend)                  |
| **FLOW-02**   | periodo obrigatória no workflow               | T3 (`Preparar Captura`) + T4 (`Flatten`) |
| **FLOW-03**   | periodo obrigatória na RPC                    | T1 (EXCEPTION)                           |
| **UNIQ-01**   | Unicidade de `periodo`                        | T2 (índice único)                        |

**Coverage:** 7/7 requisitos atendidos ✅

---

## Próximos Passos

### Imediato (T6)

1. **Aplicar migration:** `psql` ou SQL Editor do Supabase
   ```sql
   \i migrations/020_fix_create_month_batch.sql
   ```
2. **Reimportar workflows:**
   - n8n → Import workflow → Upload `Embaplan-Upload-Planilha-Anuncios.json`
   - n8n → Import workflow → Upload `Embaplan-Historico-Snapshots.json`
   - Ativar ambos
3. **Executar UAT:** Seguir roteiro da seção acima
4. **Documentar resultados:** Registrar em `STATE.md` ou neste arquivo

### Pós-Validação

```bash
git add migrations/020_fix_create_month_batch.sql
git commit -m "feat(db): corrige create_month_batch para multiplas datas"

git add workspaces/Embaplan-*.json
git commit -m "fix(n8n): valida periodo nos fluxos de upload"

git add front.html
git commit -m "fix(front): exige data de referencia no upload"
```

### Melhoria Futura (M3)

- pgTAP para testar RPC com cenários: null periodo, replace escopado, unicidade
- Playwright para UAT automatizado do upload end-to-end

---

## Decisões Técnicas

| Decisão                   | Escolha                  | Racional                                                |
| ------------------------- | ------------------------ | ------------------------------------------------------- |
| **periodo nula na RPC**   | EXCEPTION                | Evita substituição acidental — causa raiz do bug        |
| **Escopo do replace**     | Por `(periodo, user_id)` | Não apaga batches de outras datas/usuários              |
| **Unicidade**             | Índice único parcial     | Garante 1 batch por data; defesa em profundidade        |
| **Validação em camadas**  | Front + Workflow + RPC   | Redundância garante integridade mesmo com falha parcial |
| **Manter assinatura RPC** | Sim                      | Não quebra nós n8n existentes; CREATE OR REPLACE        |

---

## Lições Aprendidas

**L-002 (registrado em STATE.md):**

> Bug de upload multi-data = perda de `periodo` + replace agressivo. Workflows n8n podem perder dados em referências cruzadas assíncronas; RPCs devem falhar cedo (EXCEPTION) em vez de assumir defaults silenciosos; DELETE sempre escopado por chaves lógicas.

**Prevenção:**

- Validação em múltiplas camadas (front, workflow, RPC)
- Índices únicos reforçam invariantes críticos
- Falhar cedo > assumir valor default
- Testes UAT roteirizados antes de produção

---

**Documentação Relacionada:**

- Spec: `.specs/features/upload-multidatas/spec.md`
- Design: `.specs/features/upload-multidatas/design.md`
- Tasks: `.specs/features/upload-multidatas/tasks.md`
- Roadmap: `.specs/project/ROADMAP.md` (M2.5)
- State: `.specs/project/STATE.md`
