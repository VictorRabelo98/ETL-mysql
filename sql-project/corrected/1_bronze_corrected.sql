-- ============================================================
-- BRONZE LAYER — DADOS BRUTOS
-- Versão corrigida: sem alteração nos dados (intencionalmente
-- sujos), com melhorias estruturais e comentários de auditoria.
-- ============================================================

-- Criação dos schemas para as diferentes camadas
DROP SCHEMA IF EXISTS bronze_layer;
DROP SCHEMA IF EXISTS silver_layer;
DROP SCHEMA IF EXISTS gold_layer;

CREATE SCHEMA bronze_layer CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE SCHEMA silver_layer CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE SCHEMA gold_layer    CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- [MELHORIA] Charset explícito em cada schema garante suporte
-- a caracteres especiais (ã, é, ç) sem depender de configuração
-- do servidor MySQL.

USE bronze_layer;

-- ============================================================
-- CAMADA BRONZE: TABELAS DE DADOS BRUTOS
-- Todos os campos são VARCHAR para aceitar qualquer formato.
-- Nenhum dado é rejeitado nesta camada.
-- ============================================================

CREATE TABLE raw_customers (
    customer_id       VARCHAR(50),
    full_name         VARCHAR(200),
    email             VARCHAR(200),
    phone             VARCHAR(50),
    registration_date VARCHAR(50),
    city              VARCHAR(100),
    state             VARCHAR(50),
    country           VARCHAR(50),
    birth_date        VARCHAR(50),
    created_at        TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    -- [MELHORIA] Índice na coluna de ingestão para rastrear
    -- ordem de chegada durante deduplicação na Silver.
    INDEX idx_customer_id (customer_id),
    INDEX idx_created_at  (created_at)
);

CREATE TABLE raw_books (
    book_id          VARCHAR(50),
    title            VARCHAR(500),
    author           VARCHAR(300),
    publisher        VARCHAR(200),
    publication_year VARCHAR(20),
    isbn             VARCHAR(50),
    category         VARCHAR(100),
    price            VARCHAR(50),
    stock_quantity   VARCHAR(50),
    pages            VARCHAR(20),
    language_code    VARCHAR(20),
    rating           VARCHAR(20),
    created_at       TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_book_id (book_id)
);

CREATE TABLE raw_orders (
    order_id         VARCHAR(50),
    customer_id      VARCHAR(50),
    order_date       VARCHAR(50),
    total_amount     VARCHAR(50),
    payment_method   VARCHAR(100),
    order_status     VARCHAR(50),
    shipping_cost    VARCHAR(50),
    discount_applied VARCHAR(50),
    created_at       TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_order_id    (order_id),
    INDEX idx_customer_id (customer_id)
);

CREATE TABLE raw_order_items (
    order_item_id VARCHAR(50),
    order_id      VARCHAR(50),
    book_id       VARCHAR(50),
    quantity      VARCHAR(20),
    unit_price    VARCHAR(50),
    subtotal      VARCHAR(50),
    created_at    TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_order_item_id (order_item_id),
    INDEX idx_order_id      (order_id),
    INDEX idx_book_id       (book_id)
);

CREATE TABLE raw_reviews (
    review_id    VARCHAR(50),
    book_id      VARCHAR(50),
    customer_id  VARCHAR(50),
    rating       VARCHAR(20),
    review_text  TEXT,
    review_date  VARCHAR(50),
    helpful_count VARCHAR(20),
    created_at   TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_review_id   (review_id),
    INDEX idx_book_id     (book_id),
    INDEX idx_customer_id (customer_id)
);

-- ============================================================
-- INSERÇÃO DE DADOS BRUTOS (SIMULAÇÃO DE FONTES REAIS)
-- Os dados abaixo são intencionalmente sujos para demonstrar
-- os problemas que o pipeline ETL resolve.
-- ============================================================

