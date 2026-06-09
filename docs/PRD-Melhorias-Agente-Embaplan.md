# PRD & Plano — Evolução do Agente Embaplan

> **Versão:** 1.1 · **Data:** 09/06/2026 · **Produto:** Assistente Inteligente de Performance de Anúncios (Embaplan)
> **Status:** Em implementação (Fase 1 — Épico 1 entregue parcialmente)

---

## 0. Status de Implementação

| Item | Arquivo | Estado |
|------|---------|--------|
| Tabelas de histórico (batch + snapshot) + RPCs (criar batch, gravar snapshots, timeline, overview) | [migrations/008_analysis_snapshots.sql](../migrations/008_analysis_snapshots.sql) | ✅ Entregue |
| Tabela de recomendações + RPCs (registrar, status, "Outros", avaliar eficácia, listar) | [migrations/009_recommendations.sql](../migrations/009_recommendations.sql) | ✅ Entregue |
| RPC de registro automático das recomendações do agente (com dedup) | [migrations/010_agent_recommendations.sql](../migrations/010_agent_recommendations.sql) | ✅ Entregue |
| Link do anúncio + métricas extras no overview/timeline | [migrations/011_overview_link_metrics.sql](../migrations/011_overview_link_metrics.sql) | ✅ Entregue |
| n8n: captura de snapshot (POST), timeline (GET), overview (GET) + recomendações (list/status/"Outros"/add) | [workspaces/Embaplan-Historico-Snapshots.json](../workspaces/Embaplan-Historico-Snapshots.json) | ✅ Entregue |
| Front: botão "📈 Histórico" por anúncio + modal (linha do tempo + recomendações ✅/❌/Outros) | [front.html](../front.html) | ✅ Entregue |
| Wiring: upload da planilha dispara a captura de snapshot | [workspaces/Embaplan-Upload-Planilha-Anuncios.json](../workspaces/Embaplan-Upload-Planilha-Anuncios.json) | ✅ Entregue (falta selecionar o ID do sub-fluxo no n8n) |
| Agente registrar as recomendações automaticamente ao analisar | [front.html](../front.html) → `registerAgentRecommendations()` → `embaplan-add-recommendations` | ✅ Entregue |
| Épico 3 (dashboard visual) | [front.html](../front.html) → overlay Dashboard (KPIs, top/bottom, lista de todos os anúncios, alertas, filtro por loja) | ✅ Entregue |
| Cartões do dashboard com título, status, tendência, link e botão de histórico; modal de detalhe com faixa de métricas + gráfico + recomendações | [front.html](../front.html) | ✅ Entregue |
| Carga incremental mês a mês (período no batch, reenvio idempotente) | [migrations/012_incremental_monthly.sql](../migrations/012_incremental_monthly.sql) | ✅ Entregue (banco) |
| Dashboard com abas: 🏠 Visão Geral (executiva) · 🚨 Alertas · 🏪 Comparar Lojas · 🎯 O que revisar hoje | [front.html](../front.html) | ✅ Entregue |
| Home executiva (Receita/ROAS/ACOS, receita e ACOS por loja, top + críticas) | [front.html](../front.html) → `renderHome()` | ✅ Entregue |
| Painel de Alertas (ACOS alto, CTR baixo, sem conversão, queda, escala, destaque) | [front.html](../front.html) → `renderAlertas()` | ✅ Entregue |
| Comparar Lojas — benchmark do mesmo produto entre lojas + risco de leilão interno | [front.html](../front.html) → `renderComparar()` / `auctionRisk()` | ✅ Entregue |
| "O que revisar hoje" — fila priorizada (problemas/oportunidades/escaláveis + impacto) | [front.html](../front.html) → `renderOportunidades()` | ✅ Entregue |
| Dashboard como tela inicial (abre 1x por sessão do navegador) | [front.html](../front.html) → `startApp()` | ✅ Entregue |
| Posicionamento multi-lojas (cobertura × canibalização) na resposta do agente | prompt do Agente IA (n8n) → REGRA 2.1 | ✅ Entregue |
| Quantificar impacto financeiro (investimento estimado, retorno, ROI) por recomendação | prompt do Agente IA (n8n) → REGRA 2.2 + template Ação Corretiva | ✅ Entregue |
| Resposta em formato "Resumo Executivo" (Situação/Motivo/Ação/Impacto) | prompt do Agente IA (n8n) → REGRA 2.3 + template do card | ✅ Entregue |

