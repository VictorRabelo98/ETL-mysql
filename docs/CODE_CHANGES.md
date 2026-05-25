# Relatório de Alterações no Código

> Este documento explica **o que foi corrigido, onde estava o erro e por que a correção é necessária** nas versões geradas em `sql-project/corrected/`. O código original (`sql-project/*.sql`) **não foi alterado**.

---

## Arquivo 1: `1_bronze_corrected.sql`

### [MELHORIA B1] Charset explícito na criação dos schemas

**Original:**
```sql
CREATE SCHEMA bronze_layer;
CREATE SCHEMA silver_layer;
CREATE SCHEMA gold_layer;
```

**Corrigido:**
```sql
CREATE SCHEMA bronze_layer CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE SCHEMA silver_layer CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE SCHEMA gold_layer    CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
```

**Por quê:**
Sem charset explícito, o schema herda o charset padrão do servidor MySQL. Em servidores configurados com `latin1` (ainda comum em instalações antigas), caracteres como `ã`, `é`, `ç` em `São Paulo`, `Florianópolis`, `Ficção Científica` são armazenados incorretamente, causando erros de encoding visíveis nos relatórios da Gold layer. `utf8mb4` suporta todo o Unicode, incluindo emojis e caracteres especiais do Português.

---

### [MELHORIA B2] Índices nas tabelas Bronze

**Original:** Nenhum índice nas tabelas Bronze.

**Corrigido:**
```sql
CREATE TABLE raw_customers (
    ...
    INDEX idx_customer_id (customer_id),
    INDEX idx_created_at  (created_at)
);
```

**Por quê:**
A deduplicação na Silver usa uma subquery que filtra por `customer_id` e `MIN(created_at)`. Sem índice, essa operação é O(n²) — cada linha da Bronze faz um full table scan para encontrar o MIN. Com índices, é O(n log n). Em datasets pequenos o impacto é imperceptível; em 100k+ registros, a diferença pode ser de segundos vs. horas.

---

## Arquivo 2: `2_silver_corrected.sql`

### [CORREÇÃO S1] Deduplicação robusta de clientes

**Arquivo:** `2_silver_corrected.sql` — INSERT em `dim_customers`

**Original:**
```sql
SELECT DISTINCT
    customer_id,
    TRIM(REGEXP_REPLACE(full_name, '\\s+', ' ')) AS full_name,
    ...
FROM bronze_layer.raw_customers
WHERE customer_id IS NOT NULL;
```

**Corrigido:**
```sql
SELECT
    rc.customer_id,
    TRIM(REGEXP_REPLACE(rc.full_name, '\\s+', ' ')) AS full_name,
    ...
FROM bronze_layer.raw_customers rc
WHERE rc.created_at = (
    SELECT MIN(rc2.created_at)
    FROM bronze_layer.raw_customers rc2
    WHERE rc2.customer_id = rc.customer_id
)
AND rc.customer_id IS NOT NULL;
```

**Por quê — o bug:**
`SELECT DISTINCT` elimina linhas apenas quando **todos os campos selecionados são idênticos**. No dado original, C001 aparece duas vezes com `NOW()` — em produção, dois inserts em momentos diferentes teriam `created_at` diferentes. Nesse caso, DISTINCT manteria ambos os registros com o mesmo `customer_id`, e o INSERT subsequente em `dim_customers` (que tem `customer_id UNIQUE`) **falharia com erro de constraint**.

**A correção:**
A subquery `WHERE rc.created_at = (SELECT MIN(created_at) WHERE customer_id = rc.customer_id)` garante que apenas um registro — o mais antigo — seja selecionado por `customer_id`. É a deduplicação correta para dados com timestamps de ingestão.

---

### [CORREÇÃO S2] Score de qualidade inclui validação de formato de data

**Original:**
```sql
(CASE WHEN registration_date IS NOT NULL THEN 0.2 ELSE 0 END)
```

**Corrigido:**
```sql
(CASE WHEN rc.registration_date REGEXP '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
        OR rc.registration_date REGEXP '^[0-9]{4}/[0-9]{2}/[0-9]{2}$'
        OR rc.registration_date REGEXP '^[0-9]{2}/[0-9]{2}/[0-9]{4}$'
      THEN 0.20 ELSE 0 END)
```

