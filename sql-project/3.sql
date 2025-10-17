

-- ============================================
-- CAMADA GOLD - ANALYTICS & AGREGAÇÕES
-- ============================================

USE gold_layer;

-- Limpar views e tabelas existentes
DROP VIEW IF EXISTS vw_review_analytics;
DROP VIEW IF EXISTS vw_geographic_analysis;
DROP VIEW IF EXISTS vw_payment_analysis;
DROP VIEW IF EXISTS vw_sales_over_time;
DROP VIEW IF EXISTS vw_customer_analytics;
DROP VIEW IF EXISTS vw_top_selling_books;
DROP VIEW IF EXISTS vw_sales_by_category;
DROP TABLE IF EXISTS agg_author_performance;
DROP TABLE IF EXISTS agg_daily_metrics;

-- ============================================
-- 1. VISÃO: VENDAS POR CATEGORIA
-- ============================================

CREATE VIEW vw_sales_by_category AS
SELECT 
    b.category,
    COUNT(DISTINCT o.order_id) AS total_orders,
    COUNT(oi.order_item_id) AS total_items_sold,
    SUM(oi.quantity) AS total_quantity,
    ROUND(SUM(oi.calculated_subtotal), 2) AS total_revenue,
    ROUND(AVG(oi.calculated_subtotal), 2) AS avg_order_value,
    ROUND(SUM(oi.calculated_subtotal) / SUM(oi.quantity), 2) AS avg_price_per_unit
FROM silver_layer.fact_order_items oi
JOIN silver_layer.fact_orders o ON oi.order_id = o.order_id
JOIN silver_layer.dim_books b ON oi.book_id = b.book_id
WHERE o.is_valid_order = TRUE
    AND o.order_status != 'Cancelado'
GROUP BY b.category
ORDER BY total_revenue DESC;

-- ============================================
-- 2. VISÃO: TOP LIVROS MAIS VENDIDOS
-- ============================================

CREATE VIEW vw_top_selling_books AS
SELECT 
    b.book_id,
    b.title,
    b.author,
    b.category,
    b.price,
    b.avg_rating,
    COUNT(DISTINCT o.order_id) AS times_ordered,
    COALESCE(SUM(oi.quantity), 0) AS total_copies_sold,
    ROUND(COALESCE(SUM(oi.calculated_subtotal), 0), 2) AS total_revenue,
    ROUND(AVG(fr.rating), 1) AS customer_avg_rating,
    COUNT(DISTINCT fr.review_id) AS total_reviews
FROM silver_layer.dim_books b
LEFT JOIN silver_layer.fact_order_items oi ON b.book_id = oi.book_id
LEFT JOIN silver_layer.fact_orders o ON oi.order_id = o.order_id AND o.is_valid_order = TRUE AND o.order_status != 'Cancelado'
LEFT JOIN silver_layer.fact_reviews fr ON b.book_id = fr.book_id
GROUP BY b.book_id, b.title, b.author, b.category, b.price, b.avg_rating
HAVING total_copies_sold > 0
ORDER BY total_copies_sold DESC, total_revenue DESC;

-- ============================================
-- 3. VISÃO: ANÁLISE DE CLIENTES
-- ============================================

CREATE VIEW vw_customer_analytics AS
SELECT 
    c.customer_id,
    c.full_name,
    c.city,
    c.state,
    c.age,
    c.registration_date,
    COUNT(DISTINCT o.order_id) AS total_orders,
    ROUND(SUM(o.total_amount), 2) AS total_spent,
    ROUND(AVG(o.total_amount), 2) AS avg_order_value,
    ROUND(SUM(o.total_amount) / NULLIF(COUNT(DISTINCT o.order_id), 0), 2) AS avg_per_order,
    COUNT(DISTINCT oi.book_id) AS unique_books_purchased,
    COALESCE(SUM(oi.quantity), 0) AS total_books_quantity,
    COUNT(DISTINCT fr.review_id) AS total_reviews_written,
    ROUND(AVG(fr.rating), 1) AS avg_rating_given,
    MAX(o.order_date) AS last_order_date,
    DATEDIFF(CURDATE(), MAX(o.order_date)) AS days_since_last_order,
    CASE 
        WHEN DATEDIFF(CURDATE(), MAX(o.order_date)) <= 60 THEN 'Ativo'
        WHEN DATEDIFF(CURDATE(), MAX(o.order_date)) <= 180 THEN 'Em Risco'
        ELSE 'Inativo'
    END AS customer_status,
    CASE 
        WHEN SUM(o.total_amount) >= 300 THEN 'VIP'
        WHEN SUM(o.total_amount) >= 150 THEN 'Regular'
        ELSE 'Novo'
    END AS customer_tier
