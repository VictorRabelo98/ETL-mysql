# Arquitetura Técnica: Pipeline ETL Medallion

## Visão Geral

Este projeto implementa a **Arquitetura Medallion** (também chamada de Delta Architecture ou Multi-Hop Architecture) inteiramente em MySQL. A filosofia central é a progressão de dados por camadas de qualidade crescente, preservando os dados originais em cada etapa.

---

## Diagrama de Fluxo Completo

```
┌──────────────────────────────────────────────────────────────────┐
│                    FONTES DE DADOS (Externas)                    │
│   CRM / ERP / Formulário Web / Marketplace / Sistema Legado      │
└──────────────────────────────┬───────────────────────────────────┘
                               │ INSERT INTO bronze_layer.*
                               ▼
┌──────────────────────────────────────────────────────────────────┐
│                      BRONZE LAYER                                │
│                  Schema: bronze_layer                            │
│                                                                  │
│  ┌─────────────────┐  ┌─────────────────┐  ┌────────────────┐  │
│  │  raw_customers  │  │   raw_books     │  │  raw_orders    │  │
│  │  (11 registros) │  │  (12 registros) │  │ (12 registros) │  │
│  └─────────────────┘  └─────────────────┘  └────────────────┘  │
│                                                                  │
│  ┌──────────────────────┐  ┌────────────────────┐              │
│  │  raw_order_items     │  │   raw_reviews      │              │
│  │  (22 registros)      │  │  (12 registros)    │              │
│  └──────────────────────┘  └────────────────────┘              │
│                                                                  │
│  Características:                                                │
│  • Todos campos VARCHAR (sem tipagem)                            │
│  • Sem constraints de FK                                         │
│  • Dados com erros preservados                                   │
│  • Imutável (append-only em produção)                            │
└──────────────────────────────┬───────────────────────────────────┘
                               │ SELECT + TRANSFORM + INSERT
                               │ (2.sql)
                               ▼
┌──────────────────────────────────────────────────────────────────┐
│                      SILVER LAYER                                │
│                  Schema: silver_layer                            │
│                                                                  │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │              Dimensões (Dimension Tables)                │    │
│  │                                                         │    │
│  │  dim_customers        dim_books                         │    │
│  │  • customer_key PK    • book_key PK                     │    │
│  │  • customer_id UQ     • book_id UQ                      │    │
│  │  • email_valid BOOL   • price DECIMAL                   │    │
│  │  • state CHAR(2)      • publication_year INT            │    │
│  │  • age INT            • avg_rating DECIMAL              │    │
│  │  • quality_score      • is_available BOOL               │    │
│  │                       • quality_score                   │    │
│  └────────────────────┬────────────────────────────────────┘    │
│                       │ FK references                            │
│  ┌────────────────────▼────────────────────────────────────┐    │
│  │                Fatos (Fact Tables)                       │    │
│  │                                                         │    │
│  │  fact_orders          fact_order_items  fact_reviews     │    │
│  │  • order_key PK       • item_key PK     • review_key PK │    │
│  │  • customer_id FK     • order_id FK     • book_id FK    │    │
│  │  • order_date DATE    • book_id FK      • customer_id FK│    │
│  │  • is_valid_order     • subtotal_match  • rating INT    │    │
│  │  • quality_score      • calc_subtotal   • is_valid BOOL │    │
│  └─────────────────────────────────────────────────────────┘    │
└──────────────────────────────┬───────────────────────────────────┘
                               │ SELECT + AGGREGATE + CREATE VIEW
                               │ (3.sql)
                               ▼
┌──────────────────────────────────────────────────────────────────┐
│                       GOLD LAYER                                 │
│                   Schema: gold_layer                             │
│                                                                  │
│  Views Analíticas (7):           Tabelas Agregadas (2):         │
│  • vw_sales_by_category          • agg_daily_metrics            │
│  • vw_top_selling_books          • agg_author_performance        │
│  • vw_customer_analytics                                        │
│  • vw_sales_over_time                                           │
│  • vw_payment_analysis                                          │
│  • vw_geographic_analysis                                       │
│  • vw_review_analytics                                          │
└──────────────────────────────────────────────────────────────────┘
```

---

## Modelo de Dados: Silver Layer

### Diagrama Entidade-Relacionamento

```
dim_customers                    dim_books
─────────────                    ─────────
customer_key PK                  book_key PK
customer_id UQ ←──┐    ┌──────→ book_id UQ
full_name          │    │         title
email              │    │         author
email_valid        │    │         category
phone              │    │         price
registration_date  │    │         stock_quantity
city               │    │         avg_rating
state              │    │         is_available
country            │    │         data_quality_score
birth_date         │    │
age                │    │
data_quality_score │    │
                   │    │
fact_orders        │    │         fact_order_items
───────────        │    │         ────────────────
order_key PK       │    │         order_item_key PK
order_id UQ        │    └──────── book_id FK
customer_id FK ────┘         ┌── order_id FK
order_date                   │   quantity
total_amount                 │   unit_price
payment_method               │   subtotal
order_status                 │   calculated_subtotal
shipping_cost                │   subtotal_matches
discount_applied             │
net_amount                   │
is_valid_order               │
data_quality_score           │
       │                     │
       └─────────────────────┘

fact_reviews
────────────
review_key PK
review_id UQ
book_id FK ──────────────── dim_books.book_id
customer_id FK ──────────── dim_customers.customer_id
rating
review_text
review_date
helpful_count
review_length
is_valid_review
```

---

## Padrões de Transformação

### Detecção de Formato de Data (Multi-Pattern)

