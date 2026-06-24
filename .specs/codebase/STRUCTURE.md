# Project Structure

**Raiz:** `c:\Users\Administrador\Downloads\embaplan`

## Árvore de diretórios

```
embaplan/
├── front.html                 # SPA completa (chat + dashboard), ~10.900 linhas
├── migrations/                # Schema + funções RPC do Supabase (SQL versionado)
│   ├── 001_..._019_*.sql       # Migrations sequenciais
│   └── down_clean_old_schema.sql
├── workspaces/                # Workflows n8n exportados (JSON)
│   ├── Embaplan - Agent IA.json
│   ├── Embaplan - RAG.json
│   ├── Embaplan-Front.json
│   ├── Embaplan-Upload-Planilha-Anuncios.json
│   ├── Embaplan-Historico-Snapshots.json
│   ├── Embaplan-Recomendacoes-IA.json
│   ├── Embaplan-Portfolio-Evolution.json
│   ├── Embaplan-Detect-Changes.json
│   ├── Embaplan-Gerenciar-Planilhas.json
│   ├── Embaplan-Chat-*.json     # GET-History, GET-Sessions, DELETE-Session, Tags
│   ├── Embaplan - Consultar Todas as Abas.json
│   └── [Embaplan] Sub-fluxo_ Consultar Planilha Inteligente.json
├── RAG/                        # Base de conhecimento
│   └── Playbook Analista Shopee Ads.pdf
├── docs/                       # (vazio)
├── *.xlsx                      # Planilhas de exemplo/dados Shopee
└── .specs/                     # Documentação spec-driven (este diretório)
```

## Organização por módulo

### Apresentação

**Propósito:** UI do usuário (chat IA + dashboard analítico).
**Local:** `front.html`
**Arquivos-chave:** `front.html` (único).

### Orquestração / API (n8n)

**Propósito:** expor webhooks REST e orquestrar dados, IA e integrações.
**Local:** `workspaces/`
**Arquivos-chave:** `Embaplan - Agent IA.json` (chat), `Embaplan-Upload-Planilha-Anuncios.json` (ingestão), `Embaplan-Historico-Snapshots.json` (analytics).

### Dados / regra de negócio

**Propósito:** schema, controle de acesso e lógica de negócio.
**Local:** `migrations/`
**Arquivos-chave:** `008_analysis_snapshots.sql`, `009_recommendations.sql`, `018_batch_management.sql`, `003_admin_guards.sql`.

### Conhecimento (RAG)

**Propósito:** material de domínio para o agente IA.
**Local:** `RAG/` + Google Drive
**Arquivos-chave:** `Playbook Analista Shopee Ads.pdf`.

## Onde as coisas vivem

**Chat IA:**

- UI: `front.html` (área de chat, sessões, tags)
- Orquestração: `Embaplan - Agent IA.json`, `Embaplan-Chat-*.json`, `Embaplan - RAG.json`
- Dados: `embaplan_chat_message`, `embaplan_chat_tags` (`007`, `015`)

**Dashboard / Analytics:**

- UI: `front.html` (overlay com abas Visão Geral, Alertas, Comparar, Oportunidades, Evolução)
- Orquestração: `Embaplan-Historico-Snapshots.json`, `Embaplan-Portfolio-Evolution.json`, `Embaplan-Detect-Changes.json`
- Dados: `embaplan_upload_batch`, `embaplan_analysis_snapshot` (`008`, `011`, `012`, `019`)

**Upload de planilha:**

- UI: `front.html` (botão "Enviar Planilha")
- Orquestração: `Embaplan-Upload-Planilha-Anuncios.json` + sub-fluxos
- Dados: `embaplan_create_month_batch`, `embaplan_insert_snapshots`

**Recomendações IA:**

- UI: `front.html` (seções de recomendações)
- Orquestração: `Embaplan-Recomendacoes-IA.json`
- Dados: `embaplan_recommendation` (`009`, `010`, `014`)

**Gestão de usuários (admin):**

- UI: `front.html` (gestão via `embaplan-user-change`)
- Dados: `auth.users` + RPCs `embaplan_admin_*` (`001`–`006`)

## Diretórios especiais

**`migrations/`** — Schema do Supabase versionado; aplicar em ordem numérica.
**`workspaces/`** — Workflows n8n; importar no n8n para deploy. Fonte de verdade do backend.
**`.specs/`** — Documentação spec-driven (codebase mapping + project + features).
**`docs/`** — Atualmente vazio; reservado para documentação gerada.