**Por quê:**
A versão original pontuava `registration_date IS NOT NULL` como critério de qualidade. Porém uma data como `"invalid-date-xyz"` é NOT NULL e recebia 0.20 de score mesmo sendo inútil. A correção exige que a data esteja em formato reconhecido, tornando o score uma métrica real de qualidade.

---

### [CORREÇÃO S3] `is_valid_order` suporta ambos os formatos de data

**Original:**
```sql
CASE
    WHEN o.total_amount IS NOT NULL
        AND o.total_amount != ''
        AND CAST(o.total_amount AS DECIMAL(10,2)) > 0
        AND o.order_date IS NOT NULL
        AND STR_TO_DATE(o.order_date, '%Y-%m-%d') <= CURDATE()  -- ← só YYYY-MM-DD
        THEN TRUE
    ELSE FALSE
END AS is_valid_order
```

**Corrigido:**
```sql
CASE
    WHEN o.total_amount IS NOT NULL
        AND o.total_amount != ''
        AND CAST(o.total_amount AS DECIMAL(10,2)) > 0
        AND (
            (o.order_date REGEXP '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
                AND STR_TO_DATE(o.order_date, '%Y-%m-%d') <= CURDATE())
            OR
            (o.order_date REGEXP '^[0-9]{2}/[0-9]{2}/[0-9]{4}$'
                AND STR_TO_DATE(o.order_date, '%d/%m/%Y') <= CURDATE())
        )
        THEN TRUE
    ELSE FALSE
END AS is_valid_order
```

**Por quê — o bug:**
`STR_TO_DATE('01/08/2023', '%Y-%m-%d')` retorna `NULL` porque o formato não corresponde. O CASE avalia `NULL <= CURDATE()` que é `NULL` (nem TRUE nem FALSE), portanto cai no `ELSE FALSE`. O pedido `ORD008` (C008, formato `01/08/2023`) seria marcado como inválido incorretamente, excluindo esse cliente e seus itens das análises Gold.

---

### [CORREÇÃO S4] COALESCE em `calculated_subtotal`

**Original:**
```sql
CAST(oi.quantity AS UNSIGNED) * CAST(oi.unit_price AS DECIMAL(10,2)) AS calculated_subtotal
```

**Corrigido:**
```sql
COALESCE(
    CASE WHEN oi.quantity REGEXP '^[0-9]+$' THEN CAST(oi.quantity AS UNSIGNED) ELSE 1 END,
    1
) *
COALESCE(
    CASE WHEN CAST(oi.unit_price AS DECIMAL(10,2)) >= 0
         THEN CAST(oi.unit_price AS DECIMAL(10,2)) END,
    0
) AS calculated_subtotal
```

**Por quê:**
Em MySQL, `CAST('abc' AS UNSIGNED)` retorna `0` com um warning, não um erro. Mas `CAST(NULL AS DECIMAL)` retorna `NULL`, e `NULL * qualquer_coisa = NULL`. Se `unit_price` for `NULL` (pedido sem preço), `calculated_subtotal` seria `NULL`, e a comparação `ABS(subtotal - NULL) < 0.01` também seria `NULL`, fazendo `subtotal_matches = FALSE` mesmo para registros onde a validação não se aplica. O COALESCE garante um valor padrão defensivo.

---

### [MELHORIA S5] Índices nas tabelas Silver

**Original:** Sem índices nas colunas de join nas tabelas Silver.

**Corrigido:**
```sql
-- Em fact_orders:
INDEX idx_customer_id  (customer_id),
INDEX idx_order_date   (order_date),
INDEX idx_valid_status (is_valid_order, order_status)

-- Em fact_order_items:
INDEX idx_order_id (order_id),
INDEX idx_book_id  (book_id)

-- Em fact_reviews:
INDEX idx_book_id     (book_id),
INDEX idx_customer_id (customer_id),
INDEX idx_rating      (rating)
```

