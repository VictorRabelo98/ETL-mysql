# Stack Tecnológica

## Visão Geral

| Camada | Tecnologia | Versão Mínima | Papel |
|--------|-----------|---------------|-------|
| Banco de Dados | MySQL | 5.7+ | Engine principal de armazenamento e transformação |
| Linguagem | SQL (dialect MySQL) | — | Toda a lógica de ETL |
| Arquitetura | Medallion Architecture | — | Padrão de design de camadas |
| Paradigma | ELT (Extract, Load, Transform) | — | Dado carregado bruto, transformado in-database |

---

## MySQL: Por Que Esta Escolha?

### Contexto

MySQL é o **banco de dados relacional mais usado no mercado brasileiro** de médias empresas, especialmente em e-commerce, SaaS e sistemas de gestão. Usar MySQL como engine ETL elimina a necessidade de ferramentas externas e reduz a curva de adoção pela equipe.

### Recursos Utilizados

#### Schemas Múltiplos (Banco de Dados Separados)
```sql
CREATE SCHEMA bronze_layer;
CREATE SCHEMA silver_layer;
CREATE SCHEMA gold_layer;
```
Permite separação de acesso (permissões por schema), organização lógica e queries cross-schema via `schema.tabela`.

#### REGEXP para Validação de Padrão
```sql
-- Validação de email
email REGEXP '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$'

-- Detecção de formato de data
date_field REGEXP '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
date_field REGEXP '^[0-9]{2}/[0-9]{2}/[0-9]{4}$'
```
MySQL suporta POSIX Extended Regular Expressions (ERE), suficiente para validação de padrões simples a médios.

#### STR_TO_DATE para Conversão Multi-Formato
```sql
STR_TO_DATE(campo, '%Y-%m-%d')   -- ISO 8601
STR_TO_DATE(campo, '%d/%m/%Y')   -- Formato brasileiro
STR_TO_DATE(campo, '%d-%m-%Y')   -- Formato brasileiro com hífen
```
Converte strings para o tipo `DATE` com formatação explícita, sem ambiguidade.

#### REGEXP_REPLACE para Normalização de Texto
```sql
TRIM(REGEXP_REPLACE(full_name, '\\s+', ' '))
```
Disponível a partir do MySQL 8.0. Remove espaços duplicados internos enquanto `TRIM()` remove espaços nas extremidades.

#### Funções de Data e Tempo
```sql
YEAR(CURDATE())          -- Ano atual para validação de pub_year
TIMESTAMPDIFF(YEAR, birth_date, CURDATE())   -- Cálculo de idade
DATEDIFF(CURDATE(), order_date)              -- Dias desde último pedido
DATE_FORMAT(order_date, '%Y-%m')             -- Período para agregação temporal
MONTHNAME(order_date)                        -- Nome do mês em inglês
```

#### Views (CREATE OR REPLACE VIEW)
```sql
CREATE OR REPLACE VIEW gold_layer.vw_sales_by_category AS ...
```
Views na Gold layer funcionam como **abstrações de acesso** — analistas consultam a view sem precisar saber a query subjacente. `CREATE OR REPLACE` permite atualização sem DROP explícito.

#### Foreign Keys para Integridade Referencial
```sql
FOREIGN KEY (customer_id) REFERENCES dim_customers(customer_id)
FOREIGN KEY (order_id)    REFERENCES fact_orders(order_id)
FOREIGN KEY (book_id)     REFERENCES dim_books(book_id)
```
Garantem que não existam itens de pedido sem pedido pai, ou reviews sem livro existente.

#### Subqueries Correlacionadas
```sql
-- Para identificar o livro mais popular por autor
(
    SELECT b2.title
    FROM silver_layer.dim_books b2
    LEFT JOIN silver_layer.fact_order_items oi2 ON b2.book_id = oi2.book_id
    WHERE b2.author = b.author
    GROUP BY b2.book_id, b2.title
    ORDER BY SUM(COALESCE(oi2.quantity, 0)) DESC
    LIMIT 1
)
```

#### EXISTS para Validação de FK antes do INSERT
```sql
WHERE EXISTS (
    SELECT 1 FROM silver_layer.dim_customers c
    WHERE c.customer_id = o.customer_id
)
```
Padrão mais eficiente que `IN` para verificações de existência, especialmente com subsets grandes.