### 0.0 Carga incremental mês a mês (Richard)
O modelo de snapshots **já é append-only**: cada upload cria um *batch* e a timeline soma todos os batches — então **basta enviar o mês novo** (ex.: só "março"), sem reprocessar jan+fev. A migration `012` adiciona o campo `periodo` (mês de referência) e a RPC `sameka_embaplan_create_month_batch(... p_periodo, p_replace)`: reenviar o mesmo mês **substitui** aquele batch (idempotente) em vez de duplicar. **Passo manual no n8n:** trocar a chamada de `sameka_embaplan_create_batch` por `sameka_embaplan_create_month_batch` no fluxo de captura, passando o mês de referência da planilha.

### 0.1 Wiring do gatilho — ✅ implementado
O fluxo `Embaplan - Upload Planilha Anuncios` agora, após **"Atualizar Planilha Embaplan"**, executa o sub-fluxo `Consultar Planilha Inteligente` (aba "Dados Brutos"), extrai `produtos[]` em *Preparar Captura* e faz `POST` para `embaplan-capture-snapshot`. A resposta ao usuário sai em paralelo (não espera a captura). **Único passo manual:** no n8n, abrir o nó *Obter Sumário (Sub-fluxo)* e selecionar o workflow do sub-fluxo (placeholder `REPLACE_WITH_SUBFLUXO_WORKFLOW_ID`).

### 0.2 Configuração necessária (Supabase + n8n)
1. Rodar `008_analysis_snapshots.sql`, `009_recommendations.sql`, `010_agent_recommendations.sql`, `011_overview_link_metrics.sql` e `012_incremental_monthly.sql` no SQL Editor do Supabase.
2. No n8n, criar a credencial **HTTP Header Auth** `Supabase Service` (`apikey` + `Authorization: Bearer <service_role>`) e ajustar `SUPABASE_URL` nos nós *Config* / *Parse Query* do workflow de histórico (placeholders `REPLACE_WITH_SUPABASE_CRED_ID` e `REPLACE_WITH_PROJECT`).
3. Importar e ativar o workflow `Embaplan-Historico-Snapshots.json` (expõe `embaplan-ad-timeline`, `embaplan-overview`, `embaplan-recommendations`, `embaplan-recommendation-status`, `embaplan-user-change`, `embaplan-add-recommendations` — todos já consumidos pelo front).

### 0.3 Blocos de prompt prontos para o Agente IA (Fase 3)
Cole estes blocos no prompt do agente (n8n) para atender os pontos de **posicionamento multi-lojas**, **impacto financeiro** e **resposta objetiva**:

**A) Posicionamento multi-lojas (cobertura × canibalização):**
```
Ao encontrar anúncios do MESMO produto em lojas diferentes, NÃO trate como
canibalização automaticamente. Primeiro avalie: participação total no
marketplace, ganho de exposição e dominância de página. Só sinalize risco se
houver indício de leilão interno (mesmo público, CPC subindo). Prefira dizer:
"Esses anúncios aumentam a cobertura do marketplace, porém há risco de leilão
interno (ACOS médio X%)." em vez de "esses anúncios competem".
```

**B) Quantificar impacto financeiro (toda recomendação):**
```
Toda recomendação DEVE conter, quando recomendar mexer em verba/lance:
- Investimento estimado (ex.: "Aumentar orçamento diário em R$ 15")
- Potencial de retorno (ex.: "Receita +R$ 300 a R$ 500/mês")
- ROI esperado (ex.: "ROI estimado de 8x")
Baseie os números no ROAS/ACOS atuais do próprio anúncio.
```

**C) Formato "Resumo Executivo" (resposta objetiva):**
```
Responda de forma curta e direta, neste formato por campanha:
Situação: 🟢/🟡/🔴 <uma linha>
Motivo: <ROAS, ACOS — máx. 2 métricas>
Ação: <1 ação principal>
Impacto: <+X vendas/mês ou +R$ Y>
Evite parágrafos longos.
```