**Por quê:**
As views Gold fazem múltiplos JOINs entre Silver tables. Sem índices nas colunas de join (`customer_id`, `order_id`, `book_id`), cada JOIN é um full table scan. O índice composto `(is_valid_order, order_status)` é especialmente útil porque toda view Gold filtra `WHERE is_valid_order = TRUE AND order_status != 'Cancelado'`.

---

## Arquivo 3: `3_gold_corrected.sql`

### [CORREÇÃO G1] Arquivo consolidado — eliminação de duplicatas

**Original:** O `3.sql` original contém:
1. Views criadas com `CREATE VIEW` (linhas 24–209)
2. Tabelas agregadas `agg_daily_metrics` e `agg_author_performance` (linhas 215–306)
3. **Bloco SQL órfão** — queries raw sem contexto (linhas 323–337)
4. **Mesmas views recriadas** com `CREATE OR REPLACE VIEW` (linhas 343–510)
5. **Tabelas duplicadas**: `agg_daily_metrics2` e `agg_author_performance2` (linhas 516–608)
6. Verificação final (linhas 614–624)

**Por quê o arquivo duplicado é problemático:**
- A primeira `CREATE VIEW vw_sales_by_category` (linha 24) é criada, depois a `CREATE OR REPLACE VIEW` na linha 343 sobrescreve com lógica ligeiramente diferente. Um desenvolvedor lendo o arquivo não sabe qual versão está ativa.
- `agg_daily_metrics2` e `agg_author_performance2` são tabelas sem uso nas verificações — servem apenas para confundir.
- O bloco SQL nas linhas 323–337 executa uma query de `vw_sales_by_category` sem criar nenhum objeto, apenas retornando um resultset temporário. Em produção, esse bloco geraria output inesperado no log de execução.

**Corrigido:** Um único arquivo limpo com `CREATE OR REPLACE VIEW` para todas as views e `CREATE TABLE` único por entidade agregada.

---

### [CORREÇÃO G2] Filtro LEFT JOIN no ON vs. WHERE

**Afeta:** `vw_top_selling_books`, `vw_customer_analytics`, `vw_geographic_analysis`

**Original (versão 2 no 3.sql):**
```sql
FROM silver_layer.dim_books b
LEFT JOIN silver_layer.fact_order_items oi ON b.book_id = oi.book_id
LEFT JOIN silver_layer.fact_orders o ON oi.order_id = o.order_id
LEFT JOIN silver_layer.fact_reviews fr ON b.book_id = fr.book_id
WHERE o.is_valid_order = TRUE     ← PROBLEMA
    AND o.order_status != 'Cancelado'
```

**Corrigido:**
```sql
FROM silver_layer.dim_books b
LEFT JOIN silver_layer.fact_order_items oi ON b.book_id  = oi.book_id
LEFT JOIN silver_layer.fact_orders      o  ON oi.order_id = o.order_id
    AND o.is_valid_order = TRUE           ← CORRETO
    AND o.order_status != 'Cancelado'
LEFT JOIN silver_layer.fact_reviews fr ON b.book_id = fr.book_id
```

**Por quê — o bug é sutil mas grave:**
Em SQL, quando uma condição no `WHERE` referencia uma coluna de uma tabela em `LEFT JOIN`, o banco de dados **converte o LEFT JOIN em INNER JOIN implicitamente**. Isso ocorre porque o WHERE exige que `o.is_valid_order = TRUE` — mas registros onde o LEFT JOIN não encontrou correspondência teriam `o.is_valid_order = NULL`, e `NULL = TRUE` é FALSE, excluindo a linha.

Resultado prático: `vw_top_selling_books` excluía livros sem pedidos válidos. `vw_customer_analytics` excluía clientes sem histórico de compra. `vw_geographic_analysis` excluía estados sem pedidos válidos. A análise ficava **enviesada** — mostrando apenas o subconjunto de "tudo que funcionou", sem visibilidade sobre ausências.

---

### [CORREÇÃO G3] NULLIF para divisão segura em `vw_review_analytics`

**Original (versão 2, linha ~500):**
```sql
ROUND(
    (SUM(CASE WHEN fr.rating >= 4 THEN 1 ELSE 0 END) * 100.0) /
    COUNT(fr.review_id),    ← divisão por zero possível
    2
) AS positive_review_percentage
```

