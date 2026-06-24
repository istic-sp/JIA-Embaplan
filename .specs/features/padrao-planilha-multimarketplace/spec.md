# Feature: Padrão de planilha multi-marketplace (Shopee + Mercado Livre)

**Status:** In progress
**Size:** Large
**Created:** 2026-06-24

## Resumo

Refatorar o padrão de leitura da planilha de anúncios para:

1. Aceitar nomes de colunas em variações novas (sinônimos), sem quebrar o gate de esquema.
2. Detectar o marketplace pela coluna `Loja` e gerar o link correto:
   - `Loja` começa com `ML` → **Mercado Livre**
   - `Loja` começa com `S` ou qualquer outro valor (padrão) → **Shopee**

## Contexto / Decisões do usuário

- **Gate de esquema:** aceitar SINÔNIMOS (flexível) — tanto os nomes antigos quanto os novos passam.
- **Link Mercado Livre:** formato `https://produto.mercadolivre.com.br/MLB-{digitos}-_JM` (ex: `MLB5323824554` → `https://produto.mercadolivre.com.br/MLB-5323824554-_JM`).
- **ML sem shop_id:** o link de ML é montado SÓ pelo ID do anúncio (sem mapeamento de loja).
- **Shopee:** mantém o mapa `LOJAS` (loja → shop_id) e o formato `https://shopee.com.br/{slug}-i.{shop_id}.{ad_id}`. A chave da loja é a parte numérica de `Loja` (ex: `S1` → `1`, `3` → `3`).

## Padrões de cabeçalho aceitos (exemplos)

Shopee (22 colunas):

```
# | Loja | INDEX | ID do anúncio | Nome | Impressões | Cliques | CTR | Convertidos | $Clicks | Conversão | Vendidos | GMV | Investimento | ACOS | Categoria | tamanho | Anunciada | %l.Medio | lucro liquido | %Lliquido | indice
# | Loja | Index | ID do Anúncio | Nome | Impressões | Cliques | CTR | Convertidos | $clicks | Tx.Conver. | Vendidos | GMV | Investimento | ACOS | Categoria | tamanho | Anunciada | %l.Medio | lucro liquido | %Lliquido | indice
```

Mercado Livre (19 colunas — SEM `Categoria`, `Tamanho`, `Qtd`):

```
# | Loja | Index | ID do Anúncio | Nome | Impressões | Cliques | CTR | Convertidos | $clicks | Tx.Conver. | Vendidos | GMV | Investimento | ACOS | %l.Medio | lucro liquido | %Lliquido | indice
```

## Grupos de sinônimos (gate de esquema, 22 colunas)

| #   | Canônico              | Sinônimos                 |
| --- | --------------------- | ------------------------- |
| 1   | `#`                   | —                         |
| 2   | `Loja`                | —                         |
| 3   | `Index`               | `INDEX`                   |
| 4   | `ID do Anúncio`       | `ID do anúncio`           |
| 5   | `Nome do Anúncio`     | `Nome`                    |
| 6   | `Impressões`          | —                         |
| 7   | `Cliques`             | —                         |
| 8   | `CTR`                 | —                         |
| 9   | `Conversões`          | `Convertidos`             |
| 10  | `Custo por Conversão` | `$Clicks`, `$clicks`      |
| 11  | `Taxa de Conversão`   | `Conversão`, `Tx.Conver.` |
| 12  | `Itens Vendidos`      | `Vendidos`                |
| 13  | `GMV`                 | —                         |
| 14  | `Despesas`            | `Investimento`            |
| 15  | `ACOS`                | —                         |
| 16  | `Categoria`           | —                         |
| 17  | `Tamanho`             | `tamanho`                 |
| 18  | `Qtd`                 | `Anunciada`               |
| 19  | `% Lucro Médio P`     | `%l.Medio`                |
| 20  | `lucro liquido`       | —                         |
| 21  | `% Lucro`             | `%Lliquido`               |
| 22  | `Índice`              | `indice`                  |

## Requisitos

| ID        | Requisito                                                                                             | Onde                             |
| --------- | ----------------------------------------------------------------------------------------------------- | -------------------------------- |
| MKT-01    | Detectar marketplace pela coluna `Loja` (`ML*`=Mercado Livre; `S*`/padrão=Shopee)                     | `montarLinkShopee` (2 workflows) |
| MKT-02    | Gerar link ML `https://produto.mercadolivre.com.br/MLB-{digitos}-_JM` a partir do ID do anúncio       | `montarLinkMercadoLivre`         |
| MKT-03    | Shopee usa a parte numérica de `Loja` como chave do `LOJAS` (shop_id)                                 | `lojaKeyNumerica`                |
| COL-01    | Reconhecer sinônimos de métricas: `Vendidos`, `Investimento`, `Convertidos`, `Conversão`/`Tx.Conver.` | `enriquecerLinha` (2 workflows)  |
| COL-02    | Reconhecer `Nome`/`Nome do Anúncio` como título                                                       | picks de `titulo` (2 workflows)  |
| SCHEMA-02 | Gate de esquema aceita sinônimos por grupo (mantém 22 colunas)                                        | `Validar Esquema` (upload)       |
| SCHEMA-03 | Gate aceita ML (19 colunas): `Categoria`, `Tamanho`, `Qtd` são OPCIONAIS                              | `Validar Esquema` (upload)       |
| PERF-01   | `extractFromFile` xlsx usa `range` (A1) para conter used range inflado (evita parse de minutos/OOM)   | nós xlsx (upload + RAG)          |
| UI-01     | Dashboard deriva marketplace do `r.loja` (client-side) e filtra por marketplace (Todos/Shopee/ML)     | `front.html` (`filterByLoja`)    |
| UI-02     | Cards de loja exibem badge do marketplace; bloco "Por marketplace" segmenta KPIs quando há 2+ deles   | `front.html` (`renderHome`)      |

## Workflows impactados

- `workspaces/[Embaplan] Sub-fluxo_ Consultar Planilha Inteligente.json`
- `workspaces/Embaplan - Consultar Todas as Abas.json`
- `workspaces/Embaplan-Upload-Planilha-Anuncios.json`
- `front.html` (segmentação por marketplace no dashboard, 100% client-side)

## Notas

- O campo de saída continua chamado `Link do Shopee` (compatibilidade com front/histórico/agente); apenas o VALOR passa a refletir o marketplace.
