# Architecture

**Padrão:** Aplicação orientada a workflows (n8n) com frontend SPA single-file e banco "lógica-no-banco" (Supabase RPC). Sem camada de backend tradicional — todo o backend é composto por webhooks n8n que invocam funções RPC PostgreSQL.

## Estrutura de alto nível

```
┌──────────────────────────────────────────────────────────────┐
│  front.html (SPA vanilla JS)  — servida via /webhook/embaplan-chat │
└──────────────┬───────────────────────────────────────────────┘
               │ fetch (REST) → base: .../webhook
               ▼
┌──────────────────────────────────────────────────────────────┐
│  n8n (Cloudfy)  — ~15 workflows expondo webhooks               │
│  ┌────────────┬─────────────┬───────────────┬───────────────┐ │
│  │ Agent IA   │ Chat APIs   │ Upload/Snap    │ Recomendações │ │
│  │ (LangChain)│ (sessions,  │ (planilha →    │ (Azure OpenAI)│ │
│  │  + RAG     │  history,   │  batch →       │               │ │
│  │            │  tags)      │  snapshots)    │               │ │
│  └─────┬──────┴──────┬──────┴───────┬────────┴──────┬────────┘ │
└────────┼─────────────┼──────────────┼───────────────┼──────────┘
         │             │              │               │
         ▼             ▼              ▼               ▼
┌──────────────┐  ┌─────────────────────────────────────────────┐
│ Google Sheets│  │ Supabase (PostgreSQL)                        │
│ Google Drive │  │  - auth.users (+ raw_user_meta_data)         │
│ (fonte dados)│  │  - embaplan_* tables                         │
│ Gemini/Azure │  │  - funções RPC SECURITY DEFINER (lógica)     │
│ Shopee       │  │  - vector store (RAG embeddings)             │
└──────────────┘  └─────────────────────────────────────────────┘
```

## Padrões identificados

### 1. Backend-as-Workflows (n8n)

**Local:** `workspaces/*.json`
**Propósito:** cada workflow expõe um ou mais webhooks REST; substitui um servidor de API tradicional.
**Implementação:** webhook node → nós Code (transformação JS) → nós Postgres/Supabase (RPC) → resposta.
**Exemplo:** `Embaplan-Historico-Snapshots.json` expõe `embaplan-ad-timeline` e `embaplan-overview`.

### 2. Lógica-no-banco via RPC `SECURITY DEFINER`

**Local:** `migrations/*.sql`
**Propósito:** centralizar regras de negócio e controle de acesso em funções PostgreSQL.
**Implementação:** todas as funções usam `SECURITY DEFINER SET search_path = public`; guards de admin via `embaplan_is_admin()`.
**Exemplo:** `embaplan_create_month_batch()`, `embaplan_admin_delete_user()`.

### 3. SPA single-file

**Local:** `front.html`
**Propósito:** UI completa (chat + dashboard) em um único arquivo, servível por qualquer host estático ou pelo próprio n8n.
**Implementação:** HTML + CSS (tokens) + JS vanilla; estado em variáveis globais e `localStorage`.

### 4. Histórico append-only (snapshots versionados)

**Local:** `embaplan_upload_batch` + `embaplan_analysis_snapshot`
**Propósito:** comparar evolução de anúncios ao longo do tempo (antes/depois).
**Implementação:** cada upload = 1 batch (mês); cada anúncio = 1 snapshot por batch; uploads mensais idempotentes (mesmo `periodo` substitui anterior).

### 5. Agente IA com ferramentas (tool-calling)

**Local:** `Embaplan - Agent IA.json`
**Propósito:** responder perguntas e auditar anúncios usando dados reais (sem alucinar).
**Implementação:** agente LangChain (Gemini) com sub-workflows expostos como tools (`Consultar_Planilha_Inteligente`, `Analisar_Link_Shopee`) + memória Postgres.

## Fluxos de dados principais

### Upload de planilha → snapshots

```
front.html → POST embaplan-upload-planilha
  → valida xlsx/csv
  → atualiza Google Sheets master
  → Sub-fluxo "Consultar Todas as Abas" → SUMARIO_PRE_CALCULADO
  → extrai produtos[]
  → POST embaplan-capture-snapshot
     → embaplan_create_month_batch (RPC)
     → embaplan_insert_snapshots (RPC)
     → embaplan_purge_pending_recommendations (RPC)
```

### Chat com agente IA

```
front.html → POST embaplan-AgentRag (streaming)
  → Postgres Chat Memory (últimas 10 msgs)
  → Agent (Gemini) chama tools:
       Consultar_Planilha_Inteligente (dados/métricas)
       Analisar_Link_Shopee (auditoria de link)
  → resposta em Markdown (stream SSE) → grava em embaplan_chat_message
```

### Geração de recomendações IA

```
front.html → POST embaplan-generate-recommendations
  → embaplan_ad_context_for_ai (RPC: estado atual + histórico + recs existentes)
  → Azure OpenAI gera 2-5 recomendações com impacto em R$
  → valida JSON
  → embaplan_add_agent_recommendations (RPC, com dedup)
```

### Dashboard (visão geral / evolução)

```
front.html → GET embaplan-overview?loja=...   → embaplan_latest_overview (RPC)
           → GET embaplan-portfolio-evolution → embaplan_portfolio_evolution (RPC)
           → GET embaplan-detect-changes      → comparação de 2 batches
```

## Organização de código

**Abordagem:** por camada física e por canal de integração.

- **Apresentação:** `front.html` (única).
- **Orquestração/API:** `workspaces/*.json` (um workflow por grupo de endpoints).
- **Dados/regra:** `migrations/*.sql` (RPCs + schema).
- **Conhecimento RAG:** `RAG/` (PDF playbook) + Google Drive.

**Limites de módulo:** definidos pelo prefixo `embaplan_` no banco e pelo nome do workflow (`Embaplan-<Feature>`). Não há acoplamento direto entre workflows exceto via webhooks e sub-fluxos (`toolWorkflow`).
