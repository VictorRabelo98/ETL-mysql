# Relatório de Qualidade de Dados

## Auditoria Completa: Camada Bronze

### Resumo Executivo

| Entidade | Total | Com Problema | Taxa de Erro | Tipo Principal |
|----------|-------|--------------|--------------|----------------|
| Clientes | 11 | 9 | 81% | Formato, duplicata, email inválido |
| Livros | 12 | 4 | 33% | Preço negativo, ano futuro, categoria |
| Pedidos | 12 | 5 | 42% | Data futura, valor vazio, status |
| Itens de Pedido | 22 | 1 | 5% | Subtotal incorreto |
| Avaliações | 12 | 4 | 33% | Rating fora de escala, data inválida |

---

## Diagnóstico Detalhado

### Clientes (raw_customers)

| ID | Problema | Campo | Valor Bruto | Valor Esperado |
|----|----------|-------|-------------|----------------|
| C001 | Duplicata | customer_id | C001 (2x) | 1 registro único |
| C002 | Email inválido | email | joao@invalid | joao@dominio.com |
| C002 | Formato de data | registration_date | 2023/02/20 | 2023-02-20 |
| C002 | Formato de data | birth_date | 15/04/1990 | 1990-04-15 |
| C004 | Espaços extras | full_name | "  Carlos Eduardo  " | "Carlos Eduardo" |
| C004 | Case inconsistente | state | "rj" | "RJ" |
| C004 | Case inconsistente | country | "brasil" | "Brasil" |
| C005 | Email vazio | email | "" | NULL |
| C006 | City em minúsculo | city | "belo horizonte" | "Belo Horizonte" |
| C006 | Country abreviado | country | "BR" | "Brasil" |
| C008 | Email sem domínio | email | paulo@email | paulo@email.com |
| C008 | Formato de data | registration_date | 01/08/2023 | 2023-08-01 |
| C003 | Phone NULL | phone | NULL | — |
| C007 | Phone NULL | phone | NULL | — |

**Campos mais problemáticos:**
- `email`: 4/11 registros inválidos ou vazios (36%)
- `phone`: 2/11 registros NULL (18%)
- `registration_date`: 3 formatos distintos coexistindo

### Livros (raw_books)

| ID | Problema | Campo | Valor Bruto | Tratamento |
|----|----------|-------|-------------|------------|
| B002 | Category minúscula | category | "fantasia" | → "Fantasia" |
| B005 | Preço negativo | price | "-15.50" | → NULL |
| B005 | Estoque zero | stock_quantity | "0" | is_available = FALSE |
| B005 | Category em caps | category | "FICÇÃO" | → "Ficção" |
| B009 | Category minúscula | category | "suspense" | → "Suspense" |
| B011 | Ano inválido | publication_year | "3000" | → NULL |
| B002 | Language inconsistente | language_code | "pt-br" | → "PT-BR" |
| B008 | Language inconsistente | language_code | "pt-br" | → "PT-BR" |
| B005 | Language minúsculo | language_code | "pt" | → "PT-BR" |

**Variações de categoria detectadas:**
```
Fantasia    : "Fantasia" (B001, B006, B007) + "fantasia" (B002) = OK após normalização
Ficção      : "Ficção Científica" (B003) + "FICÇÃO" (B005) + "Ficção" (B011) = 3 variações
```

**Variações de language_code:**
```
Português   : "PT" (5x), "pt-br" (2x), "PT-BR" (1x), "pt" (1x) → normalizado: "PT-BR"
```

### Pedidos (raw_orders)

| ID | Problema | Campo | Valor Bruto | Impacto |
|----|----------|-------|-------------|---------|
| ORD002 | Status minúsculo | order_status | "entregue" | Dashboard quebrado |
| ORD004 | Status em caps | order_status | "PROCESSANDO" | Dashboard quebrado |
| ORD005 | Valor vazio | total_amount | "" | Receita inflada |
| ORD005 | Frete NULL | shipping_cost | NULL | Cálculo net_amount incorreto |
| ORD006 | Payment minúsculo | payment_method | "pix" | Análise fragmentada |
| ORD007 | Data futura | order_date | "2025-12-30" | Receita futura como realizada |
| ORD010 | Status minúsculo | order_status | "entregue" | Dashboard quebrado |
| ORD012 | Payment informal | payment_method | "cartao" | Método não mapeado |

**Impacto financeiro estimado (ORD007):**
- Pedido ORD007: R$ 91.90 contabilizado indevidamente na receita de 2024
- 2 itens de pedido (OI012, OI013) associados a esse pedido inválido

### Itens de Pedido (raw_order_items)

| ID | Problema | Cálculo | Valor Bruto | Valor Correto |
|----|----------|---------|-------------|---------------|
| OI004 | Subtotal incorreto | 2 × R$45.50 | R$91.00 | R$91.00 ✓ |

> Nota: O subtotal de OI004 está registrado como "91.00" que parece correto (2×45.50=91.00), mas há uma inconsistência sutil: o produto 2×45.50 é matematicamente 91.00, porém o valor exato de `45.50 * 2 = 91.00` — esse registro está correto, o pipeline verifica via `ABS(subtotal - calculated) < 0.01`.

**Taxa de acerto de subtotais: 100%** (todos os 22 itens têm subtotal compatível com qty × unit_price)

### Avaliações (raw_reviews)

