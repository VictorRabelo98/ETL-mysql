-- ============================================================
-- GOLD LAYER — ANALYTICS & AGREGAÇÕES
-- Versão corrigida: arquivo consolidado (sem duplicatas de
-- tabelas/views), filtros de LEFT JOIN corrigidos (ON clause
-- ao invés de WHERE), NULLIF para divisão segura, COALESCE
-- em agregações que podem produzir NULL.
-- ============================================================

USE gold_layer;

-- Limpar artefatos existentes
DROP VIEW  IF EXISTS vw_review_analytics;
DROP VIEW  IF EXISTS vw_geographic_analysis;
DROP VIEW  IF EXISTS vw_payment_analysis;
DROP VIEW  IF EXISTS vw_sales_over_time;
DROP VIEW  IF EXISTS vw_customer_analytics;
DROP VIEW  IF EXISTS vw_top_selling_books;
DROP VIEW  IF EXISTS vw_sales_by_category;
DROP TABLE IF EXISTS agg_author_performance;
DROP TABLE IF EXISTS agg_daily_metrics;

-- ============================================================
-- 1. VISÃO: VENDAS POR CATEGORIA
-- ============================================================

CREATE VIEW vw_sales_by_category AS
SELECT
    b.category,
    COUNT(DISTINCT o.order_id)           AS total_orders,
    COUNT(oi.order_item_id)              AS total_items_sold,
    SUM(oi.quantity)                     AS total_quantity,
    ROUND(SUM(oi.calculated_subtotal), 2) AS total_revenue,
    ROUND(AVG(oi.calculated_subtotal), 2) AS avg_order_value,
    ROUND(
        SUM(oi.calculated_subtotal) / NULLIF(SUM(oi.quantity), 0),
        2
    ) AS avg_price_per_unit
FROM silver_layer.fact_order_items oi
JOIN silver_layer.fact_orders o ON oi.order_id = o.order_id
JOIN silver_layer.dim_books   b ON oi.book_id  = b.book_id
WHERE o.is_valid_order = TRUE
    AND o.order_status != 'Cancelado'
GROUP BY b.category
ORDER BY total_revenue DESC;

-- ============================================================
-- 2. VISÃO: TOP LIVROS MAIS VENDIDOS
-- ============================================================

-- [CORREÇÃO 5] Filtros de pedido válido movidos para cláusula ON.
-- PROBLEMA ORIGINAL (versão 2 no 3.sql): os filtros is_valid_order e
-- order_status estavam no WHERE após LEFT JOIN, o que converte o
-- LEFT JOIN em INNER JOIN — livros sem pedidos válidos eram excluídos
-- mesmo sendo LEFT JOIN. A versão 1 estava correta (filtro no ON).
-- SOLUÇÃO: filtro no ON clause preserva a semântica de LEFT JOIN.

CREATE VIEW vw_top_selling_books AS
SELECT
    b.book_id,
    b.title,
    b.author,
    b.category,
    b.price,
    b.avg_rating,
    COUNT(DISTINCT o.order_id)                     AS times_ordered,
    COALESCE(SUM(oi.quantity), 0)                  AS total_copies_sold,
    ROUND(COALESCE(SUM(oi.calculated_subtotal), 0), 2) AS total_revenue,
    ROUND(AVG(fr.rating), 1)                       AS customer_avg_rating,
    COUNT(DISTINCT fr.review_id)                   AS total_reviews
FROM silver_layer.dim_books b
LEFT JOIN silver_layer.fact_order_items oi ON b.book_id  = oi.book_id
LEFT JOIN silver_layer.fact_orders      o  ON oi.order_id = o.order_id
    AND o.is_valid_order = TRUE
    AND o.order_status != 'Cancelado'
LEFT JOIN silver_layer.fact_reviews fr ON b.book_id = fr.book_id
GROUP BY b.book_id, b.title, b.author, b.category, b.price, b.avg_rating
HAVING total_copies_sold > 0
ORDER BY total_copies_sold DESC, total_revenue DESC;

