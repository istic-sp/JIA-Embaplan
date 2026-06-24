# Testing Infrastructure

> **Estado atual: NÃO HÁ testes automatizados no repositório.** Não foram encontrados frameworks de teste, arquivos de teste, nem configuração de CI. A validação é manual (UAT pelo usuário no front.html e no n8n). Esta é uma lacuna relevante — ver CONCERNS.md.

## Test Frameworks

**Unit:** nenhum
**Integration:** nenhum
**E2E:** nenhum
**Coverage:** não medido

## Test Organization

**Local:** não aplicável (sem testes)
**Naming:** não aplicável
**Structure:** não aplicável

## Test Execution

**Commands:** nenhum comando de teste definido (sem `package.json`, `Makefile` ou config de CI).
**Validação atual:** manual —

- Frontend: abrir `front.html` no navegador e exercitar fluxos.
- Banco: aplicar migrations no Supabase e testar RPCs via SQL editor.
- Workflows: executar/testar no editor n8n (botão "Test workflow").

## Coverage Targets

**Current:** 0% (sem testes)
**Goals:** não documentados. Recomendação ECC: mínimo 80% quando testes forem introduzidos.
**Enforcement:** nenhum.

## Test Coverage Matrix

| Code Layer              | Required Test Type                | Location Pattern    | Run Command             |
| ----------------------- | --------------------------------- | ------------------- | ----------------------- |
| Frontend (`front.html`) | none (atual) → e2e                | n/a                 | n/a                     |
| Funções RPC (Supabase)  | none (atual) → integration        | `migrations/*.sql`  | n/a (pgTAP recomendado) |
| Workflows n8n           | none (atual) → integration manual | `workspaces/*.json` | Test workflow no editor |

> Todas as camadas estão marcadas como "none" hoje. As colunas após "→" indicam o tipo recomendado a adotar.

## Parallelism Assessment

| Test Type | Parallel-Safe? | Isolation Model | Evidence              |
| --------- | -------------- | --------------- | --------------------- |
| n/a       | n/a            | n/a             | Sem testes existentes |

> Quando testes de integração de banco forem adicionados: usar banco/schema isolado por execução, pois as RPCs compartilham tabelas `embaplan_*` (não paralelizáveis com banco compartilhado).

## Gate Check Commands

| Gate Level | When to Use | Command        |
| ---------- | ----------- | -------------- |
| Quick      | n/a         | (não definido) |
| Full       | n/a         | (não definido) |
| Build      | n/a         | (não definido) |

## Recomendações para introduzir testes

1. **Banco (prioridade):** adotar **pgTAP** para testar funções RPC (`embaplan_create_month_batch`, `embaplan_evaluate_recommendations`, guards de admin) com banco efêmero (Supabase local / Docker).
2. **Frontend:** **Playwright** para E2E dos fluxos críticos (login, enviar mensagem, upload de planilha, abrir dashboard).
3. **Workflows n8n:** testes de integração chamando os webhooks com payloads conhecidos e asserções sobre o estado do banco.
4. **CI:** pipeline mínimo que aplica migrations em banco limpo e roda os testes de banco.
