# Codebase Concerns

**Analysis Date:** 2026-06-23

## Security Considerations

**Login do frontend com credenciais fixas (admin/admin):**

- Risk: o `front.html` autentica contra usuário/senha hardcoded (`admin`/`admin`) com token estático `"valid"` em `localStorage` (`chat_auth_v2`, expiração 12h). Qualquer pessoa com a URL acessa a aplicação. Há ainda auto-login em ambientes sandbox (iframe) que ignora a tela de login.
- Files: `front.html` (linhas ~5250–5390)
- Current mitigation: expiração de sessão de 12h; nenhuma verificação no servidor.
- Recommendations: integrar o login do front com o Supabase Auth já modelado no banco (`auth.users`, papéis `admin`/`visualizador`). A skill `.github/skills/supabase-auth` cobre exatamente esse fluxo (login, sessão em iframe, RBAC). Remover credenciais fixas e validar sessão no backend.

**Webhooks n8n públicos sem autenticação por token:**

- Risk: os endpoints sob `https://longflatworm-n8n.cloudfy.live/webhook/embaplan-*` (incluindo `embaplan-DatabaseSetup`, `embaplan-batch-delete`, `embaplan-user-change`) não apresentam validação de origem/assinatura no front. Endpoints de escrita/admin podem ser chamados diretamente.
- Files: `workspaces/*.json` (webhook nodes), `front.html` (lista de endpoints, ~5021–5048)
- Current mitigation: obscuridade da URL; controle de admin existe apenas nas RPCs `embaplan_admin_*`.
- Recommendations: exigir autenticação (header/JWT do Supabase) nos webhooks; propagar a identidade do usuário às RPCs em vez de injetar o UUID via texto da mensagem (`trg_chat_set_user_id`).

**Identidade do usuário derivada do conteúdo da mensagem:**

- Risk: `trg_chat_set_user_id` (migration `007`) extrai o UUID do usuário de um padrão de texto `[CONTEXTO DO USUÁRIO: ID="..."]` dentro da mensagem. Um cliente pode forjar esse contexto e se passar por outro usuário.
- Files: `migrations/007_add_user_to_chat.sql`
- Current mitigation: nenhuma.
- Recommendations: derivar `user_id` do JWT autenticado no n8n/Supabase, não do corpo da mensagem.

**Endpoint destrutivo de setup exposto:**

- Risk: `embaplan-DatabaseSetup` (reset/inicialização do banco) é acionável a partir do front.
- Files: `front.html` (~5021–5048), workflow correspondente.
- Recommendations: remover do front, restringir a operação a admin autenticado ou a uso manual interno.

## Test Coverage Gaps

**Ausência total de testes automatizados:**

- What's not tested: tudo — funções RPC do banco, workflows n8n e o frontend.
- Risk: regressões silenciosas em lógica financeira crítica (cálculo de ROAS/ACOS/lucro, idempotência de batches mensais, avaliação de efetividade de recomendações, deltas/tendências via `LAG()`).
- Priority: High (especialmente para o banco, que concentra a regra de negócio).
- Difficulty to test: média — requer Supabase local/efêmero (pgTAP) e Playwright para o front. Ver TESTING.md.

## Fragile Areas

**Ingestão de planilha dependente de Google Sheets como fonte de verdade:**

- Files: `workspaces/Embaplan-Upload-Planilha-Anuncios.json`, sub-fluxos "Consultar Todas as Abas" / "Consultar Planilha Inteligente"
- Why fragile: o fluxo lê todas as abas e consolida `SUMARIO_PRE_CALCULADO`; mudanças de layout/colunas na planilha, nomes de abas ou formatação numérica (`"R$ 1.234,56"`, `"7,5%"`) podem quebrar o parsing.
- Common failures: campos não parseados, anúncios ausentes, métricas zeradas.
- Safe modification: validar o esquema esperado antes de inserir snapshots; centralizar o parsing numérico (`toNum()`); adicionar testes de integração com planilhas de exemplo (`*.xlsx` já presentes no repo).
- Test coverage: nenhuma.

**Mapeamento de lojas Shopee hardcoded:**

- Files: workflows que geram links Shopee; `migrations/011`/`013` (`embaplan_extract_link`)
- Why fragile: shop IDs fixos (`1→457463719`, `2→1020574907`, `3→959503392`) e padrão de link `...-i.{shop_id}.{ad_id}`; novas lojas exigem alteração manual de código.
- Safe modification: externalizar o mapeamento loja→shop_id para configuração/tabela.

**front.html monolítico (~10.900 linhas, ~369 KB):**

- Files: `front.html`
- Why fragile: HTML+CSS+JS em arquivo único excede de longe o limite de 800 linhas das convenções ECC; difícil de revisar, testar e modificar com segurança.
- Safe modification: mudanças pontuais e bem localizadas; a médio prazo, considerar modularizar (extrair JS/CSS) caso o projeto evolua para build próprio.

## Tech Debt

**Lógica de negócio acoplada a nós Code do n8n:**

- Issue: transformações importantes (parsing, consolidação, montagem de prompt) vivem em nós Code JavaScript dentro dos JSON de workflow, sem versionamento granular nem testes.
- Files: `workspaces/Embaplan - Agent IA.json`, `Embaplan-Recomendacoes-IA.json`, `Embaplan-Upload-Planilha-Anuncios.json`
- Why: velocidade de prototipação no n8n.
- Impact: difícil revisar diffs (JSON grande), reproduzir e testar; risco de divergência entre lógica do front e do backend.
- Fix approach: extrair helpers reutilizáveis, documentar contratos de payload e cobrir com testes de integração de webhook.

**Dois provedores de LLM em paralelo (Gemini + Azure OpenAI):**

- Issue: chat usa Gemini 3 Pro; recomendações usam Azure `gpt-5.4-mini`. Dois conjuntos de credenciais e comportamentos.
- Files: `Embaplan - Agent IA.json`, `Embaplan-Recomendacoes-IA.json`
- Impact: manutenção e custo duplicados; comportamento inconsistente.
- Fix approach: avaliar consolidação ou documentar claramente o porquê de cada escolha.

## Dependencies at Risk

**Modelos de LLM com nomes de versão preview/futuros:**

- Risk: `models/gemini-3-pro-preview` e `gpt-5.4-mini` são identificadores de preview; nomes/preços/disponibilidade podem mudar e quebrar os workflows.
- Impact: chat e recomendações ficam indisponíveis.
- Migration plan: parametrizar o nome do modelo via variável; ter fallback configurável.

**Bibliotecas de frontend via CDN com `@latest`:**

- Risk: `lucide@latest` (unpkg) pode introduzir mudanças sem aviso; CDNs externos são ponto único de falha.
- Files: `front.html` (linhas 7–17)
- Migration plan: fixar versões e/ou hospedar localmente (alinhado às convenções web ECC de evitar dependências remotas voláteis).

---

_Concerns audit: 2026-06-23_
_Atualizar conforme problemas forem corrigidos ou novos forem descobertos._