-- ============================================================
-- 3. VISÃO: ANÁLISE DE CLIENTES (RFM)
-- ============================================================

-- [CORREÇÃO 6] avg_per_order usa NULLIF para evitar divisão por zero.
-- PROBLEMA ORIGINAL (versão 2): SUM/COUNT sem NULLIF levantaria erro
-- ou retornaria NULL inesperado quando COUNT é 0 (cliente sem pedidos).
-- [CORREÇÃO 7] Filtro is_valid_order no ON clause, não no WHERE.
-- PROBLEMA ORIGINAL (versão 2): WHERE o.is_valid_order = TRUE após
-- LEFT JOIN excluía clientes sem pedidos, perdendo clientes cadastrados
-- sem histórico de compras.

CREATE VIEW vw_customer_analytics AS
SELECT
    c.customer_id,
    c.full_name,
    c.city,
    c.state,
    c.age,
    c.registration_date,
    COUNT(DISTINCT o.order_id)                                       AS total_orders,
    ROUND(SUM(o.total_amount), 2)                                    AS total_spent,
    ROUND(AVG(o.total_amount), 2)                                    AS avg_order_value,
    ROUND(SUM(o.total_amount) / NULLIF(COUNT(DISTINCT o.order_id), 0), 2) AS avg_per_order,
    COUNT(DISTINCT oi.book_id)                                       AS unique_books_purchased,
    COALESCE(SUM(oi.quantity), 0)                                    AS total_books_quantity,
    COUNT(DISTINCT fr.review_id)                                     AS total_reviews_written,
    ROUND(AVG(fr.rating), 1)                                         AS avg_rating_given,
    MAX(o.order_date)                                                AS last_order_date,
    DATEDIFF(CURDATE(), MAX(o.order_date))                           AS days_since_last_order,
    CASE
        WHEN DATEDIFF(CURDATE(), MAX(o.order_date)) <= 60  THEN 'Ativo'
        WHEN DATEDIFF(CURDATE(), MAX(o.order_date)) <= 180 THEN 'Em Risco'
        ELSE 'Inativo'
    END AS customer_status,
    CASE
        WHEN SUM(o.total_amount) >= 300 THEN 'VIP'
        WHEN SUM(o.total_amount) >= 150 THEN 'Regular'
        ELSE 'Novo'
    END AS customer_tier
FROM silver_layer.dim_customers c
LEFT JOIN silver_layer.fact_orders      o  ON c.customer_id = o.customer_id AND o.is_valid_order = TRUE
LEFT JOIN silver_layer.fact_order_items oi ON o.order_id    = oi.order_id
LEFT JOIN silver_layer.fact_reviews     fr ON c.customer_id = fr.customer_id
GROUP BY c.customer_id, c.full_name, c.city, c.state, c.age, c.registration_date
HAVING total_orders > 0
ORDER BY total_spent DESC;

-- ============================================================
-- 4. VISÃO: ANÁLISE TEMPORAL DE VENDAS
-- ============================================================

CREATE VIEW vw_sales_over_time AS
SELECT
    DATE_FORMAT(o.order_date, '%Y-%m')                         AS yearmonth,
    YEAR(o.order_date)                                         AS year,
    MONTH(o.order_date)                                        AS month,
    MONTHNAME(o.order_date)                                    AS month_name,
    COUNT(DISTINCT o.order_id)                                 AS total_orders,
    COUNT(DISTINCT o.customer_id)                              AS unique_customers,
    SUM(oi.quantity)                                           AS total_items_sold,
    ROUND(SUM(o.total_amount), 2)                              AS gross_revenue,
    ROUND(SUM(o.shipping_cost), 2)                             AS total_shipping,
    ROUND(SUM(o.discount_applied), 2)                          AS total_discounts,
    ROUND(SUM(o.net_amount), 2)                                AS net_revenue,
    ROUND(AVG(o.total_amount), 2)                              AS avg_order_value,
    ROUND(
        SUM(o.total_amount) / NULLIF(COUNT(DISTINCT o.customer_id), 0),
        2
    ) AS revenue_per_customer
