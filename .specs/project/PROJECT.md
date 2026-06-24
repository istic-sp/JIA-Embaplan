# Embaplan

**Vision:** Plataforma de inteligência para anúncios de marketplace (Shopee Ads) que transforma planilhas de desempenho em análises, histórico evolutivo e recomendações acionáveis por IA.
**For:** Analistas/gestores de tráfego e e-commerce que operam anúncios na Shopee (e outros marketplaces) e precisam decidir onde escalar, pausar ou otimizar.
**Solves:** A dificuldade de interpretar planilhas extensas de métricas (ROAS, ACOS, lucro, conversão) e acompanhar a evolução dos anúncios ao longo do tempo — substituindo análise manual por dashboards, comparações e sugestões com impacto financeiro em R$.

## Goals

- Ingerir planilhas mensais de anúncios e manter histórico versionado por período (batches idempotentes), permitindo comparar "antes vs. depois".
- Fornecer um agente de IA conversacional que audita anúncios usando dados reais (sem alucinar) e gera recomendações priorizadas com impacto em R$.
- Disponibilizar um dashboard com KPIs (receita, lucro, ROAS, ACOS), alertas de anúncios críticos, comparação entre lojas e evolução do portfólio.

## Tech Stack

**Core:**

- Orquestração/Backend: n8n (self-hosted, Cloudfy) expondo webhooks REST
- Banco/Auth/Vector: Supabase (PostgreSQL) com lógica em funções RPC `SECURITY DEFINER`
- Frontend: SPA single-file em HTML/CSS/JS vanilla (`front.html`)

**Key dependencies:**

- LLM de chat: Google Gemini 3 Pro (agente LangChain no n8n)
- LLM de recomendações: Azure OpenAI (`gpt-5.4-mini`)
- Google Sheets / Google Drive (fonte de dados e arquivos)
- RAG: vector store + `Playbook Analista Shopee Ads.pdf`

## Scope

**v1 inclui:**

- Upload e versionamento de planilhas (batches mensais, snapshots por anúncio)
- Chat com agente IA (auditoria de anúncios, análise financeira) com sessões e tags
- Dashboard analítico (Visão Geral, Alertas, Comparar, Oportunidades, Evolução)
- Recomendações IA (geração, status, avaliação de efetividade entre batches)
- Detecção de mudanças entre batches e gestão de batches (listar/editar/excluir)
- Gestão de usuários e papéis (admin/visualizador) via RPCs admin

**Explicitamente fora de escopo (atual):**

- Testes automatizados (não existem hoje)
- Integração direta com APIs oficiais da Shopee (uso é via planilha + scraping de link)
- Autenticação robusta no frontend (hoje é login local simplificado — ver CONCERNS.md)
- Suporte multi-marketplace completo além de Shopee (mencionado nos prompts, não implementado)

## Constraints

- Técnico: backend inteiramente em n8n + RPCs do Supabase; sem camada de serviço própria. Linguagem do produto é pt-BR (moeda R$, decimais com vírgula).
- Técnico: frontend é arquivo único de ~10.900 linhas, dependente de CDNs externos.
- Segurança: login do front com credenciais fixas e webhooks públicos sem token — débito de segurança conhecido a endereçar.
- Recursos: dependência de dois provedores de LLM (Gemini + Azure) com modelos em preview.