FROM silver_layer.dim_customers c
LEFT JOIN silver_layer.fact_orders o ON c.customer_id = o.customer_id AND o.is_valid_order = TRUE
LEFT JOIN silver_layer.fact_order_items oi ON o.order_id = oi.order_id
LEFT JOIN silver_layer.fact_reviews fr ON c.customer_id = fr.customer_id
GROUP BY c.customer_id, c.full_name, c.city, c.state, c.age, c.registration_date
HAVING total_orders > 0
ORDER BY total_spent DESC;

-- ============================================
-- 4. VISÃO: ANÁLISE TEMPORAL DE VENDAS
-- ============================================

CREATE VIEW vw_sales_over_time AS
SELECT 
    DATE_FORMAT(o.order_date, '%Y-%m') AS yearmonth,
    YEAR(o.order_date) AS year,
    MONTH(o.order_date) AS month,
    MONTHNAME(o.order_date) AS month_name,
    COUNT(DISTINCT o.order_id) AS total_orders,
    COUNT(DISTINCT o.customer_id) AS unique_customers,
    SUM(oi.quantity) AS total_items_sold,
    ROUND(SUM(o.total_amount), 2) AS gross_revenue,
    ROUND(SUM(o.shipping_cost), 2) AS total_shipping,
    ROUND(SUM(o.discount_applied), 2) AS total_discounts,
    ROUND(SUM(o.net_amount), 2) AS net_revenue,
    ROUND(AVG(o.total_amount), 2) AS avg_order_value,
    ROUND(SUM(o.total_amount) / COUNT(DISTINCT o.customer_id), 2) AS revenue_per_customer
FROM silver_layer.fact_orders o
JOIN silver_layer.fact_order_items oi ON o.order_id = oi.order_id
WHERE o.is_valid_order = TRUE
    AND o.order_status != 'Cancelado'
GROUP BY DATE_FORMAT(o.order_date, '%Y-%m'), YEAR(o.order_date), 
         MONTH(o.order_date), MONTHNAME(o.order_date)
ORDER BY yearmonth;

-- ============================================
-- 5. VISÃO: ANÁLISE DE MÉTODOS DE PAGAMENTO
-- ============================================

CREATE VIEW vw_payment_analysis AS
SELECT 
    o.payment_method,
    COUNT(DISTINCT o.order_id) AS total_orders,
    ROUND(SUM(o.total_amount), 2) AS total_revenue,
    ROUND(AVG(o.total_amount), 2) AS avg_order_value,
    ROUND(SUM(o.discount_applied), 2) AS total_discounts,
    ROUND(
        (COUNT(DISTINCT o.order_id) * 100.0) / 
        (SELECT COUNT(*) FROM silver_layer.fact_orders WHERE is_valid_order = TRUE),
        2
    ) AS percentage_of_orders,
    ROUND(
        (SUM(o.total_amount) * 100.0) / 
        (SELECT SUM(total_amount) FROM silver_layer.fact_orders WHERE is_valid_order = TRUE),
        2
    ) AS percentage_of_revenue
FROM silver_layer.fact_orders o
WHERE o.is_valid_order = TRUE
    AND o.order_status != 'Cancelado'
GROUP BY o.payment_method
ORDER BY total_revenue DESC;

-- ============================================
-- 6. VISÃO: ANÁLISE GEOGRÁFICA
-- ============================================

