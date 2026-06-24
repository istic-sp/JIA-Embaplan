# State

**Last Updated:** 2026-06-25
**Current Work:** Busca de anúncios no chat (exata por loja/índice/ID + textual acento-insensitive + semântica/typo/intenção via `sumario.catalogo[]`) — AD-012; depende do AD-011 (chat lê 100% do Supabase consolidado) — aguardando UAT no chat

---

## Recent Decisions (Last 60 days)

### AD-012: Busca de anúncios — exata + textual acento-insensitive + catálogo para busca semântica da IA (2026-06-25)

**Decision:** Requisito do usuário: o agente deve achar anúncios por loja, índice (ex.: `QC10`), ID, nome (parcial), e por semântica/sinônimo/typo/intenção. Divisão de trabalho: **determinístico no sub-fluxo, semântico na IA**. No sub-fluxo `[Embaplan] Sub-fluxo_ Consultar Planilha Inteligente.json` (nó `Filtrar Resultados para a IA1`): (1) busca textual agora é **acento-insensitive** via `norm()` (NFD + remove diacríticos + colapsa não-alfanumérico) — `biblico`→`Bíblicos`, `dinossauro`→`Dinossauros`, `escola dominical`, `safari`, `contos de fada`, índice e ID passam por substring normalizada; (2) branch de loja aceita termo residual (`loja 2 dinossauro` restringe; senão devolve a loja toda); (3) novo `sumario.catalogo[]` = TODOS os anúncios (loja, indice, id, titulo, status, link) + `aviso_busca`. Prompt (`Embaplan - Agent IA.json`): nova seção "🔎 MODOS DE BUSCA" — exata/textual/semântica, manda a IA percorrer `catalogo[]` por SIGNIFICADO para typo/intenção e LISTAGENS, e exige HONESTIDADE (ID inexistente = "não está na base", sem passar outro anúncio como se fosse o pedido — corrige o comportamento do screenshot).
**Reason:** O filtro era sensível a acento e só fazia substring exato; semântica/typo/intenção são trabalho de LLM, então a tool passa a entregar o catálogo completo e a IA raciocina sobre ele. Caso real: ID `22497100181` (Loja 1, índice QC10) não era achado — em parte por ausência de dado (planilha QC10 ainda não subida no Supabase), em parte por o filtro fabricar match errado.
**Trade-off:** Determinístico não cobre typo/intenção (proposital — fica com a IA via catálogo). `catalogo[]` aumenta o payload (aceitável no domínio, centenas de anúncios). **DADO:** anúncios precisam estar no Supabase (upload) para serem achados — a planilha aberta (Untitled-1, QC10) precisa ser enviada para testar aqueles IDs específicos.
**Impact:** Sub-fluxo (jsCode 25.2k→26.9k; +`norm`/`matchSubstr`/`catalogo`) e `Embaplan - Agent IA.json` (systemMessage 43.x→44.6k). Validado: JSON parseia, jsCode `new Function` OK, 8 casos de busca testados contra os dados de exemplo (QC10/ID/dinossauro/biblico/escola dominical/safari/contos de fada PASS; typo retorna vazio determinístico por design). Aguarda UAT — reimportar os workflows no n8n e subir a planilha QC10.

### AD-011: Chat lê 100% do Supabase consolidado — Google Sheet removido do caminho do chat (2026-06-25)