**Corrigido:**
```sql
ROUND(
    (SUM(CASE WHEN fr.rating >= 4 THEN 1 ELSE 0 END) * 100.0) /
    NULLIF(COUNT(fr.review_id), 0),    ← seguro
    2
) AS positive_review_percentage
```

**Por quê:**
Se um livro não tem reviews (ou todas as reviews são inválidas e são filtradas pelo `HAVING > 0`), `COUNT(fr.review_id)` retorna 0. Em MySQL, divisão por zero retorna `NULL` (sem erro), mas em outros databases pode levantar exception. O `NULLIF(count, 0)` torna explícito que o resultado é `NULL` quando não há reviews, evitando comportamento ambíguo.

---

### [CORREÇÃO G4] Filtro `is_valid_review` no ON clause em `vw_review_analytics`

**Original (versão 2):**
```sql
FROM silver_layer.dim_books b
LEFT JOIN silver_layer.fact_reviews fr ON b.book_id = fr.book_id
WHERE fr.is_valid_review = TRUE     ← converte LEFT JOIN em INNER JOIN
```

**Corrigido:**
```sql
FROM silver_layer.dim_books b
LEFT JOIN silver_layer.fact_reviews fr ON b.book_id = fr.book_id AND fr.is_valid_review = TRUE
```

**Por quê:**
Mesmo raciocínio da CORREÇÃO G2. Com o filtro no WHERE, livros sem reviews válidas (como B005, B011 com problemas) são excluídos da view. Com o filtro no ON, esses livros aparecem com `total_reviews = 0` e são então filtrados pelo `HAVING total_reviews > 0` — comportamento explícito e controlável.

---

### [CORREÇÃO G5] COALESCE em subquery de `most_popular_book`

**Original:**
```sql
ORDER BY SUM(oi2.quantity) DESC    ← SUM pode ser NULL para livros sem venda
```

**Corrigido:**
```sql
ORDER BY SUM(COALESCE(oi2.quantity, 0)) DESC    ← ordenação determinística
```

**Por quê:**
Quando um autor tem um livro sem nenhuma venda, `LEFT JOIN fact_order_items` retorna NULL para `oi2.quantity`, e `SUM(NULL) = NULL`. Em MySQL, NULL é tratado como o **menor valor** em ORDER BY ASC mas o comportamento em DESC é inconsistente entre versões: alguns tratam NULL como maior, outros como menor. O resultado é que `most_popular_book` pode retornar um livro sem vendas como "mais popular" para um autor. `COALESCE(..., 0)` garante que livros sem vendas recebam `SUM = 0` e fiquem no final do ranking.

---

## Resumo das Correções

| # | Arquivo | Tipo | Impacto |
|---|---------|------|---------|
| B1 | Bronze | Melhoria | Charset garante suporte a caracteres PT-BR |
| B2 | Bronze | Melhoria | Índices melhoram performance de deduplicação |
| S1 | Silver | **Bug crítico** | Deduplicação falha em produção com timestamps diferentes |
| S2 | Silver | Melhoria | Score de qualidade mede formatos válidos, não apenas NOT NULL |
| S3 | Silver | **Bug crítico** | Pedidos com data DD/MM/YYYY marcados como inválidos incorretamente |
| S4 | Silver | Bug | calculated_subtotal pode ser NULL com operandos NULL |
| S5 | Silver | Melhoria | Índices eliminam full table scans nas queries Gold |
| G1 | Gold | Melhoria | Arquivo limpo sem duplicatas de objetos e queries órfãs |
| G2 | Gold | **Bug crítico** | WHERE em LEFT JOIN converte para INNER JOIN, análises enviesadas |
| G3 | Gold | Bug | Divisão por zero sem NULLIF produz NULL inesperado |
| G4 | Gold | **Bug crítico** | WHERE em LEFT JOIN para reviews excluía livros sem review válida |
| G5 | Gold | Bug | ORDER BY SUM(NULL) com comportamento não determinístico |

**Legenda:**
- **Bug crítico** — causa resultado incorreto silenciosamente, sem erro explícito
- **Bug** — pode causar erro ou resultado incorreto em condições específicas
- **Melhoria** — comportamento correto com melhor performance ou robustez