```sql
-- Padrão aplicado em múltiplas tabelas Silver
CASE
    WHEN campo REGEXP '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
        THEN STR_TO_DATE(campo, '%Y-%m-%d')     -- ISO 8601
    WHEN campo REGEXP '^[0-9]{4}/[0-9]{2}/[0-9]{2}$'
        THEN STR_TO_DATE(campo, '%Y/%m/%d')     -- Formato barra ISO
    WHEN campo REGEXP '^[0-9]{2}/[0-9]{2}/[0-9]{4}$'
        THEN STR_TO_DATE(campo, '%d/%m/%Y')     -- Formato brasileiro
    WHEN campo REGEXP '^[0-9]{2}-[0-9]{2}-[0-9]{4}$'
        THEN STR_TO_DATE(campo, '%d-%m-%Y')     -- Formato brasileiro com hífen
    ELSE NULL
END
```

### Normalização de Texto

```sql
-- Remove espaços duplos, mantém capitalização correta
TRIM(REGEXP_REPLACE(full_name, '\\s+', ' ')) AS full_name

-- Capitaliza primeira letra, resto minúsculo (para cidades)
CONCAT(
    UPPER(SUBSTRING(TRIM(city), 1, 1)),
    LOWER(SUBSTRING(TRIM(city), 2))
) AS city
```

### Score de Qualidade por Entidade

```sql
-- dim_customers (5 critérios × 0.20)
(CASE WHEN customer_id IS NOT NULL AND customer_id != '' THEN 0.20 ELSE 0 END) +
(CASE WHEN email REGEXP '^[A-Za-z0-9._%+-]+@...' THEN 0.20 ELSE 0 END) +
(CASE WHEN phone IS NOT NULL AND phone != '' THEN 0.20 ELSE 0 END) +
(CASE WHEN registration_date IS NOT NULL THEN 0.20 ELSE 0 END) +
(CASE WHEN birth_date IS NOT NULL THEN 0.20 ELSE 0 END)

-- dim_books (7 critérios com pesos diferentes)
(CASE WHEN book_id IS NOT NULL THEN 0.15 ELSE 0 END) +
(CASE WHEN title IS NOT NULL AND title != '' THEN 0.15 ELSE 0 END) +
(CASE WHEN author IS NOT NULL AND author != '' THEN 0.15 ELSE 0 END) +
(CASE WHEN publication_year BETWEEN 1000 AND YEAR(CURDATE()) THEN 0.15 ELSE 0 END) +
(CASE WHEN isbn IS NOT NULL AND isbn != '' THEN 0.10 ELSE 0 END) +
(CASE WHEN price > 0 THEN 0.15 ELSE 0 END) +
(CASE WHEN rating BETWEEN 0 AND 5 THEN 0.15 ELSE 0 END)
```

---

## Análise de Segmentação na Gold Layer

### RFM Simplificado (Recência, Frequência, Monetário)

```sql
-- Recência → customer_status
CASE
    WHEN DATEDIFF(CURDATE(), MAX(order_date)) <= 60  THEN 'Ativo'
    WHEN DATEDIFF(CURDATE(), MAX(order_date)) <= 180 THEN 'Em Risco'
    ELSE 'Inativo'
END

-- Monetário → customer_tier
CASE
    WHEN SUM(total_amount) >= 300 THEN 'VIP'
    WHEN SUM(total_amount) >= 150 THEN 'Regular'
    ELSE 'Novo'
END
```

---

## Considerações de Performance

### Índices Recomendados

```sql
-- Silver Layer: Índices nas colunas de junção frequente
CREATE INDEX idx_fact_orders_customer ON silver_layer.fact_orders(customer_id);
CREATE INDEX idx_fact_orders_date     ON silver_layer.fact_orders(order_date);
CREATE INDEX idx_fact_orders_status   ON silver_layer.fact_orders(order_status, is_valid_order);
CREATE INDEX idx_fact_items_order     ON silver_layer.fact_order_items(order_id);
CREATE INDEX idx_fact_items_book      ON silver_layer.fact_order_items(book_id);
CREATE INDEX idx_fact_reviews_book    ON silver_layer.fact_reviews(book_id);
CREATE INDEX idx_fact_reviews_cust    ON silver_layer.fact_reviews(customer_id);

-- Gold Layer: Índice na data para métricas diárias
CREATE INDEX idx_daily_date ON gold_layer.agg_daily_metrics(metric_date);
```

### Subqueries vs JOINs

As subqueries correlacionadas em `agg_author_performance` (para `most_popular_book` e `most_popular_category`) são O(n²) em relação ao número de autores. Para datasets grandes, substituir por CTEs com `ROW_NUMBER()`:

```sql
WITH author_books_ranked AS (
    SELECT
        b.author,
        b.title,
        ROW_NUMBER() OVER (
            PARTITION BY b.author
            ORDER BY SUM(COALESCE(oi.quantity, 0)) DESC
        ) AS rn
    FROM silver_layer.dim_books b
    LEFT JOIN silver_layer.fact_order_items oi ON b.book_id = oi.book_id
    GROUP BY b.author, b.title
)
SELECT author, title AS most_popular_book
FROM author_books_ranked
WHERE rn = 1;
```

---

## Escalabilidade

Este pipeline foi projetado para demonstração com um dataset pequeno, mas segue padrões que escalam:

| Volume | Estratégia |
|--------|-----------|
| Até 1M registros | Scripts SQL conforme implementado |
| 1M–50M registros | Adicionar índices, particionamento por data em fact_orders |
| 50M+ registros | Migrar para Spark/dbt mantendo a mesma lógica de negócio |
| Real-time | Adicionar camada de streaming (Kafka) antes do Bronze; manter Silver/Gold idênticos |

A **lógica de transformação** documentada aqui é portável. Os mesmos padrões de validação, normalização e scoring funcionam em qualquer engine SQL.