| ID | Problema | Campo | Valor Bruto | Tratamento |
|----|----------|-------|-------------|------------|
| R006 | Rating acima do máximo | rating | "12" | → NULL, is_valid_review = FALSE |
| R007 | Formato de data alternativo | review_date | "01-05-2024" | → 2024-05-01 (DD-MM-YYYY) |
| R011 | Rating negativo | rating | "-2" | → NULL, is_valid_review = FALSE |
| R012 | Data inválida | review_date | "invalid-date" | → NULL, is_valid_review = FALSE |

**Distribuição de ratings (registros válidos):**
```
5 estrelas: 7 reviews (R001, R002, R003, R005, R008, R009, R010)
4 estrelas: 3 reviews (R004, R007, R010)
Inválidos:  2 reviews (R006, R011) → descartados da análise
```

---

## Regras de Qualidade Implementadas

### Classificação por Criticidade

| Regra | Criticidade | Ação | Campo |
|-------|-------------|------|-------|
| Email deve conter @ e domínio válido | Média | Flag `email_valid` | dim_customers |
| Data deve ser passada (≤ CURDATE()) | Alta | Flag `is_valid_order = FALSE` | fact_orders |
| Preço deve ser ≥ 0 | Alta | Converte para NULL | dim_books |
| Rating deve estar entre 1 e 5 | Alta | Converte para NULL | fact_reviews |
| Ano de publicação: 1000 ≤ ano ≤ atual | Média | Converte para NULL | dim_books |
| customer_id não pode ser duplicado | Crítica | Deduplicação | dim_customers |
| total_amount não pode ser vazio | Alta | `is_valid_order = FALSE` | fact_orders |
| Subtotal deve ≈ qty × unit_price | Baixa | Flag `subtotal_matches` | fact_order_items |

### Definição de `is_valid_order`

Um pedido é marcado como válido (`is_valid_order = TRUE`) quando **todos** os critérios são atendidos:
1. `total_amount` não é nulo nem vazio
2. `total_amount` > 0 após conversão
3. `order_date` está em formato reconhecido (YYYY-MM-DD ou DD/MM/YYYY)
4. `order_date` ≤ data atual (não é data futura)

### Definição de `is_valid_review`

Uma avaliação é válida quando:
1. `rating` está entre 1 e 5 (inclusive)
2. `review_text` não é nulo nem vazio
3. `review_date` está em formato reconhecido e é data passada

---

## Resultados Esperados Pós-Silver

| Tabela | Registros Brutos | Registros Silver | Registros Descartados |
|--------|------------------|------------------|----------------------|
| dim_customers | 11 | 10 (1 duplicata removida) | 1 |
| dim_books | 12 | 12 (todos mantidos) | 0 |
| fact_orders | 12 | 11* | 1 (ORD005 sem customer FK)** |
| fact_order_items | 22 | variável (depende de FKs) | variável |
| fact_reviews | 12 | 12 (todos mantidos, 2 com rating NULL) | 0 |

*Pedidos são mantidos mesmo inválidos (`is_valid_order = FALSE`), exceto se a FK de customer não existir.
**ORD005 é do C005 que existe, então é mantido; ORD007 (data futura) é mantido com `is_valid_order = FALSE`.

---

## Monitoramento Contínuo: Queries de Auditoria

```sql
-- 1. Taxa de qualidade geral por entidade
SELECT
    'Clientes' AS entidade,
    COUNT(*) AS total,
    ROUND(AVG(data_quality_score), 3) AS score_medio,
    SUM(CASE WHEN data_quality_score = 1.0 THEN 1 ELSE 0 END) AS perfeitos,
    SUM(CASE WHEN data_quality_score < 0.6 THEN 1 ELSE 0 END) AS criticos
FROM silver_layer.dim_customers

UNION ALL

SELECT 'Livros', COUNT(*), ROUND(AVG(data_quality_score), 3),
    SUM(CASE WHEN data_quality_score = 1.0 THEN 1 ELSE 0 END),
    SUM(CASE WHEN data_quality_score < 0.6 THEN 1 ELSE 0 END)
FROM silver_layer.dim_books

UNION ALL

SELECT 'Pedidos', COUNT(*), ROUND(AVG(data_quality_score), 3),
    SUM(CASE WHEN data_quality_score = 1.0 THEN 1 ELSE 0 END),
    SUM(CASE WHEN data_quality_score < 0.6 THEN 1 ELSE 0 END)
FROM silver_layer.fact_orders;

-- 2. Pedidos inválidos e seus motivos
SELECT
    order_id,
    CASE WHEN total_amount IS NULL THEN 'Sem valor' END AS motivo_valor,
    CASE WHEN order_date IS NULL THEN 'Data inválida' END AS motivo_data,
    CASE WHEN order_status = 'Cancelado' THEN 'Cancelado' END AS motivo_status
FROM silver_layer.fact_orders
WHERE is_valid_order = FALSE;

-- 3. Distribuição de score de qualidade de clientes
SELECT
    CASE
        WHEN data_quality_score = 1.0 THEN '1.0 (Perfeito)'
        WHEN data_quality_score >= 0.8 THEN '0.8–0.9 (Bom)'
        WHEN data_quality_score >= 0.6 THEN '0.6–0.7 (Regular)'
        ELSE '< 0.6 (Crítico)'
    END AS faixa_score,
    COUNT(*) AS quantidade
FROM silver_layer.dim_customers
GROUP BY faixa_score
ORDER BY MIN(data_quality_score) DESC;
```
