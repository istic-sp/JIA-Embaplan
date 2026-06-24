# T6: Checklist de UAT — Upload em Múltiplas Datas

**Feature:** `upload-multidatas`  
**Executor:** ******\_\_\_\_******  
**Data:** **********\_\_**********

---

## 🔧 Pré-requisitos

- [ ] **1. Aplicar migration 020 no Supabase**

  ```sql
  -- SQL Editor do Supabase (ou psql):
  -- Copiar/colar conteúdo de migrations/020_fix_create_month_batch.sql
  ```

  ✅ Sem erros | ❌ Erro: **********\_\_\_**********

- [ ] **2. Reimportar workflows no n8n**
  - [ ] `Embaplan-Upload-Planilha-Anuncios.json` → Import → Activate
  - [ ] `Embaplan-Historico-Snapshots.json` → Import → Activate

  ✅ Ambos ativos | ❌ Problema: **********\_\_\_**********

- [ ] **3. Verificar estado inicial**
  ```sql
  SELECT id, periodo, rotulo FROM embaplan_upload_batch ORDER BY periodo;
  ```
  **Resultado:** **\_** batches existentes  
  **Datas:** ******\_\_\_\_******, ******\_\_\_\_******

---

## 🧪 Testes Funcionais

### Teste 1: Adicionar Data ANTERIOR

**Objetivo:** Inserir batch com data anterior às existentes, SEM apagar outros batches.

- [ ] **Ação:** Abrir `front.html` → Modal de upload → Selecionar data **anterior** (ex.: 2026-04-10)
- [ ] **Ação:** Enviar planilha qualquer `.xlsx`
- [ ] **Verificar:** Upload bem-sucedido, mensagem de sucesso exibida
- [ ] **Verificar SQL:**
  ```sql
  SELECT id, periodo, rotulo FROM embaplan_upload_batch ORDER BY periodo;
  ```
  **Esperado:** Total de batches = inicial + 1  
  **Datas ordenadas:** **\_\_** < **\_\_** < **\_\_** (nova data aparece no início)  
  **Batches anteriores intactos:** ✅ | ❌

✅ PASSOU | ❌ FALHOU: **********\_\_\_**********

---

### Teste 2: Adicionar Data POSTERIOR

**Objetivo:** Inserir batch com data posterior às existentes, sem apagar outros batches.

- [ ] **Ação:** Modal de upload → Selecionar data **posterior** (ex.: 2026-07-10)
- [ ] **Ação:** Enviar planilha
- [ ] **Verificar:** Upload bem-sucedido
- [ ] **Verificar SQL:**
  ```sql
  SELECT id, periodo, rotulo FROM embaplan_upload_batch ORDER BY periodo;
  ```
  **Esperado:** Total de batches = anterior + 1  
  **Nova data aparece no final:** ✅ | ❌  
  **Dashboard mostra novo período como atual:** ✅ | ❌

✅ PASSOU | ❌ FALHOU: **********\_\_\_**********

---

### Teste 3: Replace de Mesma Data

**Objetivo:** Reenviar planilha para data já existente deve **substituir apenas aquele batch**, mantendo outros intactos.

- [ ] **Ação:** Modal de upload → Selecionar **mesma data** do Teste 2 (ex.: 2026-07-10)
- [ ] **Ação:** Enviar planilha diferente
- [ ] **Verificar:** Upload bem-sucedido, mensagem de substituição
- [ ] **Verificar SQL:**

  ```sql
  SELECT id, periodo, rotulo FROM embaplan_upload_batch ORDER BY periodo;
  ```

  **Esperado:** Total de batches = igual ao Teste 2 (não aumentou)  
  **Batch substituído:** `id` mudou para aquela data ✅ | ❌

  ```sql
  SELECT COUNT(*) FROM embaplan_upload_batch WHERE periodo='2026-07-10';
  ```

  **Esperado:** `1` (sem duplicatas)  
  **Outros batches intactos:** ✅ | ❌

✅ PASSOU | ❌ FALHOU: **********\_\_\_**********

---

### Teste 4: Bloqueio no Frontend (sem data)

**Objetivo:** Frontend deve impedir envio quando nenhuma data selecionada.

- [ ] **Ação:** Modal de upload → **Limpar campo de data** (deixar vazio)
- [ ] **Ação:** Tentar enviar planilha
- [ ] **Verificar:** Mensagem de erro aparece: _"Selecione a data de referência..."_
- [ ] **Verificar:** Modal permanece aberto (não fecha)
- [ ] **Verificar SQL:**
  ```sql
  SELECT id, periodo, rotulo FROM embaplan_upload_batch ORDER BY periodo;
  ```
  **Esperado:** Total de batches = igual ao Teste 3 (nenhum novo criado)

✅ PASSOU | ❌ FALHOU: **********\_\_\_**********

---

### Teste 5: Verificar Unicidade no Banco

**Objetivo:** Confirmar que não há duplicatas de `periodo` no banco.

- [ ] **Executar SQL:**
  ```sql
  SELECT periodo, COUNT(*) AS total
  FROM embaplan_upload_batch
  WHERE periodo IS NOT NULL
  GROUP BY periodo
  HAVING COUNT(*) > 1;
  ```
  **Esperado:** `0 linhas` (nenhuma duplicata)  
  **Resultado real:** **\_\_\_** linhas

✅ PASSOU | ❌ FALHOU: **********\_\_\_**********

---

### Teste 6: Verificar `periodo` no Banco = Escolhida no Front

**Objetivo:** Data salva no banco deve corresponder exatamente à selecionada no front.

- [ ] **Ação:** Selecionar data específica no front (ex.: 2026-08-15)
- [ ] **Ação:** Enviar planilha
- [ ] **Verificar SQL:**
  ```sql
  SELECT periodo FROM embaplan_upload_batch ORDER BY id DESC LIMIT 1;
  ```
  **Data esperada:** 2026-08-15  
  **Data real:** ******\_\_******  
  **Match:** ✅ | ❌

✅ PASSOU | ❌ FALHOU: **********\_\_\_**********

---

## 📊 Resultado Final

**Testes Passados:** \_**\_ / 6  
**Testes Falhados:** \_\_** / 6

### Critérios de Aprovação

- [ ] **TODOS os 6 testes passaram**
- [ ] Cronologia permanece íntegra (nenhum batch apagado indevidamente)
- [ ] `periodo` no banco sempre igual à escolhida no front
- [ ] Nenhuma duplicata de `periodo` no banco

**Feature APROVADA para produção:** ✅ | ❌

---

## 📝 Notas / Problemas Encontrados

```
[Escreva aqui qualquer observação, erro inesperado ou comportamento estranho]




```

---

## ✅ Próximos Passos (após aprovação)

- [ ] Registrar resultados em `.specs/project/STATE.md`
- [ ] Fazer commit das mudanças:

  ```bash
  git add migrations/020_fix_create_month_batch.sql
  git commit -m "feat(db): corrige create_month_batch para multiplas datas"

  git add workspaces/Embaplan-*.json
  git commit -m "fix(n8n): valida periodo nos fluxos de upload"

  git add front.html
  git commit -m "fix(front): exige data de referencia no upload"
  ```

- [ ] Deploy para produção
- [ ] Marcar M2.5 como COMPLETE no ROADMAP

---

**Assinatura:** ******\_\_\_\_******  
**Data:** **********\_\_**********
