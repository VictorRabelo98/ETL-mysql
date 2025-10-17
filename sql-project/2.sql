-- ============================================
-- TRANSFORMAÇÃO E LIMPEZA - CAMADA SILVER
-- ============================================

USE silver_layer;

-- Limpar tabelas existentes (ordem reversa por causa das FKs)
DROP TABLE IF EXISTS fact_reviews;
DROP TABLE IF EXISTS fact_order_items;
DROP TABLE IF EXISTS fact_orders;
DROP TABLE IF EXISTS dim_books;
DROP TABLE IF EXISTS dim_customers;

-- ============================================
-- LIMPAR E CRIAR TABELA DE CLIENTES
-- ============================================

USE silver_layer;

DROP TABLE IF EXISTS dim_customers;

CREATE TABLE dim_customers (
    customer_key INT AUTO_INCREMENT PRIMARY KEY,
    customer_id VARCHAR(50) UNIQUE NOT NULL,
    full_name VARCHAR(200) NOT NULL,
    email VARCHAR(200),
    email_valid BOOLEAN,
    phone VARCHAR(50),
    registration_date DATE,
    city VARCHAR(100),
    state CHAR(2),
    country VARCHAR(50),
    birth_date DATE,
    age INT,
    data_quality_score DECIMAL(3,2),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

-- ============================================
-- INSERIR DADOS LIMPOS
-- ============================================

INSERT INTO dim_customers (
    customer_id,
    full_name,
    email,
    email_valid,
    phone,
    registration_date,
    city,
    state,
    country,
    birth_date,
    age,
    data_quality_score
)
SELECT DISTINCT
    customer_id,
    TRIM(REGEXP_REPLACE(full_name, '\\s+', ' ')) AS full_name,
    CASE 
        WHEN email = '' THEN NULL
        ELSE LOWER(TRIM(email))
    END AS email,
    CASE 
        WHEN email REGEXP '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$' THEN TRUE
        ELSE FALSE
    END AS email_valid,
    TRIM(phone) AS phone,
    CASE 
        WHEN registration_date REGEXP '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' 
            THEN STR_TO_DATE(registration_date, '%Y-%m-%d')
        WHEN registration_date REGEXP '^[0-9]{4}/[0-9]{2}/[0-9]{2}$' 
            THEN STR_TO_DATE(registration_date, '%Y/%m/%d')
        WHEN registration_date REGEXP '^[0-9]{2}/[0-9]{2}/[0-9]{4}$' 
            THEN STR_TO_DATE(registration_date, '%d/%m/%Y')
        ELSE NULL
    END AS registration_date,
    CONCAT(
        UPPER(SUBSTRING(TRIM(city), 1, 1)),
        LOWER(SUBSTRING(TRIM(city), 2))
    ) AS city,
    UPPER(LEFT(TRIM(state), 2)) AS state,
    CASE 
        WHEN LOWER(TRIM(country)) IN ('brasil', 'brazil', 'br') THEN 'Brasil'
        ELSE TRIM(country)
    END AS country,
    CASE 
        WHEN birth_date REGEXP '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' 
            THEN STR_TO_DATE(birth_date, '%Y-%m-%d')
        WHEN birth_date REGEXP '^[0-9]{2}/[0-9]{2}/[0-9]{4}$' 
            THEN STR_TO_DATE(birth_date, '%d/%m/%Y')
        ELSE NULL
    END AS birth_date,
    CASE 
        WHEN birth_date REGEXP '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' 
            THEN TIMESTAMPDIFF(YEAR, STR_TO_DATE(birth_date, '%Y-%m-%d'), CURDATE())
        WHEN birth_date REGEXP '^[0-9]{2}/[0-9]{2}/[0-9]{4}$' 
            THEN TIMESTAMPDIFF(YEAR, STR_TO_DATE(birth_date, '%d/%m/%Y'), CURDATE())
        ELSE NULL
    END AS age,
    (
        (CASE WHEN customer_id IS NOT NULL AND customer_id != '' THEN 0.2 ELSE 0 END) +
        (CASE WHEN email REGEXP '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$' THEN 0.2 ELSE 0 END) +
        (CASE WHEN phone IS NOT NULL AND phone != '' THEN 0.2 ELSE 0 END) +
        (CASE WHEN registration_date IS NOT NULL THEN 0.2 ELSE 0 END) +
        (CASE WHEN birth_date IS NOT NULL THEN 0.2 ELSE 0 END)
    ) AS data_quality_score
FROM bronze_layer.raw_customers
WHERE customer_id IS NOT NULL;

-- ============================================
-- VERIFICAR RESULTADO
-- ============================================

SELECT 'Clientes processados:' AS metrica, 
       COUNT(*) AS total, 
       ROUND(AVG(data_quality_score), 2) AS qualidade_media
FROM dim_customers;

SELECT * FROM dim_customers LIMIT 5;

-- ============================================
-- LIMPAR E CRIAR TABELA DE LIVROS
-- ============================================

USE silver_layer;

DROP TABLE IF EXISTS dim_books;

CREATE TABLE dim_books (
    book_key INT AUTO_INCREMENT PRIMARY KEY,
    book_id VARCHAR(50) UNIQUE NOT NULL,
    title VARCHAR(500) NOT NULL,
    author VARCHAR(300) NOT NULL,
    publisher VARCHAR(200),
    publication_year INT,
    isbn VARCHAR(50),
    category VARCHAR(100),
    price DECIMAL(10,2),
    stock_quantity INT,
    pages INT,
    language_code CHAR(5),
    avg_rating DECIMAL(2,1),
    is_available BOOLEAN,
    data_quality_score DECIMAL(3,2),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

-- ============================================
-- INSERIR DADOS LIMPOS
-- ============================================

INSERT INTO dim_books (
    book_id,
    title,
    author,
    publisher,
    publication_year,
    isbn,
    category,
    price,
    stock_quantity,
    pages,
    language_code,
    avg_rating,
    is_available,
    data_quality_score
)
SELECT 
    book_id,
    TRIM(title) AS title,
    TRIM(author) AS author,
    TRIM(publisher) AS publisher,
    CASE 
        WHEN CAST(publication_year AS UNSIGNED) BETWEEN 1000 AND YEAR(CURDATE()) 
            THEN CAST(publication_year AS UNSIGNED)
        ELSE NULL
    END AS publication_year,
    TRIM(isbn) AS isbn,
    CASE 
        WHEN LOWER(TRIM(category)) = 'fantasia' THEN 'Fantasia'
        WHEN LOWER(TRIM(category)) = 'ficção científica' THEN 'Ficção Científica'
        WHEN LOWER(TRIM(category)) IN ('ficção', 'ficcao') THEN 'Ficção'
        WHEN LOWER(TRIM(category)) = 'suspense' THEN 'Suspense'
        WHEN LOWER(TRIM(category)) = 'terror' THEN 'Terror'
        WHEN LOWER(TRIM(category)) = 'romance' THEN 'Romance'
        WHEN LOWER(TRIM(category)) = 'romance clássico' THEN 'Romance Clássico'
        WHEN LOWER(TRIM(category)) = 'literatura brasileira' THEN 'Literatura Brasileira'
        ELSE TRIM(category)
    END AS category,
    CASE 
        WHEN CAST(price AS DECIMAL(10,2)) >= 0 THEN CAST(price AS DECIMAL(10,2))
        ELSE NULL
    END AS price,
    CASE 
        WHEN stock_quantity REGEXP '^[0-9]+$' 
            THEN CAST(stock_quantity AS UNSIGNED)
        ELSE 0
    END AS stock_quantity,
    CASE 
        WHEN pages REGEXP '^[0-9]+$' AND CAST(pages AS UNSIGNED) > 0
            THEN CAST(pages AS UNSIGNED)
        ELSE NULL
    END AS pages,
    CASE 
        WHEN LOWER(TRIM(language_code)) IN ('pt', 'pt-br', 'pt_br', 'português') THEN 'PT-BR'
        WHEN LOWER(TRIM(language_code)) IN ('en', 'english', 'inglês') THEN 'EN'
        ELSE UPPER(TRIM(language_code))
    END AS language_code,
    CASE 
        WHEN CAST(rating AS DECIMAL(2,1)) BETWEEN 0 AND 5 
            THEN CAST(rating AS DECIMAL(2,1))
        ELSE NULL
    END AS avg_rating,
    CASE 
        WHEN CAST(stock_quantity AS UNSIGNED) > 0 
            AND CAST(price AS DECIMAL(10,2)) > 0 
            THEN TRUE
        ELSE FALSE
    END AS is_available,
    (
        (CASE WHEN book_id IS NOT NULL THEN 0.15 ELSE 0 END) +
        (CASE WHEN title IS NOT NULL AND title != '' THEN 0.15 ELSE 0 END) +
        (CASE WHEN author IS NOT NULL AND author != '' THEN 0.15 ELSE 0 END) +
        (CASE WHEN CAST(publication_year AS UNSIGNED) BETWEEN 1000 AND YEAR(CURDATE()) THEN 0.15 ELSE 0 END) +
        (CASE WHEN isbn IS NOT NULL AND isbn != '' THEN 0.1 ELSE 0 END) +
        (CASE WHEN CAST(price AS DECIMAL(10,2)) > 0 THEN 0.15 ELSE 0 END) +
        (CASE WHEN CAST(rating AS DECIMAL(2,1)) BETWEEN 0 AND 5 THEN 0.15 ELSE 0 END)
    ) AS data_quality_score
FROM bronze_layer.raw_books
WHERE book_id IS NOT NULL;

-- ============================================
-- VERIFICAR RESULTADO
-- ============================================

SELECT 'Livros processados:' AS metrica,
       COUNT(*) AS total,
       ROUND(AVG(data_quality_score), 2) AS qualidade_media
FROM dim_books;

SELECT * FROM dim_books LIMIT 5;


-- ============================================
-- 3. TABELA DE PEDIDOS LIMPA
-- ============================================

CREATE TABLE fact_orders (
    order_key INT AUTO_INCREMENT PRIMARY KEY,
    order_id VARCHAR(50) UNIQUE NOT NULL,
    customer_id VARCHAR(50) NOT NULL,
    order_date DATE,
    total_amount DECIMAL(10,2),
    payment_method VARCHAR(100),
    order_status VARCHAR(50),
    shipping_cost DECIMAL(10,2),
    discount_applied DECIMAL(10,2),
    net_amount DECIMAL(10,2),
    is_valid_order BOOLEAN,
    data_quality_score DECIMAL(3,2),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (customer_id) REFERENCES dim_customers(customer_id)
);

INSERT INTO fact_orders (
    order_id,
    customer_id,
    order_date,
    total_amount,
    payment_method,
    order_status,
    shipping_cost,
    discount_applied,
    net_amount,
    is_valid_order,
    data_quality_score
)
SELECT 
    o.order_id,
    o.customer_id,
    CASE 
        WHEN o.order_date REGEXP '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' 
            AND STR_TO_DATE(o.order_date, '%Y-%m-%d') <= CURDATE()
            THEN STR_TO_DATE(o.order_date, '%Y-%m-%d')
        WHEN o.order_date REGEXP '^[0-9]{2}/[0-9]{2}/[0-9]{4}$' 
            AND STR_TO_DATE(o.order_date, '%d/%m/%Y') <= CURDATE()
            THEN STR_TO_DATE(o.order_date, '%d/%m/%Y')
        ELSE NULL
    END AS order_date,
    CASE 
        WHEN o.total_amount = '' OR o.total_amount IS NULL THEN NULL
        WHEN CAST(o.total_amount AS DECIMAL(10,2)) >= 0 
            THEN CAST(o.total_amount AS DECIMAL(10,2))
        ELSE NULL
    END AS total_amount,
    CASE 
        WHEN LOWER(TRIM(o.payment_method)) LIKE '%cart%credit%' 
            OR LOWER(TRIM(o.payment_method)) = 'cartão de crédito'
            THEN 'Cartão de Crédito'
        WHEN LOWER(TRIM(o.payment_method)) LIKE '%cart%deb%' 
            OR LOWER(TRIM(o.payment_method)) = 'cartão de débito'
            THEN 'Cartão de Débito'
        WHEN LOWER(TRIM(o.payment_method)) = 'pix' THEN 'PIX'
        WHEN LOWER(TRIM(o.payment_method)) = 'boleto' THEN 'Boleto'
        WHEN LOWER(TRIM(o.payment_method)) = 'cartao' THEN 'Cartão'
        ELSE TRIM(o.payment_method)
    END AS payment_method,
    CASE 
        WHEN LOWER(TRIM(o.order_status)) = 'entregue' THEN 'Entregue'
        WHEN LOWER(TRIM(o.order_status)) IN ('em trânsito', 'em transito') THEN 'Em Trânsito'
        WHEN LOWER(TRIM(o.order_status)) = 'processando' THEN 'Processando'
        WHEN LOWER(TRIM(o.order_status)) = 'cancelado' THEN 'Cancelado'
        ELSE TRIM(o.order_status)
    END AS order_status,
    CASE 
        WHEN o.shipping_cost IS NULL OR o.shipping_cost = '' THEN 0
        WHEN CAST(o.shipping_cost AS DECIMAL(10,2)) >= 0 
            THEN CAST(o.shipping_cost AS DECIMAL(10,2))
        ELSE 0
    END AS shipping_cost,
    CASE 
        WHEN o.discount_applied IS NULL OR o.discount_applied = '' THEN 0
        WHEN CAST(o.discount_applied AS DECIMAL(10,2)) >= 0 
            THEN CAST(o.discount_applied AS DECIMAL(10,2))
        ELSE 0
    END AS discount_applied,
    CASE 
        WHEN o.total_amount = '' OR o.total_amount IS NULL THEN NULL
        ELSE (
            CAST(COALESCE(NULLIF(o.total_amount, ''), '0') AS DECIMAL(10,2)) +
            CAST(COALESCE(NULLIF(o.shipping_cost, ''), '0') AS DECIMAL(10,2)) -
            CAST(COALESCE(NULLIF(o.discount_applied, ''), '0') AS DECIMAL(10,2))
        )
    END AS net_amount,
    CASE 
        WHEN o.total_amount IS NOT NULL 
            AND o.total_amount != ''
            AND CAST(o.total_amount AS DECIMAL(10,2)) > 0
            AND o.order_date IS NOT NULL
            AND STR_TO_DATE(o.order_date, '%Y-%m-%d') <= CURDATE()
            THEN TRUE
        ELSE FALSE
    END AS is_valid_order,
    (
        (CASE WHEN o.order_id IS NOT NULL THEN 0.2 ELSE 0 END) +
        (CASE WHEN o.customer_id IS NOT NULL THEN 0.2 ELSE 0 END) +
        (CASE WHEN o.order_date IS NOT NULL AND o.order_date != '' THEN 0.2 ELSE 0 END) +
        (CASE WHEN o.total_amount IS NOT NULL AND o.total_amount != '' 
            AND CAST(o.total_amount AS DECIMAL(10,2)) > 0 THEN 0.2 ELSE 0 END) +
        (CASE WHEN o.payment_method IS NOT NULL AND o.payment_method != '' THEN 0.2 ELSE 0 END)
    ) AS data_quality_score
FROM bronze_layer.raw_orders o
WHERE o.order_id IS NOT NULL
    AND EXISTS (
        SELECT 1 FROM silver_layer.dim_customers c 
        WHERE c.customer_id = o.customer_id
    );
-- ============================================
-- 4. TABELA DE ITENS DE PEDIDO LIMPA
-- ============================================

CREATE TABLE fact_order_items (
    order_item_key INT AUTO_INCREMENT PRIMARY KEY,
    order_item_id VARCHAR(50) UNIQUE NOT NULL,
    order_id VARCHAR(50) NOT NULL,
    book_id VARCHAR(50) NOT NULL,
    quantity INT,
    unit_price DECIMAL(10,2),
    subtotal DECIMAL(10,2),
    calculated_subtotal DECIMAL(10,2),
    subtotal_matches BOOLEAN,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (order_id) REFERENCES fact_orders(order_id),
    FOREIGN KEY (book_id) REFERENCES dim_books(book_id)
);

INSERT INTO fact_order_items (
    order_item_id,
    order_id,
    book_id,
    quantity,
    unit_price,
    subtotal,
    calculated_subtotal,
    subtotal_matches
)
SELECT 
    oi.order_item_id,
    oi.order_id,
    oi.book_id,
    CASE 
        WHEN oi.quantity REGEXP '^[0-9]+$' AND CAST(oi.quantity AS UNSIGNED) > 0
            THEN CAST(oi.quantity AS UNSIGNED)
        ELSE 1
    END AS quantity,
    CASE 
        WHEN CAST(oi.unit_price AS DECIMAL(10,2)) >= 0 
            THEN CAST(oi.unit_price AS DECIMAL(10,2))
        ELSE NULL
    END AS unit_price,
    CASE 
        WHEN CAST(oi.subtotal AS DECIMAL(10,2)) >= 0 
            THEN CAST(oi.subtotal AS DECIMAL(10,2))
        ELSE NULL
    END AS subtotal,
    CAST(oi.quantity AS UNSIGNED) * CAST(oi.unit_price AS DECIMAL(10,2)) AS calculated_subtotal,
    CASE 
        WHEN ABS(
            CAST(oi.subtotal AS DECIMAL(10,2)) - 
            (CAST(oi.quantity AS UNSIGNED) * CAST(oi.unit_price AS DECIMAL(10,2)))
        ) < 0.01 THEN TRUE
        ELSE FALSE
    END AS subtotal_matches
FROM bronze_layer.raw_order_items oi
WHERE oi.order_item_id IS NOT NULL
    AND EXISTS (SELECT 1 FROM silver_layer.fact_orders o WHERE o.order_id = oi.order_id)
    AND EXISTS (SELECT 1 FROM silver_layer.dim_books b WHERE b.book_id = oi.book_id);
-- ============================================
-- 5. TABELA DE AVALIAÇÕES LIMPA
-- ============================================

CREATE TABLE fact_reviews (
    review_key INT AUTO_INCREMENT PRIMARY KEY,
    review_id VARCHAR(50) UNIQUE NOT NULL,
    book_id VARCHAR(50) NOT NULL,
    customer_id VARCHAR(50) NOT NULL,
    rating INT,
    review_text TEXT,
    review_date DATE,
    helpful_count INT,
    review_length INT,
    is_valid_review BOOLEAN,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (book_id) REFERENCES dim_books(book_id),
    FOREIGN KEY (customer_id) REFERENCES dim_customers(customer_id)
);

INSERT INTO fact_reviews (
    review_id,
    book_id,
    customer_id,
    rating,
    review_text,
    review_date,
    helpful_count,
    review_length,
    is_valid_review
)
SELECT 
    r.review_id,
    r.book_id,
    r.customer_id,
    CASE 
        WHEN CAST(r.rating AS UNSIGNED) BETWEEN 1 AND 5 
            THEN CAST(r.rating AS UNSIGNED)
        ELSE NULL
    END AS rating,
    TRIM(r.review_text) AS review_text,
    CASE 
        WHEN r.review_date REGEXP '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' 
            AND STR_TO_DATE(r.review_date, '%Y-%m-%d') <= CURDATE()
            THEN STR_TO_DATE(r.review_date, '%Y-%m-%d')
        WHEN r.review_date REGEXP '^[0-9]{2}-[0-9]{2}-[0-9]{4}$' 
            AND STR_TO_DATE(r.review_date, '%d-%m-%Y') <= CURDATE()
            THEN STR_TO_DATE(r.review_date, '%d-%m-%Y')
        ELSE NULL
    END AS review_date,
    CASE 
        WHEN r.helpful_count REGEXP '^[0-9]+$' 
            THEN CAST(r.helpful_count AS UNSIGNED)
        ELSE 0
    END AS helpful_count,
    CHAR_LENGTH(TRIM(r.review_text)) AS review_length,
    CASE 
        WHEN CAST(r.rating AS UNSIGNED) BETWEEN 1 AND 5 
            AND r.review_text IS NOT NULL 
            AND TRIM(r.review_text) != ''
            AND r.review_date IS NOT NULL
            THEN TRUE
        ELSE FALSE
    END AS is_valid_review
FROM bronze_layer.raw_reviews r
WHERE r.review_id IS NOT NULL
    AND EXISTS (SELECT 1 FROM silver_layer.dim_books b WHERE b.book_id = r.book_id)
    AND EXISTS (SELECT 1 FROM silver_layer.dim_customers c WHERE c.customer_id = r.customer_id);
-- ============================================
-- VERIFICAÇÃO DA CAMADA SILVER
-- ============================================

SELECT '=== RELATÓRIO DE QUALIDADE DOS DADOS ===' AS info;

SELECT 'Clientes processados:' AS metrica, COUNT(*) AS total, 
       ROUND(AVG(data_quality_score), 2) AS qualidade_media
FROM dim_customers;

SELECT 'Livros processados:' AS metrica, COUNT(*) AS total,
       ROUND(AVG(data_quality_score), 2) AS qualidade_media
FROM dim_books;

SELECT 'Pedidos processados:' AS metrica, COUNT(*) AS total,
       ROUND(AVG(data_quality_score), 2) AS qualidade_media,
       SUM(CASE WHEN is_valid_order = TRUE THEN 1 ELSE 0 END) AS pedidos_validos
FROM fact_orders;

SELECT 'Itens de pedido processados:' AS metrica, COUNT(*) AS total,
       SUM(CASE WHEN subtotal_matches = TRUE THEN 1 ELSE 0 END) AS subtotais_corretos
FROM fact_order_items;

SELECT 'Avaliações processadas:' AS metrica, COUNT(*) AS total,
       SUM(CASE WHEN is_valid_review = TRUE THEN 1 ELSE 0 END) AS reviews_validos
FROM fact_reviews;