---

## 1. Resumo Executivo

O Agente Embaplan hoje faz **micro-auditoria técnica de anúncios** (Shopee, Mercado Livre, Amazon, Shein) a partir de uma planilha consolidada, classifica cada anúncio (🚀 Escalável / ⏳ Maturação / ⚠️ Gargalo / 🛑 Ralo) e entrega cards de campanha com ações corretivas. Funciona bem como **auditoria pontual (snapshot)**, mas ainda não tem:

- **Linha do tempo / memória por anúncio** → cada upload de planilha não vira histórico; não dá para ver se um anúncio melhorou ou piorou, nem se a sugestão do agente deu certo.
- **Acompanhamento de execução** → não registra se a recomendação foi feita (✅) ou descartada (❌).
- **Visualização** → tudo é texto; falta dashboard com ranking, insights e alertas.
- **Visão de portfólio** → analisa anúncio/loja isolados; não otimiza a venda do conjunto de bases nem trata canibalização vs. ticket médio.
- **Projeção financeira** → recomenda "investir mais" sem mostrar o investimento estimado e o retorno esperado.
- **Objetividade** → respostas longas e prolixas.

Este documento organiza essas melhorias em **7 épicos**, com requisitos funcionais, mudanças técnicas (front-end, n8n e banco) e critérios de aceite, além de um **roadmap em 3 fases**.

---

## 2. Contexto / Arquitetura Atual

| Camada | Componente | Papel |
|--------|-----------|-------|
| Front-end | `front.html` | Chat single-page (marca Embaplan), login/papéis (admin/viewer), sessões, histórico, upload de planilha, render de cards. Consome webhooks n8n. |
| Orquestração | `Embaplan - Agent IA` | Agente RAG principal. Prompt: "Consultor Executivo e Estrategista Sênior de Performance". Usa sub-fluxo + base RAG. |
| Dados | `Sub-fluxo Consultar Planilha Inteligente` | Lê Google Sheets (abas "Dados Brutos" e "Dashboard Simplificado") e retorna `SUMARIO_PRE_CALCULADO` com métricas prontas. |
| Conhecimento | `Embaplan - RAG` + base de documentos | Playbooks/boas práticas de ads consultados antes de recomendar. |
| Ingestão | `Upload Planilha Anuncios` | Sobe `.xlsx` para o Google Drive. |
| Sessões | `Chat-GET-Sessions / GET-History / DELETE-Session / prune` | CRUD de conversa. |
| Persistência | Supabase (Postgres) | `sameka_users` (papéis, empresa, áreas de cobertura), `sameka_chat_message` (histórico com `user_id`). Migrations `001`–`007`. |

**Métricas que o agente já calcula por anúncio e por linha de produto:** Vendas, Receita, Lucro, Investimento Ads, ACOS, CTR, Conversão, ROAS, ROI incremental sobre ads, Margem Líquida, Custo por Venda, Ticket Médio, Saúde 0–10.

**Limitação central:** cada análise é "stateless" — não existe uma entidade persistida de *Análise/Recomendação* que permita histórico, comparação e acompanhamento.

---

## 3. Objetivos e Métricas de Sucesso

### Objetivos
1. Transformar o agente de **auditor pontual** em **acompanhante de evolução** (memória + comparação).
2. Dar **visibilidade visual** (dashboard, ranking, insights, alertas).
3. Otimizar o **portfólio inteiro de bases**, não anúncios isolados — tratando canibalização, ticket médio e competição entre lojas.
4. Tornar recomendações de investimento **acionáveis e financeiramente justificadas** (forecast).
5. Tornar as respostas **mais objetivas e instrutivas**.

### Métricas de Sucesso (KPIs do produto)
| KPI | Baseline | Meta |
|-----|----------|------|
| % de recomendações com status registrado (✅/❌/outro) | 0% | ≥ 70% |
| Tempo para o usuário entender "o que mudou desde a última análise" | N/A (manual) | ≤ 10s (visual) |
| % de respostas dentro do limite de objetividade definido | — | ≥ 90% |
| ACOS médio do portfólio (tendência) | atual | ↓ ao longo de N rodadas |
| Lucro líquido total das bases acompanhadas | atual | ↑ trimestral |

