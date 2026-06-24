# Plataforma Embaplan — Especificação (estado atual)

> Spec consolidado do sistema brownfield já implementado. Documenta as capacidades existentes como requisitos rastreáveis, servindo de baseline para evolução. Para novas features, criar specs próprios em `.specs/features/<feature>/`.

## Problem Statement

Analistas de tráfego que operam anúncios na Shopee recebem planilhas extensas de desempenho (ROAS, ACOS, lucro, conversão) e não conseguem, de forma ágil, identificar o que escalar, pausar ou otimizar — nem acompanhar a evolução de cada anúncio ao longo do tempo. A Embaplan converte essas planilhas em histórico versionado, dashboards, comparações e recomendações de IA com impacto financeiro em R$.

## Goals

- [ ] Ingerir planilhas mensais e manter histórico versionado por período (comparar antes/depois)
- [ ] Oferecer chat com agente IA que audita anúncios com dados reais (sem alucinar)
- [ ] Entregar dashboard com KPIs, alertas, comparação entre lojas, oportunidades e evolução
- [ ] Gerar e avaliar recomendações de otimização priorizadas com impacto em R$

## Out of Scope

| Feature                    | Reason                                                   |
| -------------------------- | -------------------------------------------------------- |
| Testes automatizados       | Não existem hoje; planejado em M3                        |
| Auth robusta no frontend   | Login local simplificado (admin/admin); endereçado em M2 |
| API oficial da Shopee      | Integração é via planilha + scraping de link             |
| Multi-marketplace completo | Citado nos prompts, não implementado                     |

---

## User Stories

### P1: Upload e versionamento de planilhas ⭐ MVP

**User Story**: Como analista, quero enviar a planilha mensal de anúncios para que o sistema registre uma versão histórica e capture os dados de cada anúncio.

**Why P1**: Sem ingestão de dados versionados não há análise nem histórico — é a base de tudo.

**Acceptance Criteria**:

1. WHEN o usuário envia um arquivo Excel/CSV THEN o sistema SHALL validar o formato e atualizar a planilha master (Google Sheets)
2. WHEN o upload é processado THEN o sistema SHALL criar um batch associado ao período (mês) e inserir um snapshot por anúncio
3. WHEN um upload do mesmo período já existe THEN o sistema SHALL substituir o batch anterior de forma idempotente
4. WHEN um novo batch é criado THEN o sistema SHALL purgar recomendações pendentes obsoletas

**Independent Test**: Enviar uma planilha de exemplo e verificar criação do batch e dos snapshots no banco.

---

### P1: Chat com agente IA ⭐ MVP

**User Story**: Como analista, quero conversar com um agente de IA que analisa meus anúncios usando dados reais para que eu receba auditorias e respostas confiáveis.

**Why P1**: É a principal interface de valor do produto.

**Acceptance Criteria**:

1. WHEN o usuário envia uma mensagem THEN o sistema SHALL responder via streaming usando o agente (Gemini) com as últimas 10 mensagens de contexto
2. WHEN o agente precisa de dados THEN o sistema SHALL consultar a planilha/métricas via tools (sem inventar dados)
3. WHEN há link Shopee no contexto THEN o sistema SHALL auditar o anúncio via a tool de análise de link
4. WHEN a resposta é gerada THEN o sistema SHALL renderizar Markdown e persistir a mensagem na sessão
5. WHEN ocorre erro de gateway (502/503/504/520-524) THEN o sistema SHALL recuperar a resposta consultando o histórico

**Independent Test**: Iniciar uma sessão, perguntar sobre um produto e verificar resposta com dados reais persistida no histórico.

---

### P1: Dashboard analítico ⭐ MVP

**User Story**: Como gestor, quero um painel com KPIs e alertas para identificar rapidamente anúncios críticos e oportunidades.

**Why P1**: Entrega visão executiva imediata sobre o desempenho.

**Acceptance Criteria**:

1. WHEN o usuário abre o painel THEN o sistema SHALL exibir KPIs (receita, lucro, ROAS médio, ACOS médio, nº de críticos) a partir de `embaplan-overview`
2. WHEN existe filtro de loja THEN o sistema SHALL recalcular os KPIs para a loja selecionada
3. WHEN há anúncios críticos (status ralo/gargalo OU lucro<0 OU ACOS>15% OU tendência piorando) THEN o sistema SHALL listá-los na aba Alertas
4. WHEN o usuário acessa Comparar THEN o sistema SHALL exibir benchmark entre lojas (melhores/piores por receita e ACOS)
5. WHEN o usuário acessa Evolução THEN o sistema SHALL carregar evolução do portfólio e mudanças detectadas

**Independent Test**: Abrir o painel com dados de exemplo e validar os 5 conjuntos de informação por aba.

---

### P2: Recomendações IA

**User Story**: Como analista, quero recomendações de otimização geradas por IA com impacto em R$ para priorizar ações.

**Why P2**: Agrega valor sobre a base analítica, mas depende dos dados (P1) existirem.

**Acceptance Criteria**:

1. WHEN o usuário solicita gerar recomendações THEN o sistema SHALL montar contexto do anúncio (atual + histórico + recs existentes) e gerar 2–5 sugestões com impacto em R$
2. WHEN recomendações são geradas THEN o sistema SHALL deduplicar contra as existentes antes de gravar
3. WHEN o usuário altera o status THEN o sistema SHALL registrar pendente/feito/descartado e nota do usuário
4. WHEN um novo batch chega THEN o sistema SHALL avaliar a efetividade das recomendações (funcionou/neutro/piorou) comparando a métrica-alvo entre batches