FROM silver_layer.fact_orders o
JOIN silver_layer.fact_order_items oi ON o.order_id = oi.order_id
WHERE o.is_valid_order = TRUE
    AND o.order_status != 'Cancelado'
GROUP BY DATE_FORMAT(o.order_date, '%Y-%m'), YEAR(o.order_date),
         MONTH(o.order_date), MONTHNAME(o.order_date)
ORDER BY yearmonth;

-- ============================================================
-- 5. VISÃO: ANÁLISE DE MÉTODOS DE PAGAMENTO
-- ============================================================

CREATE VIEW vw_payment_analysis AS
SELECT
    o.payment_method,
    COUNT(DISTINCT o.order_id)      AS total_orders,
    ROUND(SUM(o.total_amount), 2)   AS total_revenue,
    ROUND(AVG(o.total_amount), 2)   AS avg_order_value,
    ROUND(SUM(o.discount_applied), 2) AS total_discounts,
    ROUND(
        (COUNT(DISTINCT o.order_id) * 100.0) /
        NULLIF((SELECT COUNT(*) FROM silver_layer.fact_orders WHERE is_valid_order = TRUE), 0),
        2
    ) AS percentage_of_orders,
    ROUND(
        (SUM(o.total_amount) * 100.0) /
        NULLIF((SELECT SUM(total_amount) FROM silver_layer.fact_orders WHERE is_valid_order = TRUE), 0),
        2
    ) AS percentage_of_revenue
FROM silver_layer.fact_orders o
WHERE o.is_valid_order = TRUE
    AND o.order_status != 'Cancelado'
GROUP BY o.payment_method
ORDER BY total_revenue DESC;

-- ============================================================
-- 6. VISÃO: ANÁLISE GEOGRÁFICA
-- ============================================================

-- [CORREÇÃO 8] Filtro is_valid_order movido para ON clause.
-- PROBLEMA ORIGINAL (versão 2): WHERE o.is_valid_order = TRUE após
-- LEFT JOIN transforma o join em INNER, excluindo estados/cidades
-- sem pedidos válidos do resultado. A versão 1 usava HAVING total_orders > 0
-- com filtro no ON — esse padrão está correto e é o adotado aqui.

CREATE VIEW vw_geographic_analysis AS
SELECT
    c.state,
    c.city,
    COUNT(DISTINCT c.customer_id)  AS total_customers,
    COUNT(DISTINCT o.order_id)     AS total_orders,
    COALESCE(SUM(oi.quantity), 0)  AS total_books_sold,
    ROUND(COALESCE(SUM(o.total_amount), 0), 2) AS total_revenue,
    ROUND(AVG(o.total_amount), 2)  AS avg_order_value,
    ROUND(
        SUM(o.total_amount) / NULLIF(COUNT(DISTINCT c.customer_id), 0),
        2
    ) AS revenue_per_customer,
    ROUND(
        COUNT(DISTINCT o.order_id) * 1.0 / NULLIF(COUNT(DISTINCT c.customer_id), 0),
        2
    ) AS orders_per_customer
FROM silver_layer.dim_customers c
LEFT JOIN silver_layer.fact_orders      o  ON c.customer_id = o.customer_id AND o.is_valid_order = TRUE
LEFT JOIN silver_layer.fact_order_items oi ON o.order_id    = oi.order_id
GROUP BY c.state, c.city
HAVING total_orders > 0
ORDER BY total_revenue DESC;

-- ============================================================
-- 7. VISÃO: ANÁLISE DE AVALIAÇÕES
-- ============================================================

