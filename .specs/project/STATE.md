# State

**Last Updated:** 2026-06-23
**Current Work:** Feature `upload-multidatas` — T1–T5 implementadas; aguardando UAT (T6)

---

## Recent Decisions (Last 60 days)

### AD-001: Documentar o projeto existente com spec-driven (2026-06-23)

**Decision:** Gerar os 7 docs de brownfield em `.specs/codebase/`, os docs de projeto (`PROJECT.md`, `ROADMAP.md`, `STATE.md`) e um spec consolidado do sistema atual em `.specs/features/plataforma-atual/spec.md`.
**Reason:** Projeto brownfield sem documentação formal; estabelecer base de conhecimento antes de novas features.
**Trade-off:** O spec consolida o sistema inteiro em vez de uma feature isolada (o estado atual já está implementado).
**Impact:** Próximas features devem seguir o fluxo Specify → (Design) → (Tasks) → Execute usando este baseline.

### AD-002: ROADMAP reflete estado atual como M1 COMPLETE (2026-06-23)

**Decision:** Marcar as capacidades existentes como M1 (COMPLETE) e derivar M2 (Segurança) e M3 (Qualidade) do CONCERNS.md.
**Reason:** As funcionalidades já estão em produção via n8n; os próximos marcos são melhorias.
**Trade-off:** Nenhum significativo.
**Impact:** Prioriza segurança e testes como próximos passos.

### AD-003: Upload de data antiga NÃO substitui a base do agente no Drive (2026-06-23)

**Decision:** O Drive (fonte ao vivo do agente) só é substituído quando a `periodo` enviada é >= à mais recente registrada. Datas anteriores vão APENAS para o histórico/linha do tempo. A captura do snapshot passou a usar SEMPRE os dados do arquivo enviado (modo `rows_diretas` no sub-fluxo `Consultar Todas as Abas`), eliminando também a dependência de sincronização do Drive (removidos `Aguardar Sincronização` e `Definir Aba e Termo`).
**Reason:** Subir uma planilha antiga sobrescrevendo o Drive quebraria as respostas do agente (dados desatualizados).
**Trade-off:** A consolidação do snapshot reusa o sub-fluxo via passagem de itens (`_modo`); a captura nunca mais lê o Drive.
**Impact:** Front mostra mensagem distinta (base atualizada vs. só histórico) lendo `atualizou_base` da resposta.

---

## Active Blockers

_Nenhum no momento._

---

## Lessons Learned

### L-001: Backend vive em n8n + RPCs, não em código de servidor (2026-06-23)

**Context:** Mapeamento da arquitetura.
**Problem:** Não há "backend" tradicional para ler; a lógica está em `workspaces/*.json` (nós Code) e `migrations/*.sql` (RPCs).
**Solution:** Tratar workflows n8n e funções RPC como a camada de backend; mudanças de lógica acontecem nesses dois lugares.
**Prevents:** Procurar por uma API server inexistente ao planejar alterações.

### L-002: Bug de upload multi-data = perda de `periodo` + replace agressivo (2026-06-23)

**Context:** Investigação do bug "planilha não é adicionada corretamente em datas anteriores/posteriores".
**Problem:** (1) `Preparar Captura` no workflow de upload pode perder `periodo` (referência cruzada `$('Validar Arquivo')` + resposta assíncrona); (2) `embaplan_create_month_batch` com `periodo` nula assume `NOW()::DATE` e, com `p_replace=true` fixo, faz `DELETE ... WHERE periodo=hoje`, substituindo o batch do dia. Datas escolhidas são ignoradas.
**Solution:** RPC falha se `periodo` ausente; replace escopado por `periodo`+`user_id`; índice único por data; workflows validam `periodo`; front exige data. Ver `.specs/features/upload-multidatas/`.
**Prevents:** Sobrescrita acidental de batches e quebra da cronologia.

### L-006: Editar JSON de workflow no PowerShell 5.1 corrompe acentos (mojibake) (2026-06-23)

**Context:** Tentativa de reescrever `Embaplan-Upload-Planilha-Anuncios.json` via `ConvertFrom-Json`/`ConvertTo-Json` em PS 5.1.
**Problem:** `Get-Content -Raw` (sem `-Encoding UTF8`) e a leitura do próprio `.ps1` sem BOM tratam o texto como Latin1 → acentos viram mojibake (`histórico`→`histÃ³rico`). Isso quebraria a consolidação (colunas `ID do Anúncio`, `Impressões`).
**Solution:** Para editar workflows com acentos, usar as ferramentas de edição do editor (replace_string/create_file, que preservam UTF-8) OU `[IO.File]::ReadAllText(path,[Text.Encoding]::UTF8)` + `WriteAllText` com `UTF8Encoding($false)`. Validar com grep direto no arquivo (não confiar em `Write-Output` do PS, que também corrompe).
**Prevents:** Corromper strings-chave em JSON e quebrar matching de colunas.