---

## 4. Épicos / Features

### 🟥 Épico 1 — Linha do Tempo do Anúncio (Histórico Versionado por Upload)
**Pedido do usuário:** *"Quero ver o histórico dos anúncios; toda vez que sobe a planilha ele incrementa um histórico, atualiza os valores e cria uma linha do tempo para visualmente entender se melhorou ou piorou, e ver se as sugestões do agente deram certo ou não."* (+ *"salvar a análise para comparação... ter como contexto para as próximas análises"*)

**Problema:** o agente reanalisa do zero a cada rodada e não guarda o estado anterior de cada anúncio. Não há como ver evolução nem medir se uma recomendação funcionou.

**Solução:** o **upload da planilha vira o gatilho do histórico**. A cada upload, o sistema captura um **snapshot versionado de TODOS os anúncios** (não só os analisados), incrementando a linha do tempo. Cada anúncio passa a ter uma **timeline** com seus pontos no tempo, deltas entre versões e a indicação visual de evolução.

#### 1.A — Gatilho: cada upload = um ponto na linha do tempo
- RF1.1 — Ao concluir o upload (`POST /webhook/embaplan-upload-planilha`), o fluxo lê a planilha recém-enviada e **grava um snapshot por anúncio** (loja + `indice` + produto), com data/hora e o número da **versão** (rodada) auto-incrementado.
- RF1.2 — O snapshot guarda todas as métricas: Vendas, Receita, Lucro, Investimento Ads, ACOS, CTR, Conversão, ROAS, ROI, Margem Líquida, Ticket Médio, Saúde 0–10 e o status classificado (🚀/⏳/⚠️/🛑).
- RF1.3 — "Atualiza os valores": o **estado atual** (current) de cada anúncio sempre reflete a última versão; as versões anteriores ficam preservadas como histórico (append-only, nunca sobrescreve).
- RF1.4 — Cada upload recebe um rótulo opcional (ex.: "Semana 23", "Pós-ajuste de lance") para facilitar a leitura da timeline.

#### 1.B — Visualização da evolução (melhorou / piorou)
- RF1.5 — **Timeline por anúncio**: gráfico/linha do tempo mostrando a evolução de uma métrica selecionável (ACOS, Lucro, ROAS, Conversão, Saúde 0–10) entre uploads.
- RF1.6 — **Delta entre versões**: `ACOS 9,2% → 7,5% (−1,7pp) ✅ melhorou` por par de pontos consecutivos.
- RF1.7 — **Selo de tendência** por anúncio: 🟢 evoluindo / 🟡 estável / 🔴 piorando, baseado na variação de Saúde 0–10 e Lucro entre as últimas N versões.
- RF1.8 — Marcadores na timeline: cada ponto exibe data, versão e (quando houver) o evento "recomendação X aplicada aqui" para correlacionar causa→efeito.

#### 1.C — "As sugestões deram certo?" (correlação recomendação → resultado)
- RF1.9 — Cada recomendação registrada (ver Épico 2) fica **ancorada à versão** em que foi feita. Na versão seguinte, o sistema compara as métricas-alvo e marca o resultado: **✅ funcionou / ➖ neutro / ❌ piorou**.
- RF1.10 — Resumo de eficácia: "Das 8 recomendações aplicadas, 5 melhoraram o ACOS, 2 neutras, 1 piorou."
- RF1.11 — O agente **carrega os últimos N snapshots + status das recomendações** como contexto antes de recomendar de novo (não repete o que já deu certo; revisita o que piorou).

**Mudanças técnicas**
- **Banco (nova migration `008_analysis_snapshots.sql`):**
  - `embaplan_upload_batch` (`id`, `user_id`, `rotulo`, `arquivo_nome`, `created_at`) — uma linha por upload (= versão/rodada).
  - `embaplan_analysis_snapshot` (`id`, `batch_id` FK, `loja`, `produto`, `anuncio_indice`, `metrics_jsonb`, `status`, `saude`, `lucro`, `acos`, `created_at`). Chave de série temporal: (`loja`,`produto`,`anuncio_indice`,`batch_id`). Índices para puxar a timeline e o "último por anúncio".