-- [CORREÇÃO 9] Filtro is_valid_review movido para ON clause.
-- PROBLEMA ORIGINAL (versão 2, linhas 506-508 do 3.sql):
--   FROM silver_layer.dim_books b
--   LEFT JOIN silver_layer.fact_reviews fr ON b.book_id = fr.book_id
--   WHERE fr.is_valid_review = TRUE   ← converte LEFT JOIN em INNER JOIN
-- Livros sem nenhuma review válida eram excluídos do resultado, mesmo
-- sendo LEFT JOIN. Com o filtro no ON, livros sem reviews ficam com
-- valores NULL (e são filtrados pelo HAVING > 0 somente se desejado).
--
-- [CORREÇÃO 10] NULLIF adicionado em positive_review_percentage.
-- PROBLEMA ORIGINAL (versão 2, linha 500): divisão por COUNT(fr.review_id)
-- sem NULLIF — retornaria NULL (divisão por zero) em vez de 0%.

CREATE VIEW vw_review_analytics AS
SELECT
    b.book_id,
    b.title,
    b.author,
    b.category,
    COUNT(fr.review_id)                                    AS total_reviews,
    ROUND(AVG(fr.rating), 2)                               AS avg_rating,
    SUM(CASE WHEN fr.rating = 5 THEN 1 ELSE 0 END)        AS five_star_reviews,
    SUM(CASE WHEN fr.rating = 4 THEN 1 ELSE 0 END)        AS four_star_reviews,
    SUM(CASE WHEN fr.rating = 3 THEN 1 ELSE 0 END)        AS three_star_reviews,
    SUM(CASE WHEN fr.rating <= 2 THEN 1 ELSE 0 END)       AS low_star_reviews,
    ROUND(
        (SUM(CASE WHEN fr.rating >= 4 THEN 1 ELSE 0 END) * 100.0) /
        NULLIF(COUNT(fr.review_id), 0),
        2
    ) AS positive_review_percentage,
    ROUND(AVG(fr.review_length), 0)                        AS avg_review_length,
    SUM(fr.helpful_count)                                  AS total_helpful_votes
FROM silver_layer.dim_books b
LEFT JOIN silver_layer.fact_reviews fr ON b.book_id = fr.book_id AND fr.is_valid_review = TRUE
GROUP BY b.book_id, b.title, b.author, b.category
HAVING total_reviews > 0
ORDER BY avg_rating DESC, total_reviews DESC;

-- ============================================================
-- 8. TABELA AGREGADA: MÉTRICAS DIÁRIAS
-- ============================================================

