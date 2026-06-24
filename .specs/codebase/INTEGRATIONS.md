# External Integrations

## Banco de dados / Auth / Vector — Supabase (PostgreSQL)

**Serviço:** Supabase
**Propósito:** banco relacional (tabelas `embaplan_*`), autenticação (`auth.users`), lógica de negócio (funções RPC) e vector store para RAG.
**Implementação:** nós Postgres/Supabase nos workflows n8n; funções RPC em `migrations/*.sql`.
**Configuração:** credencial n8n `Supabase_database`.
**Autenticação:** Supabase Auth; papéis em `raw_user_meta_data->>'role'` (`admin` | `visualizador`), filtro por `company_name='embaplan'`.

## Planilhas — Google Sheets (OAuth2)

**Serviço:** Google Sheets
**Propósito:** fonte de verdade dos dados de produtos/anúncios; geração dinâmica de links Shopee; enumeração de abas.
**Implementação:** `Embaplan-Upload-Planilha-Anuncios.json`, sub-fluxos "Consultar Todas as Abas" e "Consultar Planilha Inteligente".
**Configuração:** credencial `Google Sheets account`.

## Arquivos — Google Drive (OAuth2)

**Serviço:** Google Drive
**Propósito:** armazenar versões de planilhas; fornecer documentos para o pipeline RAG.
**Implementação:** `Embaplan-Upload-Planilha-Anuncios.json`, `Embaplan - RAG.json`.
**Configuração:** credencial `Google Drive account`.

## LLM principal — Google Gemini

**Serviço:** Google Gemini 3 Pro (`models/gemini-3-pro-preview`)
**Propósito:** agente IA de chat (auditoria de anúncios, análise financeira, orquestração de tools).
**Implementação:** `Embaplan - Agent IA.json`, `Embaplan - RAG.json`.
**Configuração:** credencial `Google Gemini(PaLM) Api account 2`; temperatura ~0.4; máx. 25 iterações de tool.

## LLM secundário — Azure OpenAI

**Serviço:** Azure OpenAI (`gpt-5.4-mini`)
**Propósito:** geração de recomendações de otimização com impacto financeiro em R$.
**Implementação:** `Embaplan-Recomendacoes-IA.json`.
**Configuração:** credencial `Azure Open AI account 3`.

## Marketplace — Shopee

**Serviço:** Shopee (Brasil)
**Propósito:** auditar listagem de anúncio; gerar links a partir de título/loja/ID.
**Implementação:** tool `Analisar_Link_Shopee` no agente; extração de link via `embaplan_extract_link()` (migrations 011/013).
**Padrão de link:** `https://shopee.com.br/{slug}-i.{shop_id}.{ad_id}`.
**Mapeamento de lojas (shop IDs):** `1 → 457463719`, `2 → 1020574907`, `3 → 959503392`.
**Indexação de anúncio:** `L{loja}#{indice}` (ex.: `L2#47`).

## API Integrations (webhooks n8n)

**Base URL:** `https://longflatworm-n8n.cloudfy.live/webhook`

### Chat & IA

- `POST embaplan-AgentRag` — entrada do agente IA (streaming)
- `POST embaplan-index-drive` — upload de arquivo para indexação RAG
- `POST embaplan-prune-history` — limpar histórico antigo/editado
- `GET embaplan-chat` — serve o frontend HTML
- `GET embaplan_health` — health check

### Sessões & Tags de chat

- `GET embaplan-sessions` — lista sessões
- `GET embaplan-history?sessionId=` — histórico de uma sessão
- `DELETE embaplan-session?sessionId=` — exclui sessão
- `POST embaplan-add-tag` / `POST embaplan-remove-tag`
- `GET embaplan-list-tags` / `GET embaplan-session-tags?session_id=`
- `POST embaplan-rename-tag` / `POST embaplan-delete-tag` / `GET embaplan-autocomplete`

### Planilhas & Batches

- `POST embaplan-upload-planilha` — upload de Excel/CSV
- `POST embaplan-capture-snapshot` — captura snapshot dos anúncios
- `GET embaplan-batches` — lista versões/batches
- `POST embaplan-batch-update` / `POST embaplan-batch-delete`
- `POST embaplan-detect-changes` — compara dois batches

### Analytics & Recomendações

- `GET embaplan-ad-timeline?indice=` — série temporal de um anúncio
- `GET embaplan-overview?loja=` — visão geral do dashboard
- `GET embaplan-portfolio-evolution?loja=&produto=` — evolução do portfólio
- `GET embaplan-recommendations` — recomendações de um produto
- `POST embaplan-generate-recommendations` — gera recomendações via IA
- `POST embaplan-add-recommendations` — adiciona recomendações manuais
- `POST embaplan-recommendation-status` — atualiza status
- `POST embaplan-recommendation-delete` — exclui recomendação

### Administração

- `POST embaplan-user-change` — altera usuário/papel
- `POST embaplan-DatabaseSetup` — inicializa/reseta o banco

## Webhooks (entrada)

Todos os endpoints acima são webhooks n8n. Não há assinatura/validação de origem documentada — ver CONCERNS.md (endpoints públicos sem autenticação por token).

## Background Jobs

**Sistema de fila:** nenhum dedicado. Processamento assíncrono via encadeamento de webhooks (ex.: upload → `embaplan-capture-snapshot`).
**Local:** `workspaces/`.
**Jobs-chave:** captura de snapshot pós-upload; avaliação de efetividade de recomendações entre batches (`embaplan_evaluate_recommendations`).