**Decision:** Evolução do AD-010 (Opção A completa). O sub-fluxo do chat (`[Embaplan] Sub-fluxo_ Consultar Planilha Inteligente.json`, workflowId `tfceuFQZN1G68Xyz` — usado SÓ pelo agente; o upload usa outro sub-fluxo, `2Pt9ddSETV34vSd8`) **deixou de ler o Google Sheet** e passou a ler 100% do nó Postgres `Base Consolidada (todas as lojas)` (latest-per-ad de TODOS os batches no Supabase). O nó `Filtrar Resultados para a IA1` agora mapeia as linhas do Supabase para o formato cru do pipeline (`mapSupabaseRow`: `_metricas` vindo das colunas do snapshot + `metrics_jsonb` para cliques/impressões/conversões; `Link do Shopee` de `metrics_jsonb.link` ou montado), reconstrói `produtos[]`/`anuncios_detalhados` via `consolidarPorProduto` e calcula `sumario.lojas[]` sobre a base COMPLETA (sem slice). Conexões religadas: trigger → [`Get Previous Snapshots`, `Base Consolidada`]; `Base Consolidada` → `Filtrar Resultados para a IA1`; nós `Google Sheets`, `Tem nome da aba?` e `Listar Abas API` ficaram órfãos (não executam). Prompt: removido `lojas_arquivo_atual`/aviso de "reenviar arquivo"; PASSO 1 reduzido a 1 chamada; `nome_do_separador` agora ignorado; descrição da tool atualizada.
**Reason:** O AD-010 (aditivo) expôs `lojas[]` consolidado, mas a FONTE de dados do agente (produtos/filtro) ainda era o Google Sheet (sobrescrito a cada upload → só a última loja), e o agente usava a tool como leitor de abas ("não encontrei a base com as abas esperadas"). O `metrics_jsonb` já persiste o detalhe completo por anúncio, então o Supabase substitui o Sheet sem perda.
**Trade-off:** Detalhe anúncio-a-anúncio agora disponível para TODAS as lojas (some a limitação do AD-010). `alteracoes_desde_ultimo_upload` passa a comparar base consolidada vs último batch (`Get Previous Snapshots`) — semântica levemente diferente, info secundária. Não testado em n8n ao vivo.
**Impact:** Sub-fluxo (jsCode 24.7k→25.2k; `Google Sheets`/`Tem nome da aba?`/`Listar Abas API` desconectados) e `Embaplan - Agent IA.json` (PASSO 1, bullet de lojas e descrição da tool). Validado: JSON parseia, jsCode `new Function` OK, conexões conferidas. **Supersede:** limitação do AD-010 ("reenviar arquivo para detalhe"). Aguarda UAT — usuário ausente, decisão autônoma (Opção A confirmada pelo usuário).

### AD-010: Agente só via lojas do último upload — adicionada base consolidada (5 lojas) (2026-06-25)

**Decision:** Causa raiz da reclamação "o sistema tem 5 lojas e ele só considera o último arquivo": o agente lê o **Google Sheet mestre** (`113Z3z...`), que o upload SOBRESCREVE a cada envio (`Atualizar Planilha Embaplan` = googleDrive update, `changeFileContent:true`, só quando período é o mais novo). Já o dashboard lê `embaplan_latest_overview` (Supabase) = último estado por anúncio em TODOS os batches → mostra as 5 lojas. **Fix (Opção A, aditivo/reversível):** no sub-fluxo `[Embaplan] Sub-fluxo_ Consultar Planilha Inteligente.json` adicionado nó Postgres `Base Consolidada (todas as lojas)` (latest-per-ad de TODOS os batches, mesmo padrão da RPC de overview), conectado ao trigger em paralelo. O nó `Filtrar Resultados para a IA1` agrega essas linhas por loja (try/catch) e passa a expor `sumario.lojas[]` = CONSOLIDADO (todas as lojas) + novo `sumario.lojas_arquivo_atual[]` = só o upload atual + `total_anuncios_consolidado` + `aviso_lojas`. **NÃO** mexe na auditoria profunda (`produtos[]`/`anuncios_detalhados` continuam do Google Sheet do período atual) nem na detecção de alterações (`Get Previous Snapshots` intacto). Prompt do agente atualizado: `lojas[]` = base consolidada (quais/quantas lojas existem); auditoria profunda = upload mais recente.
**Reason:** AD-007/AD-009 (prompt + filtro) não resolviam porque a FONTE do agente (Google Sheet) só tem o último arquivo. A base consolidada (5 lojas) só existe no Supabase.
**Trade-off:** O agente lista/contabiliza todas as lojas, mas detalhe anúncio-a-anúncio de lojas fora do último upload exige reenviar o arquivo (limitação honesta, comunicada). Query extra por chamada (indexada). Não rebuildou o pipeline de enriquecimento (risco baixo, sem testar n8n ao vivo).
**Impact:** Sub-fluxo (+1 nó Postgres, +conexão, jsCode 21.9k→24.7k) e `Embaplan - Agent IA.json` (systemMessage 42.5k→43.2k). Validado: JSON parseia, jsCode sintaxe OK (new Function), nó+conexão presentes. Aguarda UAT — usuário ausente, decisão autônoma (Opção A).

### AD-009: "Loja 1" vinha como "ML2" — causa raiz no filtro do sub-fluxo + reforço no prompt (2026-06-25)