- **n8n — captura no upload:** estender o fluxo `Embaplan - Upload Planilha Anuncios`. Após "Atualizar Planilha Embaplan", adicionar: (1) reuso do parser do `Sub-fluxo Consultar Planilha Inteligente` para gerar o `SUMARIO_PRE_CALCULADO`; (2) nó "Criar Batch" (INSERT em `embaplan_upload_batch`); (3) nó "Gravar Snapshots" (INSERT em lote, um por anúncio). Assim o histórico cresce **mesmo sem ninguém perguntar nada ao agente**.
- **n8n — leitura:** novo webhook `embaplan-ad-timeline` (GET por loja/produto/`indice`) que devolve a série de pontos para o gráfico, e os deltas/tendência.
- **n8n — contexto do agente:** nó "Carregar Histórico" antes da análise (SELECT últimos N snapshots + status de recomendações) injetado no prompt.
- **Prompt:** consumir o bloco "HISTÓRICO" e reportar **deltas e tendência** em vez de números absolutos isolados; correlacionar recomendações anteriores com o resultado observado.
- **Front:** componente de timeline por anúncio (gráfico de linha simples), selos de tendência, e o "antes → depois" nos cards. (Detalhe visual consolidado no Épico 3.)

**Critérios de aceite**
- Subir a planilha 2x gera 2 versões; a timeline de um anúncio mostra os 2 pontos e o delta entre eles, sem perder a versão antiga.
- Cada anúncio exibe selo 🟢/🟡/🔴 coerente com a variação real.
- Uma recomendação feita na versão *v* aparece marcada ✅/➖/❌ comparando *v* com *v+1*.
- O agente não repete recomendação que já deu certo e revisita as que pioraram.

---

### 🟥 Épico 2 — Acompanhamento de Recomendações (Checklist Executável)
**Pedido do usuário:** *"Marcar com um check ou cancel cada um dos tópicos que o agente recomendou e ir registrando esses históricos... e ter um input de 'outros' para escrever uma alteração que não foi o que o agente sugeriu, para ele saber disso."*

**Problema:** recomendações são texto solto; ninguém sabe o que foi executado.

**Solução:** cada ação corretiva vira um **item de checklist persistido** com estado e a possibilidade de o usuário registrar uma ação alternativa ("outros").

**Requisitos funcionais**
- RF2.1 — Cada ação corretiva recebe um ID estável e botões **✅ Feito / ❌ Descartado / ⏳ Pendente** no front.
- RF2.2 — Campo **"Outros"**: o usuário descreve uma alteração que fez por conta própria; isso é salvo e vira contexto para o agente.
- RF2.3 — Na próxima análise, o agente **considera os status** (não re-sugere o que foi descartado sem nova justificativa; valida se o "feito" surtiu efeito nas métricas).
- RF2.4 — Histórico de recomendações por anúncio (timeline: o que foi sugerido, quando, status, resultado).

**Mudanças técnicas**
- **Banco (`009_recommendations.sql`):** `embaplan_recommendation` (`id`, `snapshot_id`, `anuncio_indice`, `texto`, `prioridade`, `status` enum `pendente|feito|descartado`, `nota_usuario`, `updated_at`).
- **n8n:** webhook novo `embaplan-recommendation-status` (PATCH) para atualizar status/nota; o sub-fluxo de salvar análise também grava as ações como recomendações.
- **Front:** render dos cards de ação com toggles; chamada ao webhook ao clicar; campo "Outros" por anúncio.
- **Prompt:** seção "RECOMENDAÇÕES ANTERIORES E STATUS" — regras para reagir a `feito`/`descartado`/`outros`.

**Critérios de aceite**
- Marcar uma ação como ✅ persiste e aparece na próxima sessão.
- Texto em "Outros" é citado/considerado pelo agente na rodada seguinte.

---

### 🟧 Épico 3 — Dashboard Visual de Análises
**Pedido do usuário:** *"Adicionar dashboard visual das análises — os primeiros/melhores anúncios, com ACOS altos também (os ruins). Insights, avisos."*

**Problema:** toda a inteligência está presa em texto longo; falta leitura rápida.

**Solução:** painel visual (aba "Dashboard" no front) alimentado pelo `SUMARIO_PRE_CALCULADO` e pelos snapshots.