### L-005: Planilha fora do padrão corrompia a oficial — gate de esquema antes de substituir (2026-06-23)

**Context:** 3ª inserção falhava ("Nenhum anúncio encontrado"). Diagnóstico dos `.xlsx`: a planilha correta tem 2 abas (`Base e QC` com 22 colunas + `Resumo`); a enviada tinha 1 aba `Sheet1` com 5 colunas (N. Pedidos, Taxa de, Custo Total, itens, Quantidade).
**Problem:** O nó `Atualizar Planilha Embaplan` SUBSTITUI o arquivo oficial no Google Drive ANTES de qualquer validação de conteúdo. Uma planilha fora do padrão sobrescrevia a oficial e, como nenhuma coluna batia, todas as linhas eram filtradas (métricas=0) → `produtos[]` vazio → front mostrava só as inserções antigas.
**Solution:** Gate de esquema (`Extrair Planilha (validação)` + `Validar Esquema`) inserido ENTRE `Validar Arquivo` e `Atualizar Planilha`. Exige exatamente as 22 colunas padrão; bloqueia com erro detalhado (faltando/inesperadas) sem tocar na oficial. Requisito SCHEMA-01.
**Prevents:** Corromper a planilha oficial e capturas vazias por arquivo errado.

### L-004: Captura vazia na 3ª planilha = leitura antes da sincronização do Google Sheets (2026-06-23)

**Context:** Após corrigir a perda de `periodo`, a 3ª inserção falhava no nó `Flatten Snapshots` ("Nenhum anúncio encontrado em produtos[].anuncios_detalhados"); front mostrava só 2 batches.
**Problem:** O workflow de upload SUBSTITUI o arquivo no Google Drive e **imediatamente** chama o sub-fluxo `Consultar Todas as Abas`, que lê via Google Sheets API o mesmo `documentId`. Sem espera, a leitura pode voltar **vazia** (Google ainda sincronizando). O nó `Ler Todas as Abas` tem `onError: continueRegularOutput`, engolindo o erro → `produtos[]` vazio → `Flatten` aborta. (A teoria de `.slice(-150)` NÃO se aplica: esse caminho usa `Consultar Todas as Abas`, que processa `$input.all()` inteiro.)
**Solution:** (1) Nó `Aguardar Sincronização` (Wait 6s) entre `Atualizar Planilha Embaplan` e a leitura; (2) guarda em `Preparar Captura` falha claramente quando `produtos.length === 0`; (3) erro do `Flatten` agora reporta contagens (produtos / anuncios_detalhados) para diagnóstico.
**Prevents:** Captura vazia silenciosa e mensagens de erro genéricas.

### L-003: Spec-driven em brownfield = spec → design → tasks → execute (2026-06-23)

**Context:** Implementação da feature `upload-multidatas` seguindo TLC skill completo.
**Problem:** Feature com bug multi-camada (front, workflow n8n, RPC SQL) exigiu coordenação precisa.
**Solution:** (1) Spec com 7 requisitos rastreáveis; (2) Design com root cause analysis + mermaid diagram; (3) Tasks com 6 subtasks atômicas (T1-T6), código SQL/JS completo, critérios de validação; (4) Execute delegando T4 a sub-agent para contexto limpo, validação em UAT roteirizada.
**Outcome:** Implementação T1-T5 completa em ~10 operações; 0 revisões; sub-agent delegation manteve contexto <70k tokens; UAT checklist imprimível gerado automaticamente.
**Prevents:** Ambiguidade em features complexas; retrabalho por falta de design; context overflow em edições grandes; falta de rastreabilidade requisito→código.

---

## Quick Tasks Completed

| #   | Description | Date | Commit | Status |
| --- | ----------- | ---- | ------ | ------ |
| –   | –           | –    | –      | –      |

---

## Deferred Ideas

- [ ] Suporte multi-marketplace (Mercado Livre/Amazon/Shein) — Captured during: mapeamento (citado nos prompts do agente)
- [ ] Externalizar mapeamento loja→shop_id Shopee — Captured during: mapeamento (INTEGRATIONS/CONCERNS)
- [ ] Modularizar `front.html` (extrair JS/CSS) — Captured during: mapeamento (CONCERNS)

---

## Todos

- [ ] Endereçar M2 (segurança): integrar Supabase Auth ao front e proteger webhooks
- [ ] Endereçar M3 (qualidade): introduzir pgTAP + Playwright

---

## Preferences

**Model Guidance Shown:** 2026-06-23

> Tarefas leves (validação, atualização de STATE, handoff de sessão) funcionam bem com modelos mais rápidos/baratos.