**Decision:** Bug real: o filtro de loja em `[Embaplan] Sub-fluxo_ Consultar Planilha Inteligente.json` (nó `Filtrar Resultados para a IA1`) usava regex ANCORADA só-dígitos `/^loja\s*[-_]?\s*(\d+)$/i` — só filtrava se `termo_de_pesquisa` fosse EXATAMENTE "loja N". Como o agente mandava termo genérico/variado, caía no branch que devolve TODAS as lojas, e o agente lia `sumario.lojas[0]` (ordenado por receita = ML2). **Fix camada dados:** regex agora `/\bloja[\s_-]+([a-z0-9]+)/i` (acha "loja X" em qualquer posição, aceita alfanumérico tipo "ML2", exige separador p/ não casar o plural "lojas"), comparação `lojaVal === filtroLoja` ambos `.toLowerCase()`. **Fix camada prompt:** nova regra na seção "Loja N" — SEMPRE chamar a tool com `termo_de_pesquisa` = `loja <valor>` e NUNCA usar `sumario.lojas[0]` como "Loja 1".
**Reason:** AD-007 (só prompt) não bastou porque o erro também estava nos dados: o sub-fluxo não filtrava de forma robusta, então o agente recebia tudo e adivinhava errado.
**Trade-off:** Regex mais permissiva pode, em casos raros (ex.: "loja do produto X"), capturar token inválido e retornar 0 anúncios — recuperável (agente lista lojas disponíveis), e muito melhor que devolver a loja errada.
**Impact:** `[Embaplan] Sub-fluxo_ Consultar Planilha Inteligente.json` + `Embaplan - Agent IA.json` (systemMessage 41.9k → 42.5k). Validado: ambos JSON parseiam, regex testada em 10 termos (filtra "loja 1"/"anuncios da loja 1"/"loja ml2"; ignora "quais lojas tenho"/"lojas"). Aguarda UAT no chat.

### AD-008: Busca por ID no dashboard + ID & título nas menções do agente (2026-06-25)

**Decision:** (1) **Front** — novo input `#dashboardSearchInput` em `.dashboard-head-actions`; `renderDashboard` desvia para `renderBuscaAnuncios(rows, q)` quando há texto, filtrando `dashboardData` por `anuncio_indice`/`titulo`/`produto` (normalizado sem acento) e reusando `dashRow` (handlers delegados de histórico/análise continuam funcionando). Respeita os filtros de loja/marketplace por passar pelo funil `filterByLoja()`. (2) **Agente** — cabeçalho do card vira `📢 CAMPANHA: Index #[NÚMERO] — "[TÍTULO REAL]"` e nova "REGRA DE OURO" exige citar IDENTIFICADOR + TÍTULO juntos em QUALQUER menção (inclusive MODO RÁPIDO).
**Reason:** Usuário pediu localizar anúncio por ID no dashboard e o agente omitia o título (empresa localiza melhor pelo título).
**Trade-off:** Front 100% client-side (sem refetch); agente só prompt. Busca filtra a base já carregada — não busca histórico não exibido.
**Impact:** `front.html` (sem erros) e `Embaplan - Agent IA.json` (systemMessage 41.1k → 41.9k chars, validado). Aguarda UAT.

### AD-007: Corrigir interpretação do agente ("Loja N" literal + modo factual) (2026-06-24)

**Decision:** Inseridas 2 seções no topo do `systemMessage` do nó `RAG AI Agent`: (1) **Identidade da base / modo de resposta** — o agente SEMPRE tem acesso à base (tool `Consultar_Planilha_Inteligente1` lê a planilha mais recente); proibido dizer "não tenho base de dados"; MODO RÁPIDO (factual, resposta curta sem protocolo de 4 passos) vs MODO AUDITORIA (profundo). (2) **Interpretação de "Loja N"** — refere-se ao VALOR LITERAL da coluna `Loja` ("1","2","ML2"), nunca à posição/índice; "Loja 1" ≠ "Loja ML2"; se a loja não existir, listar as disponíveis em `sumario.lojas[].loja` em vez de devolver outra.
**Reason:** Agente confundia "loja 1" com a 1ª loja da lista (ML2) e negava ter base ao responder perguntas factuais simples (ex.: "quantos anúncios na base").
**Trade-off:** Apenas prompt; nenhuma mudança de dados/RPC. Risco de o modelo ainda escolher o modo errado — mitigado com exemplos explícitos de cada modo.
**Impact:** Edição isolada em `Embaplan - Agent IA.json` (systemMessage 38.9k → 41.1k chars). Validado: JSON parseia, acentos OK, seções presentes. Aguarda UAT no chat.

### AD-006: Segmentação por marketplace no dashboard é 100% client-side (2026-06-24)