CREATE VIEW vw_geographic_analysis AS
SELECT 
    c.state,
    c.city,
    COUNT(DISTINCT c.customer_id) AS total_customers,
    COUNT(DISTINCT o.order_id) AS total_orders,
    COALESCE(SUM(oi.quantity), 0) AS total_books_sold,
    ROUND(COALESCE(SUM(o.total_amount), 0), 2) AS total_revenue,
    ROUND(AVG(o.total_amount), 2) AS avg_order_value,
    ROUND(SUM(o.total_amount) / NULLIF(COUNT(DISTINCT c.customer_id), 0), 2) AS revenue_per_customer,
    ROUND(COUNT(DISTINCT o.order_id) * 1.0 / NULLIF(COUNT(DISTINCT c.customer_id), 0), 2) AS orders_per_customer
FROM silver_layer.dim_customers c
LEFT JOIN silver_layer.fact_orders o ON c.customer_id = o.customer_id AND o.is_valid_order = TRUE
LEFT JOIN silver_layer.fact_order_items oi ON o.order_id = oi.order_id
GROUP BY c.state, c.city
HAVING total_orders > 0
ORDER BY total_revenue DESC;

-- ============================================
-- 7. VISÃO: ANÁLISE DE AVALIAÇÕES
-- ============================================

CREATE VIEW vw_review_analytics AS
SELECT 
    b.book_id,
    b.title,
    b.author,
    b.category,
    COUNT(fr.review_id) AS total_reviews,
    ROUND(AVG(fr.rating), 2) AS avg_rating,
    SUM(CASE WHEN fr.rating = 5 THEN 1 ELSE 0 END) AS five_star_reviews,
    SUM(CASE WHEN fr.rating = 4 THEN 1 ELSE 0 END) AS four_star_reviews,
    SUM(CASE WHEN fr.rating = 3 THEN 1 ELSE 0 END) AS three_star_reviews,
    SUM(CASE WHEN fr.rating <= 2 THEN 1 ELSE 0 END) AS low_star_reviews,
    ROUND(
        (SUM(CASE WHEN fr.rating >= 4 THEN 1 ELSE 0 END) * 100.0) / 
        NULLIF(COUNT(fr.review_id), 0), 
        2
    ) AS positive_review_percentage,
    ROUND(AVG(fr.review_length), 0) AS avg_review_length,
    SUM(fr.helpful_count) AS total_helpful_votes
FROM silver_layer.dim_books b
LEFT JOIN silver_layer.fact_reviews fr ON b.book_id = fr.book_id AND fr.is_valid_review = TRUE
GROUP BY b.book_id, b.title, b.author, b.category
HAVING total_reviews > 0
ORDER BY avg_rating DESC, total_reviews DESC;

-- ============================================
-- 8. TABELA AGREGADA: MÉTRICAS DIÁRIAS
-- ============================================