-- Clientes: duplicata (C001), email inválido (C002, C005, C008),
--           espaços extras (C004), case inconsistente (C004, C006)
INSERT INTO raw_customers VALUES
('C001', 'Maria Silva Santos',   'maria.silva@email.com',  '(11) 98765-4321', '2023-01-15', 'São Paulo',       'SP', 'Brasil', '1985-03-20', NOW()),
('C002', 'João Pedro Oliveira',  'joao@invalid',           '11987654321',     '2023/02/20', 'Rio de Janeiro',  'RJ', 'Brasil', '15/04/1990', NOW()),
('C003', 'Ana Carolina Costa',   'ana.costa@email.com',    NULL,              '2023-03-10', 'Belo Horizonte',  'MG', 'Brasil', '1992-07-08', NOW()),
('C004', '  Carlos Eduardo  ',   'carlos.edu@email.com',   '(21)99999-8888',  '2023-04-05', 'Rio de Janeiro',  'rj', 'brasil', '1988-11-30', NOW()),
('C001', 'Maria Silva Santos',   'maria.silva@email.com',  '(11) 98765-4321', '2023-01-15', 'São Paulo',       'SP', 'Brasil', '1985-03-20', NOW()), -- duplicata intencional
('C005', 'Juliana Mendes',       '',                       '85988887777',     '2023-05-12', 'Fortaleza',       'CE', 'Brasil', '1995-02-14', NOW()),
('C006', 'Roberto Almeida',      'roberto.alm@email.com',  '(31)3456-7890',   '2023-06-18', 'belo horizonte',  'MG', 'BR',     '1980-09-25', NOW()),
('C007', 'Fernanda Lima',        'fernanda.lima@email.com', NULL,             '2023-07-22', 'Curitiba',        'PR', 'Brasil', '1993-12-05', NOW()),
('C008', 'Paulo Henrique',       'paulo@email',            '48999998888',     '01/08/2023', 'Florianópolis',   'SC', 'Brasil', '1987-06-18', NOW()),
('C009', 'Camila Rodrigues',     'camila.rod@email.com',   '(71)98888-7777',  '2023-09-10', 'Salvador',        'BA', 'Brasil', '1991-04-22', NOW()),
('C010', 'Lucas Ferreira',       'lucas.ferreira@email.com','(61)99999-6666', '2023-10-05', 'Brasília',        'DF', 'Brasil', '1989-08-30', NOW());

-- Livros: preço negativo (B005), ano inválido (B011),
--         categorias inconsistentes (B002, B005, B009)
INSERT INTO raw_books VALUES
('B001', 'O Senhor dos Anéis: A Sociedade do Anel', 'J.R.R. Tolkien',   'HarperCollins',        '1954', '978-0547928210', 'Fantasia',           '89.90',  '150', '576',  'PT',    '4.8', NOW()),
('B002', 'Harry Potter e a Pedra Filosofal',         'J.K. Rowling',     'Rocco',                '1997', '978-8532530787', 'fantasia',           '45.50',  '200', '264',  'pt-br', '4.9', NOW()),
('B003', '1984',                                     'George Orwell',    'Companhia das Letras', '1949', '978-8535914849', 'Ficção Científica',  '35.00',  '80',  '416',  'PT',    '4.7', NOW()),
('B004', 'Dom Casmurro',                             'Machado de Assis', 'Penguin',              '1899', '978-8563560179', 'Literatura Brasileira','28.90','120',  '256',  'PT-BR', '4.3', NOW()),
('B005', 'A Menina que Roubava Livros',              'Markus Zusak',     'Intrínseca',           '2005', '978-8580573466', 'FICÇÃO',             '-15.50', '0',   '480',  'pt',    '4.6', NOW()), -- preço negativo
('B006', 'O Hobbit',                                 'J.R.R. Tolkien',   'HarperCollins',        '1937', '978-0547928227', 'Fantasia',           '52.00',  '175', '310',  'PT',    '4.8', NOW()),
('B007', 'Percy Jackson e o Ladrão de Raios',        'Rick Riordan',     'Intrínseca',           '2005', '978-8598078355', 'Fantasia',           '39.90',  '95',  '400',  'PT-BR', '4.5', NOW()),
('B008', 'A Culpa é das Estrelas',                   'John Green',       'Intrínseca',           '2012', '978-8580572261', 'Romance',            '34.90',  '210', '288',  'pt-br', '4.4', NOW()),
('B009', 'O Código Da Vinci',                        'Dan Brown',        'Arqueiro',             '2003', '978-8599296134', 'suspense',           '42.00',  '60',  '432',  'PT',    '4.2', NOW()),
('B010', 'Orgulho e Preconceito',                    'Jane Austen',      'Martin Claret',        '1813', '978-8572327640', 'Romance Clássico',   '29.90',  '140', '424',  'PT',    '4.6', NOW()),
('B011', 'A Revolucao dos Bichos',                   'George Orwell',    'Companhia das Letras', '3000', '978-8535909555', 'Ficção',             '32.00',  '90',  '152',  'PT',    '4.5', NOW()), -- ano inválido
('B012', 'It - A Coisa',                             'Stephen King',     'Suma',                 '1986', '978-8556510594', 'Terror',             '79.90',  '45',  '1104', 'PT',    '4.7', NOW());