**Independent Test**: Gerar recomendações para um anúncio e verificar gravação com impacto e dedup.

---

### P2: Sessões e tags de chat

**User Story**: Como usuário, quero organizar minhas conversas em sessões e tags para encontrar análises depois.

**Why P2**: Melhora usabilidade, não é pré-requisito do valor central.

**Acceptance Criteria**:

1. WHEN o usuário cria/seleciona uma sessão THEN o sistema SHALL listar e carregar o histórico correspondente
2. WHEN o usuário adiciona/remove uma tag THEN o sistema SHALL persistir a associação (idempotente) por usuário
3. WHEN o usuário renomeia/exclui uma tag THEN o sistema SHALL aplicar a mudança globalmente nas sessões do usuário
4. WHEN o usuário filtra por tag THEN o sistema SHALL exibir apenas as sessões correspondentes

**Independent Test**: Criar sessão, marcar com tag, filtrar e renomear a tag.

---

### P2: Detecção de mudanças e gestão de batches

**User Story**: Como analista, quero comparar versões e gerenciar batches para manter o histórico correto.

**Why P2**: Operação de manutenção sobre o histórico.

**Acceptance Criteria**:

1. WHEN o usuário compara dois batches THEN o sistema SHALL retornar deltas (adicionados/removidos/alterados)
2. WHEN o usuário lista batches THEN o sistema SHALL exibir período, rótulo, total de anúncios e contagem de recomendações
3. WHEN o usuário edita/exclui um batch THEN o sistema SHALL atualizar/remover em cascata os snapshots e ordenar por período (não por data de upload)

**Independent Test**: Editar o período de um batch e verificar reordenação cronológica.

---

### P3: Gestão de usuários (admin)

**User Story**: Como admin, quero gerenciar usuários e papéis para controlar o acesso.

**Why P3**: Necessário para operação multiusuário, mas não é o fluxo de valor diário.

**Acceptance Criteria**:

1. WHEN um admin lista usuários THEN o sistema SHALL retornar apenas usuários da empresa `embaplan`
2. WHEN um admin atualiza papel/dados (incl. estados/cidades) THEN o sistema SHALL persistir no metadata do usuário
3. WHEN um não-admin chama RPC admin THEN o sistema SHALL negar com erro de acesso (ERRCODE 42501)
4. WHEN um admin tenta excluir a própria conta THEN o sistema SHALL bloquear a operação

**Independent Test**: Como admin, atualizar o papel de um usuário e tentar auto-exclusão (deve falhar).

---

## Edge Cases

- WHEN a planilha tem formato/colunas inesperados THEN o sistema SHALL falhar de forma controlada sem corromper o histórico (hoje: parsing frágil — ver CONCERNS.md)
- WHEN números vêm como `"R$ 1.234,56"` ou `"7,5%"` THEN o sistema SHALL convertê-los corretamente
- WHEN dados mensais antigos são enviados após dados recentes THEN o sistema SHALL ordenar por período (calendário), não por data de upload
- WHEN o `localStorage` está bloqueado (iframe sandbox) THEN o sistema SHALL usar storage em memória e evitar loop de login
- WHEN a conexão cai THEN o front SHALL detectar offline (polling de `embaplan_health`) e indicar o status

---

## Requirement Traceability

| Requirement ID | Story                                     | Phase        | Status   |
| -------------- | ----------------------------------------- | ------------ | -------- |
| UPLOAD-01      | P1: Upload/versionamento                  | Implementado | Verified |
| UPLOAD-02      | P1: Upload/versionamento                  | Implementado | Verified |
| CHAT-01        | P1: Chat IA                               | Implementado | Verified |
| CHAT-02        | P1: Chat IA (tools/no-hallucination)      | Implementado | Verified |
| DASH-01        | P1: Dashboard                             | Implementado | Verified |
| DASH-02        | P1: Dashboard (alertas)                   | Implementado | Verified |
| REC-01         | P2: Recomendações IA                      | Implementado | Verified |
| REC-02         | P2: Recomendações (avaliação efetividade) | Implementado | Verified |
| TAG-01         | P2: Sessões e tags                        | Implementado | Verified |
| BATCH-01       | P2: Detecção de mudanças / batches        | Implementado | Verified |
| ADMIN-01       | P3: Gestão de usuários                    | Implementado | Verified |
| SEC-01         | P1/P3: Auth real + webhooks protegidos    | Pending (M2) | Pending  |
| TEST-01        | Qualidade: testes automatizados           | Pending (M3) | Pending  |

**ID format:** `[CATEGORIA]-[NÚMERO]`
**Coverage:** 13 requisitos — 11 implementados/verificados, 2 pendentes (segurança e testes) ⚠️

---

## Success Criteria

- [ ] Usuário consegue enviar planilha e ver KPIs do mês em < 2 minutos
- [ ] Chat responde com dados reais do anúncio consultado (sem números inventados)
- [ ] Recomendações geradas trazem impacto em R$ e não duplicam existentes
- [ ] Histórico de um anúncio mostra evolução correta por período
- [ ] (M2) Acesso ao front exige autenticação real; webhooks de escrita exigem token