**Requisitos funcionais**
- RF3.1 — **Ranking Top**: melhores anúncios por lucro/ROAS (🚀) e piores por ACOS alto / status Ralo (🛑).
- RF3.2 — **Cards de KPI** do portfólio: Receita, Lucro, ACOS médio, ROAS, Ticket Médio, nº de anúncios por status.
- RF3.3 — **Insights automáticos**: frases curtas geradas a partir das regras (ex.: "3 anúncios da Base A4 estão em Ralo, somando R$ X de prejuízo potencial").
- RF3.4 — **Avisos/Alertas**: anúncios que pioraram desde o último snapshot, ACOS acima do teto, lucro negativo.
- RF3.5 — Filtros por **loja** e por **produto/base**.
- RF3.6 — **Linha do tempo embutida**: ao abrir um anúncio, exibir o gráfico de evolução (Épico 1) com os pontos de cada upload e os marcadores de recomendação ✅/➖/❌.
- RF3.7 — **Seletor de versões/uploads**: comparar duas rodadas quaisquer (ex.: Semana 21 vs. Semana 23).

**Mudanças técnicas**
- **Front:** nova view com gráficos leves (sem dependência pesada — ex.: barras/sparklines em SVG/Canvas ou Chart.js via CDN). Reaproveitar `SUMARIO_PRE_CALCULADO` que já vem pronto.
- **n8n:** webhook `embaplan-dashboard` retornando JSON agregado (top/bottom, KPIs, alertas) — pode derivar do sumário + snapshots (tendência).
- **Sem novas tabelas** além das dos Épicos 1–2.

**Critérios de aceite**
- Em 1 tela o usuário vê os 5 melhores, os 5 piores (ACOS), KPIs e ≥ 3 insights/alertas.
- Alertas refletem variação real vs. snapshot anterior.

---

### 🟧 Épico 4 — Inteligência de Portfólio: Canibalização × Ticket Médio
**Pedido do usuário:** *"Entender que muitos anúncios do mesmo produto aumentam o ticket médio; o ML quer que todos vendam, mas não podemos ter anúncios que façam perder dinheiro. Entender que os anúncios podem se impulsionar e fazer leilões de ofertas na plataforma."*

**Problema:** o agente trata canibalização como algo a evitar, sem considerar o efeito positivo de cobertura/ticket médio nem a dinâmica de leilão dos marketplaces.

**Solução:** evoluir a análise de canibalização para um **balanço líquido de portfólio**: múltiplos anúncios são bons quando ampliam cobertura/ticket médio e ruins apenas quando destroem margem.

**Requisitos funcionais**
- RF4.1 — Classificar cada anúncio "extra" do mesmo produto como **Complementar** (amplia alcance/ticket, lucro > 0) ou **Predatório** (canibaliza e dá prejuízo).
- RF4.2 — Calcular **efeito agregado**: somar lucro do conjunto de anúncios do produto vs. cenário de consolidar; só recomendar pausar quando o conjunto perde dinheiro.
- RF4.3 — Considerar dinâmica de **leilão/impulsionamento**: anúncios podem competir entre si elevando custo; sinalizar quando dois anúncios da mesma base disputam o mesmo lance/keyword.
- RF4.4 — Recomendação clara: "manter por cobertura", "diferenciar ângulo/keyword", ou "pausar (predatório)".

**Mudanças técnicas**
- **Prompt:** substituir a regra atual de canibalização por uma **árvore de decisão de portfólio** (complementar vs. predatório) e incluir o conceito de leilão/lance entre anúncios da mesma base.
- **Sub-fluxo:** opcionalmente expor `keyword`/`lance` por anúncio, se disponível na planilha, para detectar disputa interna.

**Critérios de aceite**
- O agente não recomenda pausar um anúncio "extra" lucrativo só por existir mais de um.
- Identifica e nomeia anúncios predatórios (mesma base disputando lance e dando prejuízo).

---

### 🟧 Épico 5 — Maximizar Venda do Portfólio de Bases (Comparação entre Lojas)
**Pedido do usuário:** *"Como faço para aumentar a venda de todas as bases sem me importar com a competição entre anúncios e lojas? A comparação entre lojas tem que entender isso."*

