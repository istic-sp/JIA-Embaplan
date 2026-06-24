# Upload em múltiplas datas (anteriores/posteriores) — Especificação

**Feature slug:** `upload-multidatas`
**Status:** Draft

## Problem Statement

Ao enviar uma planilha de anúncios, o usuário escolhe uma "Data de referência" (`periodo`). Hoje, ao tentar adicionar planilhas com datas anteriores ou posteriores às já existentes, a planilha "não é adicionada corretamente": ou ela substitui um batch existente, ou cai na data de hoje em vez da data escolhida, quebrando a ordem cronológica. O usuário possui 2 planilhas inseridas e precisa adicionar outras em qualquer data (passado ou futuro) sem sobrescrever as existentes e mantendo a linha do tempo correta.

## Goals

- [ ] Cada upload com uma data de referência distinta cria um batch distinto, sem afetar batches de outras datas
- [ ] Reenviar a mesma data substitui (idempotente) apenas o batch daquela data — comportamento já desejado
- [ ] A `periodo` escolhida no front chega íntegra até a RPC `embaplan_create_month_batch` (nunca é perdida nem trocada por "hoje")
- [ ] A linha do tempo e o dashboard ordenam pela data de referência (`periodo`), não pela hora do upload

## Out of Scope

| Feature                                     | Reason                                                               |
| ------------------------------------------- | -------------------------------------------------------------------- |
| Autenticação/`user_id` real no upload       | Pertence ao M2 (segurança); aqui `user_id` segue NULL                |
| Edição em massa de batches existentes       | Já coberto por `embaplan_update_batch`/`embaplan_delete_batch` (018) |
| Importação de múltiplos arquivos de uma vez | Mantém-se 1 arquivo por upload                                       |

---

## User Stories

### P1: Adicionar planilha em data anterior ou posterior ⭐ MVP

**User Story**: Como analista, quero enviar uma planilha escolhendo uma data de referência (passada ou futura) para que ela vire um novo ponto na linha do tempo sem apagar as planilhas já enviadas.

**Why P1**: É exatamente a falha relatada; sem isso o histórico não pode ser construído corretamente.

**Acceptance Criteria**:

1. WHEN o usuário envia uma planilha com `periodo` = data X (diferente das existentes) THEN o sistema SHALL criar um novo batch com `periodo` = X e preservar todos os batches de outras datas
2. WHEN o `periodo` escolhido é anterior a batches existentes THEN o sistema SHALL inserir o batch na posição cronológica correta (ordenação por `periodo`)
3. WHEN o `periodo` escolhido é posterior THEN o sistema SHALL inseri-lo como o mais recente por data, e o dashboard SHALL refletir esse batch como "atual"
4. WHEN o usuário reenvia a MESMA data THEN o sistema SHALL substituir somente o batch daquela data (idempotência), sem afetar os demais

**Independent Test**: Com 2 batches existentes (ex.: 10/05 e 10/06), enviar uma planilha 10/04 e outra 10/07; verificar que passam a existir 4 batches ordenados 04→05→06→07 e que nenhum foi apagado.

---

### P1: Integridade da data de referência ponta a ponta ⭐ MVP

**User Story**: Como sistema, preciso garantir que a `periodo` enviada pelo front chegue íntegra à RPC, para nunca gravar uma planilha na data errada.

**Why P1**: A perda silenciosa da `periodo` é a causa raiz do bug (cai em "hoje" + substitui).

**Acceptance Criteria**:

1. WHEN o front envia `periodo` no upload THEN o workflow de upload SHALL repassá-la sem perda até o webhook `embaplan-capture-snapshot`
2. WHEN o `embaplan-capture-snapshot` recebe `periodo` THEN a chamada a `embaplan_create_month_batch` SHALL usar exatamente essa `periodo`
3. WHEN a `periodo` chega vazia/nula na captura THEN o sistema SHALL falhar de forma explícita (não gravar) em vez de assumir a data de hoje e substituir um batch existente
4. WHEN um batch é criado THEN `created_at` SHALL ser igual ao `periodo` (à meia-noite) para manter a cronologia (já previsto na migration 019)

**Independent Test**: Enviar upload com `periodo`=2026-04-10 e inspecionar no banco que o batch criado tem `periodo`=2026-04-10 (não a data atual).

---

### P2: Garantia de unicidade por data no banco

**User Story**: Como mantenedor, quero que o banco garanta no máximo um batch por data de referência, para que duplicidades não corrompam a linha do tempo.

**Why P2**: Defesa em profundidade; o comportamento de replace já tende a manter unicidade, mas sem constraint pode haver duplicatas herdadas.

**Acceptance Criteria**:

1. WHEN dois batches teriam o mesmo `periodo` THEN o banco SHALL impedir a duplicidade (constraint/índice único) ou o replace SHALL garantir unicidade
2. WHEN a migration é aplicada e já existem duplicatas THEN ela SHALL consolidar/limpar antes de criar a restrição (sem perder o batch mais recente)