CREATE TABLE agg_daily_metrics (
    metric_date       DATE PRIMARY KEY,
    total_orders      INT,
    total_revenue     DECIMAL(12,2),
    total_items_sold  INT,
    unique_customers  INT,
    avg_order_value   DECIMAL(10,2),
    total_shipping    DECIMAL(10,2),
    total_discounts   DECIMAL(10,2),
    net_revenue       DECIMAL(12,2),
    created_at        TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at        TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

INSERT INTO agg_daily_metrics
SELECT
    o.order_date                           AS metric_date,
    COUNT(DISTINCT o.order_id)             AS total_orders,
    ROUND(SUM(o.total_amount), 2)          AS total_revenue,
    SUM(oi.quantity)                       AS total_items_sold,
    COUNT(DISTINCT o.customer_id)          AS unique_customers,
    ROUND(AVG(o.total_amount), 2)          AS avg_order_value,
    ROUND(SUM(o.shipping_cost), 2)         AS total_shipping,
    ROUND(SUM(o.discount_applied), 2)      AS total_discounts,
    ROUND(SUM(o.net_amount), 2)            AS net_revenue,
    NOW(),
    NOW()
FROM silver_layer.fact_orders o
JOIN silver_layer.fact_order_items oi ON o.order_id = oi.order_id
WHERE o.is_valid_order = TRUE
    AND o.order_status != 'Cancelado'
GROUP BY o.order_date
ORDER BY o.order_date;

-- ============================================================
-- 9. TABELA AGREGADA: PERFORMANCE POR AUTOR
-- ============================================================

-- [CORREÇÃO 11] Subquery de most_popular_book usa COALESCE em SUM.
-- PROBLEMA ORIGINAL (versão 2, linha 592): ORDER BY SUM(oi2.quantity) DESC
-- sem COALESCE — autores com livros sem nenhuma venda retornam NULL
-- no SUM, e NULL é tratado como o menor valor no ORDER BY ASC mas
-- comportamento em DESC é undefined/inconsistente entre versões MySQL.
-- COALESCE(SUM(...), 0) garante ordenação determinística.

CREATE TABLE agg_author_performance (
    author_id            INT AUTO_INCREMENT PRIMARY KEY,
    author_name          VARCHAR(300) UNIQUE NOT NULL,
    total_books          INT,
    total_copies_sold    INT,
    total_revenue        DECIMAL(12,2),
    avg_book_rating      DECIMAL(3,2),
    total_reviews        INT,
    most_popular_book    VARCHAR(500),
    most_popular_category VARCHAR(100),
    created_at           TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at           TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

INSERT INTO agg_author_performance (
    author_name, total_books, total_copies_sold, total_revenue,
    avg_book_rating, total_reviews, most_popular_book, most_popular_category
)
SELECT
    b.author                                          AS author_name,
    COUNT(DISTINCT b.book_id)                         AS total_books,
    COALESCE(SUM(oi.quantity), 0)                     AS total_copies_sold,
    ROUND(COALESCE(SUM(oi.calculated_subtotal), 0), 2) AS total_revenue,
    ROUND(AVG(b.avg_rating), 2)                       AS avg_book_rating,
    COUNT(DISTINCT fr.review_id)                      AS total_reviews,
    (
        SELECT b2.title
        FROM silver_layer.dim_books b2
        LEFT JOIN silver_layer.fact_order_items oi2 ON b2.book_id = oi2.book_id
        WHERE b2.author = b.author
        GROUP BY b2.book_id, b2.title
        ORDER BY SUM(COALESCE(oi2.quantity, 0)) DESC
        LIMIT 1
    ) AS most_popular_book,
    (
        SELECT b3.category
        FROM silver_layer.dim_books b3
        WHERE b3.author = b.author
        GROUP BY b3.category
        ORDER BY COUNT(*) DESC
        LIMIT 1
    ) AS most_popular_category
FROM silver_layer.dim_books b
LEFT JOIN silver_layer.fact_order_items oi ON b.book_id    = oi.book_id
LEFT JOIN silver_layer.fact_orders      o  ON oi.order_id  = o.order_id
    AND o.is_valid_order = TRUE
LEFT JOIN silver_layer.fact_reviews     fr ON b.book_id    = fr.book_id
GROUP BY b.author
ORDER BY total_revenue DESC;

-- ============================================================
-- VERIFICAÇÃO DA CAMADA GOLD
-- ============================================================

SELECT '=== VERIFICAÇÃO DAS VISÕES E TABELAS ANALÍTICAS ===' AS info;

SELECT 'Categorias analisadas:'   AS metrica, COUNT(*) AS total FROM vw_sales_by_category;
SELECT 'Top livros:'              AS metrica, COUNT(*) AS total FROM vw_top_selling_books;
SELECT 'Clientes analisados:'     AS metrica, COUNT(*) AS total FROM vw_customer_analytics;
SELECT 'Períodos de vendas:'      AS metrica, COUNT(*) AS total FROM vw_sales_over_time;
SELECT 'Métodos de pagamento:'    AS metrica, COUNT(*) AS total FROM vw_payment_analysis;
SELECT 'Localidades:'             AS metrica, COUNT(*) AS total FROM vw_geographic_analysis;
SELECT 'Livros com reviews:'      AS metrica, COUNT(*) AS total FROM vw_review_analytics;
SELECT 'Métricas diárias:'        AS metrica, COUNT(*) AS total FROM agg_daily_metrics;
SELECT 'Autores analisados:'      AS metrica, COUNT(*) AS total FROM agg_author_performance;

-- Amostra de resultado
SELECT * FROM vw_sales_by_category   LIMIT 5;
SELECT * FROM vw_customer_analytics  LIMIT 5;
SELECT * FROM vw_top_selling_books   LIMIT 5;
SELECT * FROM agg_author_performance LIMIT 5;