**Problema:** a regra atual **segrega rigidamente por loja** e proíbe consolidar — ótimo para evitar erro numérico, mas impede a visão "crescer o todo".

**Solução:** adicionar um **modo de comparação de portfólio cross-loja** (sem misturar números de receita por loja indevidamente) focado em "onde cada base vende melhor e como crescer a soma".

**Requisitos funcionais**
- RF5.1 — Modo explícito "Comparar lojas / portfólio": mostra a mesma base em cada loja lado a lado (ACOS, conversão, ticket, lucro) **sem somar receitas como se fosse uma loja só**.
- RF5.2 — Recomendar **alocação de verba entre lojas** para a mesma base (onde o real investido rende mais lucro).
- RF5.3 — Tratar competição loja×loja como **soma positiva**: objetivo é maximizar lucro total das bases, não eleger uma loja vencedora.
- RF5.4 — Manter a salvaguarda atual (não inventar consolidado global quando o filtro pediu uma única loja).

**Mudanças técnicas**
- **Prompt:** nova seção "MODO PORTFÓLIO / CROSS-LOJA" que coexiste com a segregação atual, com regras claras de quando comparar vs. quando segregar.
- **Sub-fluxo/Dashboard:** visão "mesma base em N lojas".

**Critérios de aceite**
- Ao pedir "como vender mais todas as bases", o agente responde com plano de portfólio (alocação por loja) sem violar a regra anti-soma indevida.

---

### 🟨 Épico 6 — Recomendações de Investimento com Forecast
**Pedido do usuário:** *"Quando falar para aumentar o investimento na campanha, deve trazer o investimento estimado e o valor que retornará."*

**Problema:** hoje o agente diz "teste mais verba" sem números.

**Solução:** toda recomendação de aumento de verba vem com **projeção investimento → retorno**, baseada nas métricas atuais (ROAS, conversão, ACOS) e em premissas explícitas.

**Requisitos funcionais**
- RF6.1 — Para cada recomendação de escalar, exibir: **investimento adicional sugerido (R$)**, **receita incremental estimada (R$)**, **lucro incremental estimado (R$)** e **ACOS/ROAS projetado**.
- RF6.2 — Mostrar as **premissas** (ex.: "mantendo ROAS atual de 13x e margem de 40%") e um **intervalo** (conservador / esperado) para não passar falsa precisão.
- RF6.3 — Alertar quando escalar tende a **degradar** o retorno (saturação/leilão) — nem todo aumento é linear.
- RF6.4 — Padronizar um bloco fixo "📈 Projeção de Investimento" no template de resposta.

**Mudanças técnicas**
- **Prompt:** fórmulas explícitas de projeção (ex.: `receita_incremental ≈ investimento_adicional × ROAS_atual × fator_saturação`; `lucro_incremental ≈ receita_incremental × margem − investimento_adicional`) e regra de exibir intervalo.
- Opcional: pré-cálculo da projeção no sub-fluxo para garantir consistência numérica (mesma estratégia já usada com o `SUMARIO_PRE_CALCULADO`).

**Critérios de aceite**
- Nenhuma recomendação de "investir mais" sai sem o bloco 📈 com R$ investido, R$ retorno e premissas.

---

### 🟨 Épico 7 — Objetividade e Tom Instrutivo
**Pedido do usuário:** *"Ser mais objetivo nas respostas e falar mais focado e instrutivo."*

**Problema:** o template atual é extenso (cards completos para todos os anúncios, validações verbosas).

**Solução:** modos de resposta + diretrizes de concisão, mantendo a precisão numérica.

**Requisitos funcionais**
- RF7.1 — **Modo Executivo (padrão)**: por anúncio, no máximo 1 linha de diagnóstico + top 3 ações priorizadas; detalhe completo só sob pedido ("modo detalhado").
- RF7.2 — Linguagem **instrutiva e imperativa** ("Faça X para reduzir o ACOS de 12% para ~8%"), sem repetir validações internas na saída.
- RF7.3 — Limite de tamanho por seção; números sempre que afirmar algo.
- RF7.4 — Mover validações aritméticas para "trabalho interno" (não imprimir na resposta).