**Independent Test**: Tentar inserir dois batches com o mesmo `periodo` e confirmar que o resultado final tem apenas um.

---

### P1: Validação de esquema da planilha (gate antes de substituir) ⭐ MVP

**User Story**: Como mantenedor, quero que o sistema bloqueie planilhas fora do padrão ANTES de substituir a oficial, para não corromper os dados nem registrar capturas vazias.

**Why P1**: Uma planilha com aba/colunas diferentes (ex.: `Sheet1` com 5 colunas) sobrescreve a oficial e gera `produtos[]` vazio, quebrando a linha do tempo.

**Acceptance Criteria**:

1. WHEN a planilha enviada NÃO contém a aba padrão `Base e QC` com exatamente as 22 colunas esperadas THEN o sistema SHALL bloquear o upload ANTES de substituir o arquivo no Google Drive
2. WHEN o upload é bloqueado THEN a planilha oficial SHALL permanecer inalterada e o erro SHALL listar colunas faltando/inesperadas
3. WHEN a planilha está no padrão THEN o fluxo SHALL prosseguir normalmente

**Independent Test**: Enviar `PLANILHASHOPEE29.04 A 11.06.xlsx` (1 aba, 5 colunas) e confirmar bloqueio com mensagem clara, sem alterar a oficial; enviar a planilha correta e confirmar sucesso.

---

### P1: Não substituir a base do agente com planilha de data anterior ⭐ MVP

**User Story**: Como usuário, quero que enviar uma planilha de uma data ANTERIOR não substitua a base atual do agente (Drive), para não quebrar as respostas com dados desatualizados — mas ela ainda deve entrar no histórico.

**Why P1**: O agente responde lendo a planilha "ao vivo" no Drive. Sobrescrevê-la com dados antigos corromperia as respostas.

**Acceptance Criteria**:

1. WHEN a `periodo` enviada for MENOR que a data mais recente já registrada THEN o sistema SHALL NOT substituir o arquivo no Drive
2. WHEN a `periodo` enviada for MAIOR OU IGUAL à mais recente THEN o sistema SHALL substituir o Drive (base do agente)
3. WHEN o upload é retroativo (não atualiza o Drive) THEN o snapshot daquela data SHALL ser montado a partir do ARQUIVO ENVIADO (não do Drive) e entrar na linha do tempo
4. WHEN o upload conclui THEN o front SHALL informar se a base foi atualizada ou se foi apenas registro histórico

**Independent Test**: Com a base em 2026-06, enviar planilha de 2026-04 → Drive inalterado, histórico ganha 2026-04 com os dados daquele arquivo, front avisa "não alterou a base atual".

---

## Edge Cases

- WHEN `periodo` vem como `YYYY-MM` (mês) em vez de `YYYY-MM-DD` THEN o sistema SHALL normalizar para o dia 1 do mês (comportamento atual mantido)
- WHEN o usuário não altera o campo de data (default = hoje) e envia duas planilhas no mesmo dia THEN a segunda SHALL substituir a primeira (mesma data = idempotente) — comportamento esperado, comunicado na UI
- WHEN o `periodo` é uma data futura THEN o sistema SHALL aceitar normalmente (permitido por requisito)
- WHEN a captura falha por `periodo` ausente THEN o front SHALL exibir erro claro ("data de referência ausente") e não reportar sucesso

---

## Requirement Traceability

| Requirement ID | Story                                            | Phase  | Status  |
| -------------- | ------------------------------------------------ | ------ | ------- |
| UPDATE-01      | P1: Adicionar em datas distintas                 | Design | Pending |
| UPDATE-02      | P1: Ordenação cronológica por periodo            | Design | Pending |
| UPDATE-03      | P1: Replace só na mesma data                     | Design | Pending |
| FLOW-01        | P1: periodo íntegra no workflow de upload        | Design | Pending |
| FLOW-02        | P1: periodo usada na RPC create_month_batch      | Design | Pending |
| FLOW-03        | P1: falhar se periodo ausente (não assumir hoje) | Design | Pending |
| UNIQ-01        | P2: unicidade por data no banco                  | Design | Pending |
| SCHEMA-01      | P1: validar esquema antes de substituir a oficial | Done   | T7      |
| DRIVE-01       | P1: não substituir o Drive com data anterior      | Done   | T8      |

**ID format:** `[CATEGORIA]-[NÚMERO]`
**Coverage:** 9 requisitos

---

## Success Criteria

- [ ] A partir de 2 batches, é possível adicionar batches em datas anteriores e posteriores e todos coexistem, ordenados por data
- [ ] Nenhum batch de outra data é apagado ao adicionar uma nova data
- [ ] A `periodo` gravada no banco é sempre a escolhida no front
- [ ] Reenviar a mesma data substitui apenas aquele dia
- [ ] Upload com `periodo` ausente falha de forma visível, sem corromper dados