CREATE TABLE agg_daily_metrics (
    metric_date DATE PRIMARY KEY,
    total_orders INT,
    total_revenue DECIMAL(12,2),
    total_items_sold INT,
    unique_customers INT,
    avg_order_value DECIMAL(10,2),
    total_shipping DECIMAL(10,2),
    total_discounts DECIMAL(10,2),
    net_revenue DECIMAL(12,2),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

INSERT INTO agg_daily_metrics
SELECT 
    o.order_date AS metric_date,
    COUNT(DISTINCT o.order_id) AS total_orders,
    ROUND(SUM(o.total_amount), 2) AS total_revenue,
    SUM(oi.quantity) AS total_items_sold,
    COUNT(DISTINCT o.customer_id) AS unique_customers,
    ROUND(AVG(o.total_amount), 2) AS avg_order_value,
    ROUND(SUM(o.shipping_cost), 2) AS total_shipping,
    ROUND(SUM(o.discount_applied), 2) AS total_discounts,
    ROUND(SUM(o.net_amount), 2) AS net_revenue,
    NOW(),
    NOW()
FROM silver_layer.fact_orders o
JOIN silver_layer.fact_order_items oi ON o.order_id = oi.order_id
WHERE o.is_valid_order = TRUE
    AND o.order_status != 'Cancelado'
GROUP BY o.order_date
ORDER BY o.order_date;

-- ============================================
-- 9. TABELA AGREGADA: RESUMO POR AUTOR
-- ============================================

CREATE TABLE agg_author_performance (
    author_id INT AUTO_INCREMENT PRIMARY KEY,
    author_name VARCHAR(300) UNIQUE NOT NULL,
    total_books INT,
    total_copies_sold INT,
    total_revenue DECIMAL(12,2),
    avg_book_rating DECIMAL(3,2),
    total_reviews INT,
    most_popular_book VARCHAR(500),
    most_popular_category VARCHAR(100),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

INSERT INTO agg_author_performance (
    author_name,
    total_books,
    total_copies_sold,
    total_revenue,
    avg_book_rating,
    total_reviews,
    most_popular_book,
    most_popular_category
)
SELECT 
    b.author AS author_name,
    COUNT(DISTINCT b.book_id) AS total_books,
    COALESCE(SUM(oi.quantity), 0) AS total_copies_sold,
    ROUND(COALESCE(SUM(oi.calculated_subtotal), 0), 2) AS total_revenue,
    ROUND(AVG(b.avg_rating), 2) AS avg_book_rating,
    COUNT(DISTINCT fr.review_id) AS total_reviews,
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
LEFT JOIN silver_layer.fact_order_items oi ON b.book_id = oi.book_id
LEFT JOIN silver_layer.fact_orders o ON oi.order_id = o.order_id AND o.is_valid_order = TRUE
LEFT JOIN silver_layer.fact_reviews fr ON b.book_id = fr.book_id
GROUP BY b.author
ORDER BY total_revenue DESC;

-- ============================================
-- VERIFICAÇÃO DA CAMADA GOLD
-- ============================================

SELECT '=== VERIFICAÇÃO DAS VISÕES E TABELAS ANALÍTICAS ===' AS info;

SELECT 'Categorias analisadas:' AS metrica, COUNT(*) AS total FROM vw_sales_by_category;
SELECT 'Top livros:' AS metrica, COUNT(*) AS total FROM vw_top_selling_books;
SELECT 'Clientes analisados:' AS metrica, COUNT(*) AS total FROM vw_customer_analytics;
SELECT 'Períodos de vendas:' AS metrica, COUNT(*) AS total FROM vw_sales_over_time;
SELECT 'Métodos de pagamento:' AS metrica, COUNT(*) AS total FROM vw_payment_analysis;
SELECT 'Localidades:' AS metrica, COUNT(*) AS total FROM vw_geographic_analysis;
SELECT 'Livros com reviews:' AS metrica, COUNT(*) AS total FROM vw_review_analytics;
SELECT 'Métricas diárias:' AS metrica, COUNT(*) AS total FROM agg_daily_metrics;
SELECT 'Autores analisados:' AS metrica, COUNT(*) AS total FROM agg_author_performance;
SELECT 
    b.category,
    COUNT(DISTINCT o.order_id) AS total_orders,
    COUNT(oi.order_item_id) AS total_items_sold,
    SUM(oi.quantity) AS total_quantity,
    ROUND(SUM(oi.calculated_subtotal), 2) AS total_revenue,
    ROUND(AVG(oi.calculated_subtotal), 2) AS avg_order_value,
    ROUND(SUM(oi.calculated_subtotal) / SUM(oi.quantity), 2) AS avg_price_per_unit
FROM silver_layer.fact_order_items oi
JOIN silver_layer.fact_orders o ON oi.order_id = o.order_id
JOIN silver_layer.dim_books b ON oi.book_id = b.book_id
WHERE o.is_valid_order = TRUE
    AND o.order_status != 'Cancelado'
GROUP BY b.category
ORDER BY total_revenue DESC;

-- ============================================
-- 2. VISÃO: TOP LIVROS MAIS VENDIDOS
-- ============================================

CREATE OR REPLACE VIEW vw_top_selling_books AS
SELECT 
    b.book_id,
    b.title,
    b.author,
    b.category,
    b.price,
    b.avg_rating,
    COUNT(DISTINCT o.order_id) AS times_ordered,
    SUM(oi.quantity) AS total_copies_sold,
    ROUND(SUM(oi.calculated_subtotal), 2) AS total_revenue,
    ROUND(AVG(fr.rating), 1) AS customer_avg_rating,
    COUNT(DISTINCT fr.review_id) AS total_reviews
FROM silver_layer.dim_books b
LEFT JOIN silver_layer.fact_order_items oi ON b.book_id = oi.book_id
LEFT JOIN silver_layer.fact_orders o ON oi.order_id = o.order_id
LEFT JOIN silver_layer.fact_reviews fr ON b.book_id = fr.book_id
WHERE o.is_valid_order = TRUE 
    AND o.order_status != 'Cancelado'
GROUP BY b.book_id, b.title, b.author, b.category, b.price, b.avg_rating
ORDER BY total_copies_sold DESC, total_revenue DESC;

-- ============================================
-- 3. VISÃO: ANÁLISE DE CLIENTES
-- ============================================

CREATE OR REPLACE VIEW vw_customer_analytics AS
SELECT 
    c.customer_id,
    c.full_name,
    c.city,
    c.state,
    c.age,
    c.registration_date,
    COUNT(DISTINCT o.order_id) AS total_orders,
    ROUND(SUM(o.total_amount), 2) AS total_spent,
    ROUND(AVG(o.total_amount), 2) AS avg_order_value,
    ROUND(SUM(o.total_amount) / COUNT(DISTINCT o.order_id), 2) AS avg_per_order,
    COUNT(DISTINCT oi.book_id) AS unique_books_purchased,
    SUM(oi.quantity) AS total_books_quantity,
    COUNT(DISTINCT fr.review_id) AS total_reviews_written,
    ROUND(AVG(fr.rating), 1) AS avg_rating_given,
    MAX(o.order_date) AS last_order_date,
    DATEDIFF(CURDATE(), MAX(o.order_date)) AS days_since_last_order,
    -- Segmentação RFM simplificada
    CASE 
        WHEN DATEDIFF(CURDATE(), MAX(o.order_date)) <= 60 THEN 'Ativo'
        WHEN DATEDIFF(CURDATE(), MAX(o.order_date)) <= 180 THEN 'Em Risco'
        ELSE 'Inativo'
    END AS customer_status,
    CASE 
        WHEN SUM(o.total_amount) >= 300 THEN 'VIP'
        WHEN SUM(o.total_amount) >= 150 THEN 'Regular'
        ELSE 'Novo'
    END AS customer_tier
FROM silver_layer.dim_customers c
LEFT JOIN silver_layer.fact_orders o ON c.customer_id = o.customer_id
LEFT JOIN silver_layer.fact_order_items oi ON o.order_id = oi.order_id
LEFT JOIN silver_layer.fact_reviews fr ON c.customer_id = fr.customer_id
WHERE o.is_valid_order = TRUE
GROUP BY c.customer_id, c.full_name, c.city, c.state, c.age, c.registration_date
ORDER BY total_spent DESC;

-- ============================================
-- 4. VISÃO: ANÁLISE TEMPORAL DE VENDAS
-- ============================================

CREATE OR REPLACE VIEW vw_sales_over_time AS
SELECT 
    DATE_FORMAT(o.order_date, '%Y-%m') AS yearmonth,
    YEAR(o.order_date) AS year,
    MONTH(o.order_date) AS month,
    MONTHNAME(o.order_date) AS month_name,
    COUNT(DISTINCT o.order_id) AS total_orders,
    COUNT(DISTINCT o.customer_id) AS unique_customers,
    SUM(oi.quantity) AS total_items_sold,
    ROUND(SUM(o.total_amount), 2) AS gross_revenue,
    ROUND(SUM(o.shipping_cost), 2) AS total_shipping,
    ROUND(SUM(o.discount_applied), 2) AS total_discounts,
    ROUND(SUM(o.net_amount), 2) AS net_revenue,
    ROUND(AVG(o.total_amount), 2) AS avg_order_value,
    ROUND(SUM(o.total_amount) / COUNT(DISTINCT o.customer_id), 2) AS revenue_per_customer
FROM silver_layer.fact_orders o
JOIN silver_layer.fact_order_items oi ON o.order_id = oi.order_id
WHERE o.is_valid_order = TRUE
    AND o.order_status != 'Cancelado'
GROUP BY DATE_FORMAT(o.order_date, '%Y-%m'), YEAR(o.order_date), 
         MONTH(o.order_date), MONTHNAME(o.order_date)
ORDER BY yearmonth;

-- ============================================
-- 5. VISÃO: ANÁLISE DE MÉTODOS DE PAGAMENTO
-- ============================================

CREATE OR REPLACE VIEW vw_payment_analysis AS
SELECT 
    o.payment_method,
    COUNT(DISTINCT o.order_id) AS total_orders,
    ROUND(SUM(o.total_amount), 2) AS total_revenue,
    ROUND(AVG(o.total_amount), 2) AS avg_order_value,
    ROUND(SUM(o.discount_applied), 2) AS total_discounts,
    ROUND(
        (COUNT(DISTINCT o.order_id) * 100.0) / 
        (SELECT COUNT(*) FROM silver_layer.fact_orders WHERE is_valid_order = TRUE),
        2
    ) AS percentage_of_orders,
    ROUND(
        (SUM(o.total_amount) * 100.0) / 
        (SELECT SUM(total_amount) FROM silver_layer.fact_orders WHERE is_valid_order = TRUE),
        2
    ) AS percentage_of_revenue
FROM silver_layer.fact_orders o
WHERE o.is_valid_order = TRUE
    AND o.order_status != 'Cancelado'
GROUP BY o.payment_method
ORDER BY total_revenue DESC;

-- ============================================
-- 6. VISÃO: ANÁLISE GEOGRÁFICA
-- ============================================

CREATE OR REPLACE VIEW vw_geographic_analysis AS
SELECT 
    c.state,
    c.city,
    COUNT(DISTINCT c.customer_id) AS total_customers,
    COUNT(DISTINCT o.order_id) AS total_orders,
    SUM(oi.quantity) AS total_books_sold,
    ROUND(SUM(o.total_amount), 2) AS total_revenue,
    ROUND(AVG(o.total_amount), 2) AS avg_order_value,
    ROUND(SUM(o.total_amount) / COUNT(DISTINCT c.customer_id), 2) AS revenue_per_customer,
    ROUND(COUNT(DISTINCT o.order_id) * 1.0 / COUNT(DISTINCT c.customer_id), 2) AS orders_per_customer
FROM silver_layer.dim_customers c
LEFT JOIN silver_layer.fact_orders o ON c.customer_id = o.customer_id
LEFT JOIN silver_layer.fact_order_items oi ON o.order_id = oi.order_id
WHERE o.is_valid_order = TRUE
GROUP BY c.state, c.city
ORDER BY total_revenue DESC;

-- ============================================
-- 7. VISÃO: ANÁLISE DE AVALIAÇÕES
-- ============================================

CREATE OR REPLACE VIEW vw_review_analytics AS
SELECT 
    b.book_id,
    b.title,
    b.author,
    b.category,
    COUNT(fr.review_id) AS total_reviews,
    ROUND(AVG(fr.rating), 2) AS avg_rating,
    SUM(CASE WHEN fr.rating = 5 THEN 1 ELSE 0 END) AS five_star_reviews,
    SUM(CASE WHEN fr.rating = 4 THEN 1 ELSE 0 END) AS four_star_reviews,
    SUM(CASE WHEN fr.rating = 3 THEN 1 ELSE 0 END) AS three_star_reviews,
    SUM(CASE WHEN fr.rating <= 2 THEN 1 ELSE 0 END) AS low_star_reviews,
    ROUND(
        (SUM(CASE WHEN fr.rating >= 4 THEN 1 ELSE 0 END) * 100.0) / 
        COUNT(fr.review_id), 
        2
    ) AS positive_review_percentage,
    ROUND(AVG(fr.review_length), 0) AS avg_review_length,
    SUM(fr.helpful_count) AS total_helpful_votes
FROM silver_layer.dim_books b
LEFT JOIN silver_layer.fact_reviews fr ON b.book_id = fr.book_id
WHERE fr.is_valid_review = TRUE
GROUP BY b.book_id, b.title, b.author, b.category
HAVING COUNT(fr.review_id) > 0
ORDER BY avg_rating DESC, total_reviews DESC;

-- ============================================
-- 8. TABELA AGREGADA: MÉTRICAS DIÁRIAS
-- ============================================

CREATE TABLE agg_daily_metrics2 (
    metric_date DATE PRIMARY KEY,
    total_orders INT,
    total_revenue DECIMAL(12,2),
    total_items_sold INT,
    unique_customers INT,
    avg_order_value DECIMAL(10,2),
    total_shipping DECIMAL(10,2),
    total_discounts DECIMAL(10,2),
    net_revenue DECIMAL(12,2),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

INSERT INTO agg_daily_metrics2
SELECT 
    o.order_date AS metric_date,
    COUNT(DISTINCT o.order_id) AS total_orders,
    ROUND(SUM(o.total_amount), 2) AS total_revenue,
    SUM(oi.quantity) AS total_items_sold,
    COUNT(DISTINCT o.customer_id) AS unique_customers,
    ROUND(AVG(o.total_amount), 2) AS avg_order_value,
    ROUND(SUM(o.shipping_cost), 2) AS total_shipping,
    ROUND(SUM(o.discount_applied), 2) AS total_discounts,
    ROUND(SUM(o.net_amount), 2) AS net_revenue,
    NOW(),
    NOW()
FROM silver_layer.fact_orders o
JOIN silver_layer.fact_order_items oi ON o.order_id = oi.order_id
WHERE o.is_valid_order = TRUE
    AND o.order_status != 'Cancelado'
GROUP BY o.order_date
ORDER BY o.order_date;

-- ============================================
-- 9. TABELA AGREGADA: RESUMO POR AUTOR
-- ============================================

CREATE TABLE agg_author_performance2 (
    author_id INT AUTO_INCREMENT PRIMARY KEY,
    author_name VARCHAR(300) UNIQUE NOT NULL,
    total_books INT,
    total_copies_sold INT,
    total_revenue DECIMAL(12,2),
    avg_book_rating DECIMAL(3,2),
    total_reviews INT,
    most_popular_book VARCHAR(500),
    most_popular_category VARCHAR(100),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

INSERT INTO agg_author_performance2 (
    author_name,
    total_books,
    total_copies_sold,
    total_revenue,
    avg_book_rating,
    total_reviews,
    most_popular_book,
    most_popular_category
)
SELECT 
    b.author AS author_name,
    COUNT(DISTINCT b.book_id) AS total_books,
    COALESCE(SUM(oi.quantity), 0) AS total_copies_sold,
    ROUND(COALESCE(SUM(oi.calculated_subtotal), 0), 2) AS total_revenue,
    ROUND(AVG(b.avg_rating), 2) AS avg_book_rating,
    COUNT(DISTINCT fr.review_id) AS total_reviews,
    (
        SELECT b2.title 
        FROM silver_layer.dim_books b2
        LEFT JOIN silver_layer.fact_order_items oi2 ON b2.book_id = oi2.book_id
        WHERE b2.author = b.author
        GROUP BY b2.book_id, b2.title
        ORDER BY SUM(oi2.quantity) DESC
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
LEFT JOIN silver_layer.fact_order_items oi ON b.book_id = oi.book_id
LEFT JOIN silver_layer.fact_orders o ON oi.order_id = o.order_id
LEFT JOIN silver_layer.fact_reviews fr ON b.book_id = fr.book_id
WHERE (o.is_valid_order = TRUE OR o.order_id IS NULL)
GROUP BY b.author
ORDER BY total_revenue DESC;

-- ============================================
-- VERIFICAÇÃO DA CAMADA GOLD
-- ============================================

SELECT '=== VERIFICAÇÃO DAS VISÕES E TABELAS ANALÍTICAS ===' AS info;

SELECT 'Categorias analisadas:' AS metrica, COUNT(*) AS total FROM vw_sales_by_category;
SELECT 'Top livros:' AS metrica, COUNT(*) AS total FROM vw_top_selling_books;
SELECT 'Clientes analisados:' AS metrica, COUNT(*) AS total FROM vw_customer_analytics;
SELECT 'Períodos de vendas:' AS metrica, COUNT(*) AS total FROM vw_sales_over_time;
SELECT 'Métodos de pagamento:' AS metrica, COUNT(*) AS total FROM vw_payment_analysis;
SELECT 'Localidades:' AS metrica, COUNT(*) AS total FROM vw_geographic_analysis;
SELECT 'Livros com reviews:' AS metrica, COUNT(*) AS total FROM vw_review_analytics;
SELECT 'Métricas diárias:' AS metrica, COUNT(*) AS total FROM agg_daily_metrics;
SELECT 'Autores analisados:' AS metrica, COUNT(*) AS total FROM agg_author_performance;