**Mudanças técnicas**
- **Prompt:** introduzir `MODO_RESPOSTA = executivo|detalhado`, encurtar templates, remover instruções de "auto-validação visível".
- **Front:** toggle "Resumido / Detalhado" no input do chat.

**Critérios de aceite**
- Resposta padrão cabe em leitura rápida (diagnóstico + 3 ações por anúncio), sem perder os números-chave.

---

## 5. Roadmap (3 Fases)

> Priorização por **impacto × esforço**. Épicos 1, 2 e 7 desbloqueiam o resto.

### Fase 1 — Fundamentos (memória + objetividade)
- **Épico 7** (Objetividade) — só prompt/front, impacto imediato, baixo risco.
- **Épico 1** (Snapshots/Comparação) — base de dados para tudo que vem depois.
- **Épico 6** (Forecast de investimento) — só prompt/cálculo, alto valor percebido.

### Fase 2 — Execução e Visualização
- **Épico 2** (Checklist ✅/❌/Outros) — depende dos snapshots da Fase 1.
- **Épico 3** (Dashboard visual) — consome sumário + snapshots + recomendações.

### Fase 3 — Inteligência de Portfólio
- **Épico 4** (Canibalização × Ticket Médio / leilão).
- **Épico 5** (Maximizar portfólio / comparação entre lojas).

---

## 6. Mudanças Técnicas Consolidadas

| Camada | Itens novos |
|--------|-------------|
| **Banco (migrations)** | `008_analysis_snapshots.sql` (`embaplan_upload_batch` + `embaplan_analysis_snapshot`), `009_recommendations.sql` (+ índices). |
| **n8n — novos webhooks** | `embaplan-ad-timeline` (GET série temporal por anúncio), `embaplan-dashboard` (GET), `embaplan-recommendation-status` (PATCH). |
| **n8n — captura no upload** | Estender `Upload Planilha Anuncios`: após atualizar o arquivo, gerar `SUMARIO_PRE_CALCULADO`, criar `upload_batch` e gravar 1 snapshot por anúncio (gatilho da linha do tempo). |
| **n8n — novos nós/sub-fluxos** | "Carregar Histórico", "Salvar Recomendações", "Projeção de Investimento", "Avaliar Eficácia de Recomendação" (compara versão v vs v+1). |
| **Prompt do Agente IA** | Seções: Histórico/Deltas, Recomendações & Status, Portfólio/Canibalização, Cross-loja, Projeção de Investimento, Modos de Resposta. |
| **Front-end (`front.html`)** | Aba Dashboard, toggles ✅/❌ + campo "Outros" nos cards de ação, toggle Resumido/Detalhado, render de deltas/tendência. |

---

## 7. Riscos e Mitigações

| Risco | Mitigação |
|-------|-----------|
| Identificador de anúncio instável entre planilhas → quebra o histórico | Usar `indice` já prefixado por loja (`L2#47`); definir chave estável (loja+índice+título). |
| Forecast passar falsa certeza | Sempre mostrar premissas + intervalo conservador/esperado; alertar saturação. |
| Encurtar respostas e perder números obrigatórios | Modo Executivo mantém métricas-chave e top 3 ações; validação numérica continua interna. |
| Crescimento de dados de snapshots | Reter N versões por anúncio + arquivamento; índices adequados. |
| Comparação cross-loja reintroduzir soma indevida de receita | Manter salvaguarda atual; modo portfólio compara, não consolida receita. |

---

## 8. Fora de Escopo (por ora)
- Integração direta com APIs dos marketplaces (coleta automática de métricas) — hoje a fonte é a planilha.
- Automação de ações (alterar lance/verba direto na plataforma).
- Multiusuário colaborativo em tempo real no mesmo snapshot.

---

## 9. Perguntas em Aberto
1. A planilha expõe **keyword/lance por anúncio** (necessário para o Épico 4 detectar disputa interna)?
2. Qual a **periodicidade** de atualização da planilha (define a granularidade do histórico de evolução)?
3. Existe um **teto de ACOS** oficial por base/loja para calibrar alertas do dashboard?
4. O acompanhamento de recomendações é **por usuário** ou compartilhado pela equipe?