-- Pedidos: data futura (ORD007), total vazio (ORD005),
--          status/payment inconsistentes
INSERT INTO raw_orders VALUES
('ORD001', 'C001', '2024-01-20', '135.40', 'Cartão de Crédito', 'Entregue',    '15.00', '10.00', NOW()),
('ORD002', 'C002', '2024-02-15', '89.90',  'PIX',               'entregue',    '12.00', '0',     NOW()),
('ORD003', 'C003', '2024-02-28', '174.80', 'Boleto',            'Em Trânsito', '18.00', '15.00', NOW()),
('ORD004', 'C004', '2024-03-10', '63.90',  'Cartão de Débito',  'PROCESSANDO', '10.00', '5.00',  NOW()),
('ORD005', 'C005', '2024-03-22', '',        'Cartão de Crédito', 'Cancelado',   NULL,    '0',     NOW()), -- total vazio
('ORD006', 'C006', '2024-04-05', '156.80', 'pix',               'Entregue',    '15.00', '20.00', NOW()),
('ORD007', 'C007', '2025-12-30', '91.90',  'Cartão de Crédito', 'Entregue',    '12.00', '0',     NOW()), -- data futura
('ORD008', 'C008', '2024-05-18', '114.80', 'PIX',               'Em Trânsito', '15.00', '10.00', NOW()),
('ORD009', 'C009', '2024-06-02', '79.90',  'Boleto',            'Entregue',    '12.00', '0',     NOW()),
('ORD010', 'C010', '2024-06-15', '247.70', 'Cartão de Crédito', 'entregue',    '20.00', '25.00', NOW()),
('ORD011', 'C003', '2024-07-08', '84.00',  'PIX',               'Entregue',    '12.00', '8.00',  NOW()),
('ORD012', 'C001', '2024-07-22', '62.00',  'cartao',            'Processando', '10.00', '0',     NOW());