**Decision:** Derivar o marketplace no front a partir do valor BRUTO de `r.loja` (`marketplaceFromLoja`: começa com `ML` → Mercado Livre; senão → Shopee). Adicionado `<select id="dashboardMarketplaceFilter">` (Todos/Shopee/Mercado Livre), filtro composto dentro de `filterByLoja()`, badge de marketplace nos cards de loja (`mkBadge`) e bloco "🛒 Por marketplace" no `renderHome` (exibido quando há 2+ marketplaces).
**Reason:** O valor bruto de `loja` (com prefixo ML/numérico) é preservado de ponta a ponta até `anuncios[].loja`. Não há campo `marketplace` em snapshot/RPC e não é necessário criar — derivação no cliente evita migração, mudança de RPC e re-captura de snapshots.
**Trade-off:** O dropdown de loja continua listando todas as lojas mesmo com marketplace filtrado (selecionar loja de outro marketplace → resultado vazio). Aceitável; evita re-popular o dropdown.
**Impact:** Mudanças isoladas em `front.html`; `filterByLoja()` agora aplica loja + marketplace e alimenta todos os tabs/sidebar. Zero alteração de backend.

### AD-005: Limitar `range` no `extractFromFile` xlsx para conter used range inflado (2026-06-24)

**Decision:** Setar a opção `range` (notação A1) nos nós xlsx do `extractFromFile`: `Extrair Planilha (validação)` (upload) = `A1:AD100000`; `Extract from Excel` (RAG) = `A1:CV100000`.
**Reason:** Alguns .xlsx vêm com `<dimension>` inflada (ex.: `A1:AMJ1048576` = 1.048.576 linhas x 1024 cols) com só ~86 linhas reais. SheetJS honra o `!ref` e varre o grid inteiro (~1 bi de células) + n8n cria 1M itens fantasma → 13min p/ 84 itens e estouro de memória.
**Trade-off:** O cap de colunas/linhas trunca arquivos absurdamente grandes; folga ampla (upload 30 cols, RAG 100 cols, 100k linhas) torna isso implausível no domínio.
**Impact:** n8n repassa o `range` direto ao `sheet_to_json`; com range, ele itera só a faixa e pula linhas vazias. Comprovado: sem range trava >min; com range = 84 linhas/22 cols/~1.2s, dados idênticos.

### AD-004: Padrão da planilha vira multi-marketplace por prefixo da coluna `Loja` (2026-06-24)

**Decision:** A coluna `Loja` passa a definir o marketplace: valor começando com `ML` → Mercado Livre; começando com `S` ou qualquer outro (padrão) → Shopee. O link de ML é montado SÓ pelo ID do anúncio no formato `https://produto.mercadolivre.com.br/MLB-{digitos}-_JM`; o de Shopee mantém `LOJAS[chave_numérica]` + `https://shopee.com.br/{slug}-i.{shop_id}.{ad_id}`. O gate de esquema passou a aceitar SINÔNIMOS por grupo (22 colunas), tolerando os nomes novos (`Nome`, `Convertidos`, `$Clicks`, `Conversão`/`Tx.Conver.`, `Vendidos`, `Investimento`, `Anunciada`, `%l.Medio`, `%Lliquido`, `indice`, `INDEX`) e os antigos.
**Reason:** A planilha agora pode conter anúncios de Shopee e Mercado Livre no mesmo padrão; os nomes de colunas variam entre exports.
**Trade-off:** O campo de saída continua chamado `Link do Shopee` (compat com front/histórico/agente) embora possa conter link de ML.
**Impact:** `montarLinkShopee` + helpers (`detectarMarketplace`, `lojaKeyNumerica`, `montarLinkMercadoLivre`) e picks de métricas/título atualizados em `Consultar Planilha Inteligente` e `Consultar Todas as Abas`; gate em `Upload-Planilha-Anuncios` reescrito com grupos de sinônimos. Spec em `.specs/features/padrao-planilha-multimarketplace/`.

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

### L-007: `extractFromFile` xlsx varre o used range declarado, não os dados reais (2026-06-24)

**Context:** Nó `Extrair Planilha (validação)` levou 13min para 84 itens e "quebrava a infra".
**Problem:** O .xlsx tinha `<dimension>` inflada (`A1:AMJ1048576`). SheetJS `sheet_to_json` itera todo o `!ref` (1M linhas x 1024 cols ≈ 1 bi de células) e o n8n materializa 1M de itens vazios.
**Solution:** Setar a opção `range` (string A1) no nó; n8n a repassa ao `sheet_to_json`, que itera só a faixa e pula linhas vazias (saída = linhas reais). Diagnóstico: ler `xl/worksheets/sheetN.xml` (xlsx = zip) e checar `<dimension ref>`.
**Prevents:** Parse de minutos e OOM por planilhas com used range inflado (comum em exports/edições no Excel).

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

- [~] Suporte multi-marketplace (Mercado Livre/Amazon/Shein) — Mercado Livre + Shopee ENTREGUES (AD-004); Amazon/Shein pendentes
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