#### AUTO_INCREMENT + UNIQUE para Surrogate Keys
```sql
customer_key INT AUTO_INCREMENT PRIMARY KEY,
customer_id  VARCHAR(50) UNIQUE NOT NULL
```
Separa a chave de negócio (`customer_id`) da chave técnica do data warehouse (`customer_key`), seguindo o padrão dimensional de Kimball.

---

## Arquitetura Medallion: O Padrão de Design

### Origem

Popularizada pelo Databricks e pela plataforma Delta Lake, a Arquitetura Medallion (ou Multi-Hop Architecture) foi originalmente concebida para ambientes de Big Data. Neste projeto, demonstra que **os princípios são independentes da tecnologia** — funcionam igualmente em MySQL.

### Princípios

| Princípio | Implementação |
|-----------|---------------|
| **Imutabilidade do Bronze** | Bronze nunca é modificado após ingestão |
| **Progressão de qualidade** | Bronze → Silver → Gold: cada camada é mais confiável |
| **Rastreabilidade** | Qualquer registro Gold tem origem rastreável até o Bronze |
| **Separação de responsabilidades** | Cada camada tem uma única responsabilidade |
| **Idempotência** | Scripts começam com `DROP IF EXISTS` — executar múltiplas vezes gera o mesmo resultado |

### Comparação com Alternativas

| Padrão | Quando Usar | Desvantagem |
|--------|-------------|-------------|
| **Medallion (este projeto)** | Dados de múltiplas fontes, qualidade variável | Mais complexo de manter |
| **Star Schema simples** | Dados já limpos de uma fonte única | Sem rastreabilidade do dado bruto |
| **OBT (One Big Table)** | Analytics rápida em dados pequenos | Não escala, sem governança |
| **Data Vault** | Auditoria completa, historização | Muito complexo para equipes pequenas |

---

## O que Este Projeto NÃO Usa (e Por Quê)

| Ferramenta | Por que não foi usada | Quando usar |
|-----------|----------------------|-------------|
| **dbt** | Não necessário para demonstrar o padrão | Quando equipe já usa dbt em produção |
| **Apache Spark** | Dataset pequeno, MySQL suficiente | Quando dados ultrapassam capacidade do banco |
| **Apache Airflow** | Orquestração não é escopo do projeto | Quando pipeline roda em schedule automático |
| **Python/Pandas** | Transformações são feitas in-database | Quando transformações são complexas demais para SQL |
| **Docker** | Simplificação do setup | Quando ambiente precisa ser reproduzível |

---

## Requisitos de Ambiente

```
MySQL 8.0+          (REGEXP_REPLACE requer 8.0; resto funciona em 5.7)
                    Alternativa para 5.7: substituir REGEXP_REPLACE por
                    múltiplos REPLACE() encadeados

Charset             utf8mb4 (suporte a caracteres especiais: ã, é, ç, etc.)
Collation           utf8mb4_unicode_ci (comparações case-insensitive)

Memória recomendada 512MB RAM para o dataset de demonstração
                    Escala linearmente com o volume de dados

Storage             ~1MB para o dataset atual
                    ~100MB para 1M de registros estimados
```

### Configuração de Charset (Recomendada)

```sql
-- Verificar charset atual
SHOW VARIABLES LIKE 'character_set%';

-- Definir charset da sessão se necessário
SET NAMES utf8mb4;
SET CHARACTER SET utf8mb4;
```

---

## Portabilidade da Lógica

As transformações implementadas em MySQL são portáveis para:

| Engine | Adaptações Necessárias |
|--------|----------------------|
| **PostgreSQL** | `REGEXP` → `~`, `REGEXP_REPLACE` mantém mesma sintaxe, `CHAR_LENGTH` → `LENGTH` |
| **BigQuery** | `REGEXP_REPLACE` mantém, `STR_TO_DATE` → `PARSE_DATE`, schemas → datasets |
| **Snowflake** | `REGEXP` → `REGEXP_LIKE`, `STR_TO_DATE` → `TRY_TO_DATE`, schemas nativos |
| **dbt** | Transformar cada INSERT em um modelo `.sql` com `{{ ref() }}` |
| **Spark SQL** | Sintaxe 90% compatível, substituir `REGEXP_REPLACE` por `regexp_replace` (lowercase) |