-- Itens de pedido (sem problemas críticos nesta simulação)
INSERT INTO raw_order_items VALUES
('OI001', 'ORD001', 'B001', '1', '89.90',  '89.90',  NOW()),
('OI002', 'ORD001', 'B002', '1', '45.50',  '45.50',  NOW()),
('OI003', 'ORD002', 'B001', '1', '89.90',  '89.90',  NOW()),
('OI004', 'ORD003', 'B002', '2', '45.50',  '91.00',  NOW()),
('OI005', 'ORD003', 'B003', '2', '35.00',  '70.00',  NOW()),
('OI006', 'ORD003', 'B004', '1', '28.90',  '28.90',  NOW()),
('OI007', 'ORD004', 'B003', '1', '35.00',  '35.00',  NOW()),
('OI008', 'ORD004', 'B004', '1', '28.90',  '28.90',  NOW()),
('OI009', 'ORD006', 'B006', '2', '52.00',  '104.00', NOW()),
('OI010', 'ORD006', 'B007', '1', '39.90',  '39.90',  NOW()),
('OI011', 'ORD006', 'B008', '1', '34.90',  '34.90',  NOW()),
('OI012', 'ORD007', 'B009', '2', '42.00',  '84.00',  NOW()),
('OI013', 'ORD007', 'B010', '1', '29.90',  '29.90',  NOW()),
('OI014', 'ORD008', 'B001', '1', '89.90',  '89.90',  NOW()),
('OI015', 'ORD008', 'B004', '1', '28.90',  '28.90',  NOW()),
('OI016', 'ORD009', 'B012', '1', '79.90',  '79.90',  NOW()),
('OI017', 'ORD010', 'B012', '2', '79.90',  '159.80', NOW()),
('OI018', 'ORD010', 'B001', '1', '89.90',  '89.90',  NOW()),
('OI019', 'ORD010', 'B003', '1', '35.00',  '35.00',  NOW()),
('OI020', 'ORD011', 'B006', '1', '52.00',  '52.00',  NOW()),
('OI021', 'ORD011', 'B007', '1', '39.90',  '39.90',  NOW()),
('OI022', 'ORD012', 'B010', '2', '29.90',  '59.80',  NOW());

-- Avaliações: rating inválido (R006: 12, R011: -2),
--             data inválida (R012), formato alternativo (R007)
INSERT INTO raw_reviews VALUES
('R001', 'B001', 'C001', '5',  'Obra-prima da fantasia! Simplesmente incrível.',       '2024-02-01',   '45', NOW()),
('R002', 'B001', 'C002', '5',  'Melhor livro que já li!',                              '2024-02-18',   '32', NOW()),
('R003', 'B002', 'C003', '5',  'Magia pura! Adorei cada página.',                      '2024-03-05',   '28', NOW()),
('R004', 'B002', 'C004', '4',  'Muito bom, mas achei o ritmo lento no início.',        '2024-03-15',   '15', NOW()),
('R005', 'B003', 'C003', '5',  'Distopia aterrorizante e atual. Recomendo!',           '2024-03-20',   '52', NOW()),
('R006', 'B003', 'C004', '12', 'Excelente reflexão sobre totalitarismo.',              '2024-04-01',   '38', NOW()), -- rating inválido
('R007', 'B004', 'C006', '4',  'Clássico da literatura brasileira. Vale a leitura.',  '01-05-2024',   '22', NOW()),
('R008', 'B006', 'C006', '5',  'Aventura fantástica! Prelúdio perfeito.',              '2024-05-10',   '41', NOW()),
('R009', 'B012', 'C009', '5',  'Stephen King é mestre do terror!',                    '2024-06-08',   '67', NOW()),
('R010', 'B001', 'C010', '5',  'Releitura anual garantida.',                           '2024-06-20',   '19', NOW()),
('R011', 'B009', 'C007', '-2', 'Não gostei do final.',                                '2024-08-15',   '3',  NOW()), -- rating negativo
('R012', 'B010', 'C010', '4',  'Romance clássico bem escrito.',                       'invalid-date', '12', NOW());

-- ============================================================
-- VERIFICAÇÃO DOS DADOS BRUTOS
-- ============================================================

SELECT 'Clientes carregados:'        AS entidade, COUNT(*) AS total FROM raw_customers;
SELECT 'Livros carregados:'          AS entidade, COUNT(*) AS total FROM raw_books;
SELECT 'Pedidos carregados:'         AS entidade, COUNT(*) AS total FROM raw_orders;
SELECT 'Itens de pedido carregados:' AS entidade, COUNT(*) AS total FROM raw_order_items;
SELECT 'Avaliações carregadas:'      AS entidade, COUNT(*) AS total FROM raw_reviews;
