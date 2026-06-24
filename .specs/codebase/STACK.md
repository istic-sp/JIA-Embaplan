# Tech Stack

**Analisado:** 2026-06-23

## Núcleo

- **Plataforma de backend/orquestração:** n8n (self-hosted em `https://longflatworm-n8n.cloudfy.live`)
- **Banco de dados:** Supabase (PostgreSQL) — credencial n8n `Supabase_database`
- **Frontend:** SPA single-file em HTML/CSS/JS puro (`front.html`, ~10.900 linhas), servida via webhook n8n (`/webhook/embaplan-chat`)
- **Linguagem do produto:** Portuguese (pt-BR) em todo código, UI, comentários e mensagens

## Frontend

- **UI Framework:** Nenhum — JavaScript vanilla (sem React/Vue/Angular)
- **Estilização:** CSS custom properties (design tokens) + media queries responsivas
- **Bibliotecas via CDN:**
  - `marked@4.3.0` — parser Markdown
  - `highlight.js 11.9.0` — syntax highlighting de blocos de código
  - `lucide@latest` (unpkg) — ícones SVG
  - Google Fonts: Inter (300/400/600/700/800)
- **APIs nativas usadas:** `fetch`, `FormData`, `ReadableStream` (streaming SSE), `AbortController`, `localStorage` (com fallback em memória)
- **Gerência de estado:** variáveis globais + `localStorage` (chaves `chat_auth_v2`, `theme`)

## Backend (n8n)

- **Estilo de API:** REST via webhooks n8n (base `https://longflatworm-n8n.cloudfy.live/webhook`)
- **Lógica de negócio:** funções RPC PostgreSQL (`SECURITY DEFINER`) no Supabase + nós Code (JavaScript) nos workflows
- **Autenticação:** Supabase Auth (`auth.users` + `raw_user_meta_data`) no nível de banco; front.html usa login local simplificado (admin/admin) — ver CONCERNS.md
- **Memória de chat:** n8n LangChain Postgres Chat Memory (tabela `embaplan_chat_message`, janela de 10 mensagens)

## IA / RAG

- **LLM principal:** Google Gemini 3 Pro (`models/gemini-3-pro-preview`) — credencial `Google Gemini(PaLM) Api account 2`
- **LLM secundário (recomendações):** Azure OpenAI (`gpt-5.4-mini`) — credencial `Azure Open AI account 3`
- **Framework de agente:** `@n8n/n8n-nodes-langchain.agent` (LangChain dentro do n8n)
- **RAG:** `documentDefaultDataLoader` + `textSplitterCharacterTextSplitter` (LangChain), embeddings em vector store (Supabase Vector/Qdrant)
- **Base de conhecimento:** documentos do Google Drive + `RAG/Playbook Analista Shopee Ads.pdf`

## Testes

- **Unit:** Nenhum framework detectado
- **Integration:** Nenhum
- **E2E:** Nenhum
  > Não há infraestrutura de testes automatizados no repositório. Ver TESTING.md e CONCERNS.md.

## Serviços externos

- **Banco/Auth/Vector:** Supabase
- **Arquivos/Planilhas:** Google Drive OAuth2, Google Sheets OAuth2
- **LLM:** Google Gemini, Azure OpenAI
- **Marketplace:** Shopee (geração de links + análise de anúncio por scraping)
- **Hospedagem n8n:** Cloudfy

## Ferramentas de desenvolvimento

- **Migrations:** arquivos SQL versionados em `migrations/` (`NNN_descricao.sql`, 001–019)
- **Workflows:** JSON exportado do n8n em `workspaces/`
- **Skills/Agents:** `.github/skills/` e `.github/agents/` (automação de documentação e auth)
