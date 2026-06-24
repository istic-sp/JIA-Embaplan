# Roadmap

**Current Milestone:** M1 — Plataforma operacional (estado atual)
**Status:** In Progress

> Projeto brownfield. O M1 reflete o que já está implementado e em uso; M2+ são melhorias derivadas do mapeamento e do CONCERNS.md.

---

## M1 — Plataforma operacional (estado atual)

**Goal:** Ingestão de planilhas, chat IA, dashboard e recomendações funcionando ponta a ponta.
**Target:** Implementado (em produção via n8n/Cloudfy).

### Features

**Upload & Versionamento de planilhas** - COMPLETE

- Upload de Excel/CSV com validação
- Batches mensais idempotentes (mesmo período substitui anterior)
- Snapshots append-only por anúncio

**Chat com Agente IA** - COMPLETE

- Agente LangChain (Gemini) com tools de planilha e link Shopee
- Memória de conversa (Postgres), sessões e histórico
- Tags de sessão (adicionar/remover/renomear/excluir/filtrar)
- RAG sobre playbook e documentos do Drive

**Dashboard analítico** - COMPLETE

- Visão Geral (KPIs: receita, lucro, ROAS, ACOS, críticos)
- Alertas (anúncios com gargalo/ralo/lucro negativo/ACOS alto)
- Comparar (benchmark entre lojas)
- Oportunidades (anúncios para escalar)
- Evolução (portfólio ao longo do tempo)

**Recomendações IA** - COMPLETE

- Geração via IA com impacto em R$ e deduplicação
- Recomendações manuais; status (pendente/feito/descartado)
- Avaliação de efetividade entre batches

**Detecção de mudanças & Gestão de batches** - COMPLETE

- Comparação entre dois batches (deltas)
- Listar/editar/excluir batches; purge de recomendações pendentes

**Gestão de usuários (admin)** - COMPLETE

- RPCs admin: listar/confirmar/atualizar/excluir usuários
- Papéis admin/visualizador; guard de admin; prevenção de auto-exclusão

---

## M2 — Segurança & Identidade

**Goal:** Eliminar os débitos de segurança críticos do M1.

### Features

**Autenticação real no frontend** - PLANNED

- Integrar `front.html` ao Supabase Auth (substituir login admin/admin)
- RBAC admin/visualizador na UI

**Proteção dos webhooks n8n** - PLANNED

- Exigir JWT/token nos webhooks; derivar `user_id` do token (não do texto da mensagem)
- Restringir endpoints destrutivos (`DatabaseSetup`, `batch-delete`, `user-change`)

---

## M2.5 — Correções de ingestão (em teste)

**Goal:** Tornar o upload de planilhas confiável para múltiplas datas.

### Features

**Upload em múltiplas datas (anteriores/posteriores)** - IN TEST

- ✅ Corrige perda de `periodo` no workflow de upload
- ✅ RPC `create_month_batch` robusta (não assume "hoje"; replace escopado por data+usuário)
- ✅ Unicidade por data no banco
- 🧪 Aguardando UAT manual (T6)
- Spec/design/tasks: `.specs/features/upload-multidatas/`

---

## M3 — Qualidade & Confiabilidade

**Goal:** Reduzir fragilidade e regressões silenciosas.

### Features

**Testes automatizados** - PLANNED

- pgTAP para RPCs críticas (cálculos, idempotência, guards)
- Playwright para fluxos E2E do front
- Testes de integração dos webhooks

**Robustez da ingestão de planilha** - PLANNED

- Validação de esquema antes de inserir snapshots
- Parsing numérico centralizado e testado

---

## Future Considerations

- Suporte multi-marketplace (Mercado Livre, Amazon, Shein) já citado nos prompts
- Externalizar mapeamento loja→shop_id (remover hardcode)
- Modularizar `front.html` / pipeline de build
- Consolidar/parametrizar provedores de LLM e modelos
