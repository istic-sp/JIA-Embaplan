# Code Conventions

**Idioma:** Portuguese (pt-BR) em todo o projeto — código, UI, comentários, mensagens de erro, nomes de colunas. Moeda em Real (R$), separador decimal vírgula.

## Convenções de nomenclatura

**Frontend — funções (camelCase):**
Padrão `verbo + Substantivo`: `sendMessage()`, `fetchSessions()`, `renderDashboard()`, `openDashboard()`, `loadDashboard()`, `toggleTheme()`.
Prefixos comuns: `load*`, `render*`, `fetch*`, `handle*`, `setup*`, `toggle*`.

**Frontend — CSS (kebab-case):**
`.app-container`, `.main-grid`, `.chat-header`, `.sidebar`, `.message.user`, `.dashboard-overlay`, `.dash-tab`, `.kpi-pill`, `.priority-badge`.

**Frontend — IDs (camelCase):**
`#sessionList`, `#messagesContainer`, `#dashboardOverlay`, `#loginOverlay`, `#messageInput`, `#sendBtn`.

**Banco — tabelas:** prefixo `embaplan_*` (escopo de projeto / multi-tenant). Ex.: `embaplan_upload_batch`, `embaplan_analysis_snapshot`, `embaplan_chat_message`.

**Banco — funções RPC:** `embaplan_<acao>` ou `embaplan_admin_<acao>` (sufixo admin = gated por `embaplan_is_admin()`).

**Banco — colunas (snake_case):** `anuncio_indice`, `investimento_ads`, `ticket_medio`, `metrics_jsonb`, `created_at`. Métricas em português: `saude`, `receita`, `lucro`, `acos`, `roas`, `ctr`, `conversao`.

**Banco — índices:** `idx_<tabela>_<colunas>` (ex.: `idx_snapshot_serie`).
**Banco — triggers:** `trg_<tabela>_<acao>` (ex.: `trg_chat_set_user_id`).
**Banco — enums:** `embaplan_<entidade>_<tipo>` (ex.: `embaplan_rec_status`).

**Workflows n8n:** `Embaplan - <Propósito>` ou `Embaplan-<Feature>`; sub-fluxos `[Embaplan] Sub-fluxo: <Nome>`.

**Webhooks:** kebab-case com prefixo `embaplan-` (ex.: `embaplan-upload-planilha`, `embaplan-ad-timeline`). Exceção: `embaplan_health`.

**Migrations:** `NNN_snake_case_descricao.sql` (sequência de 3 dígitos com zero à esquerda).

## Organização de código

**front.html (single-file, ~10.900 linhas):**

1. `<head>` + scripts CDN + CSS (tokens e componentes) — linhas ~1–3400
2. `<body>` DOM: header, sidebar, chat, dashboard overlay, modais — ~3400–4850
3. JavaScript: constantes/config → refs DOM → camada de storage → API → render → handlers — ~5000–10900

Cabeçalhos de seção via comentário: `// ============== NOME DA SEÇÃO`.

**Workflows:** nós Code (JS) para transformação; sticky notes documentam propósito e setup antes de cada workflow.

## Type safety / documentação

Sem TypeScript nem JSDoc. JavaScript dinâmico no front e nos nós Code. Documentação via sticky notes (n8n) e comentários inline em português.

## Tratamento de erros

**Frontend:** tolerante a falhas de rede — interceptor global de `fetch` monitora `API_BASE`, polling de `embaplan_health` a cada 10s quando offline, recuperação em erros de gateway (502/503/504/520-524) consultando o endpoint de histórico; `AbortController` para cancelamento.
**Banco:** funções levantam `EXCEPTION` com mensagens em português e `ERRCODE` (ex.: `42501` para acesso negado).
**Parsing numérico:** helpers defensivos (`toNum()`) tratam `"R$ 1.234,56"`, `"7,5%"`.

## Comentários

Estilo em português, com emojis em logs de console (`console.log("🔓 ...")`, `console.warn("⚠️ ...")`). Comentários explicam intenção (`// Mantém o estado anterior`).

## Padrões recorrentes (banco)

- **Upsert idempotente:** `embaplan_create_month_batch(..., p_replace=TRUE)` substitui batch do mesmo período; tags via `ON CONFLICT DO NOTHING`.
- **Ordenação temporal:** ordenar por `COALESCE(periodo, created_at::date)` (migration 019), não pelo timestamp de upload.
- **Auto-população por trigger:** `trg_chat_set_user_id` extrai UUID do contexto da mensagem.
- **Window functions:** `LAG() OVER` para calcular deltas e tendência (`evoluindo`/`piorando`/`estavel`).
- **Cascades:** snapshot FK `ON DELETE CASCADE`; recommendation FK `ON DELETE SET NULL`.
