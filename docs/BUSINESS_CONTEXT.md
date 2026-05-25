# Contexto de Negócio: Pipeline ETL para Livraria Online

## O Problema de Negócio

### Cenário

Uma livraria online opera com dados provenientes de **múltiplas fontes heterogêneas**: cadastros manuais via formulário web, importações de sistemas legados, integrações com marketplaces e ERPs. Cada fonte tem seus próprios padrões de formatação, validação e encoding.

O impacto direto dessa fragmentação:

1. **Marketing ineficiente** — campanhas disparadas para clientes duplicados aumentam o custo por aquisição (CPA) e prejudicam a reputação de entregabilidade de email
2. **Receita inflada** — pedidos com datas futuras ou valores inválidos são contabilizados como receita real nos dashboards
3. **Estoque incorreto** — livros com preço negativo ou estoque inválido aparecem como disponíveis
4. **Análise de produto impossível** — categorias inconsistentes ("fantasia", "Fantasia", "FICÇÃO") fragmentam os relatórios de vendas por gênero
5. **Avaliações distorcidas** — ratings fora da escala (−2, 12) distorcem a média e prejudicam recomendações

### Perguntas de Negócio Sem Resposta

Antes do pipeline, o time de dados não conseguia responder confiávelmente:

- Quantos clientes únicos e ativos a empresa tem?
- Qual categoria de livro gera mais receita líquida?
- Qual é o ticket médio real por método de pagamento?
- Quais autores têm melhor performance em vendas + avaliações?
- Qual estado tem maior lifetime value por cliente?
- Quantos pedidos do mês passado foram realmente entregues?

---

## Contexto Técnico

### Fontes de Dados (Simuladas na Bronze Layer)

| Tabela | Registros | Origem Representada | Problemas Principais |
|--------|-----------|---------------------|----------------------|
| `raw_customers` | 11 (1 duplicata) | CRM + Formulário web | Duplicata, email inválido, formatos de data mistos, espaços extras, estados em minúsculo |
| `raw_books` | 12 | Sistema de catálogo | Preço negativo, ano de publicação 3000, categorias inconsistentes, códigos de idioma variados |
| `raw_orders` | 12 | Sistema de pedidos | Data futura, total_amount vazio, status inconsistente, frete NULL |
| `raw_order_items` | 22 | Sistema transacional | Subtotal inconsistente (2×45.50=91 ao invés de 91.00) |
| `raw_reviews` | 12 | Plataforma de reviews | Rating -2 e 12, data em formato inválido ("invalid-date"), formato DD-MM-YYYY |

### Decisões de Design

**Por que MySQL puro?**
A decisão de usar SQL sem frameworks externos (como Spark, dbt ou Airflow) demonstra que ETL de qualidade pode ser implementado com ferramentas disponíveis em qualquer ambiente corporativo. MySQL é o banco relacional mais comum no mercado brasileiro de médias empresas.

**Por que Arquitetura Medallion?**
A arquitetura em camadas resolve o dilema clássico de ETL: transformar dados sem perder rastreabilidade. A camada Bronze preserva a evidência. A Silver é o produto. A Gold é a entrega.

**Por que schemas separados?**
`bronze_layer`, `silver_layer` e `gold_layer` como schemas distintos permitem:
- Controle de acesso granular (analistas só acessam Gold)
- Identificação imediata da camada ao analisar queries
- Possibilidade de escalar cada camada independentemente

---

## Solução: Pipeline ETL em 3 Camadas

### Camada Bronze — Ingestão Fiel

**Responsabilidade:** Armazenar dados exatamente como chegaram, sem transformação.

**Princípio:** Todos os campos são `VARCHAR`. Nenhum dado é rejeitado. A Bronze é a única fonte de verdade sobre "o que o sistema fonte disse".

**Valor:** Rastreabilidade. Qualquer investigação de dado suspeito na Silver começa na Bronze.

```
Bronze Layer
├── Todos campos VARCHAR (sem tipagem forçada)
├── Aceita NULL, string vazia, formato inválido
├── Timestamp de ingestão em created_at
└── Sem constraints de integridade referencial
```

### Camada Silver — Limpeza e Qualidade

**Responsabilidade:** Transformar dados brutos em dados confiáveis.

**Transformações implementadas:**

| Problema | Técnica SQL | Resultado |
|----------|-------------|-----------|
| Duplicatas de cliente | `ROW_NUMBER() OVER (PARTITION BY customer_id)` | 1 registro canônico por ID |
| Espaços extras | `TRIM(REGEXP_REPLACE(name, '\\s+', ' '))` | Nome normalizado |
| Email inválido | `REGEXP '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$'` | Flag `email_valid` |
| Datas multi-formato | `REGEXP` + `STR_TO_DATE` por padrão detectado | Campo `DATE` tipado |
| Preço negativo | `CASE WHEN price >= 0 THEN price ELSE NULL END` | NULL para preços inválidos |
| Ano inválido | `BETWEEN 1000 AND YEAR(CURDATE())` | NULL para anos fora de range |
| Status inconsistente | `CASE LOWER(TRIM(status)) WHEN 'entregue' THEN 'Entregue'...` | Enum canônico |
| Rating fora de escala | `BETWEEN 1 AND 5` | NULL para ratings inválidos |

**Score de Qualidade por Registro:**

Cada registro na Silver recebe um `data_quality_score` calculado como soma ponderada de campos preenchidos e válidos:

```sql
-- Exemplo para dim_customers (5 critérios, 0.20 cada):
data_quality_score = 
    (customer_id preenchido ? 0.20 : 0) +
    (email válido ? 0.20 : 0) +
    (telefone preenchido ? 0.20 : 0) +
    (data de registro válida ? 0.20 : 0) +
    (data de nascimento válida ? 0.20 : 0)
```

### Camada Gold — Inteligência de Negócio

**Responsabilidade:** Transformar dados limpos em respostas para perguntas de negócio.

**Entregáveis:**

| Artefato | Pergunta de Negócio Respondida |
|----------|-------------------------------|
| `vw_sales_by_category` | "Qual gênero literário gera mais receita?" |
| `vw_top_selling_books` | "Quais livros vender mais no próximo e-mail marketing?" |
| `vw_customer_analytics` | "Quem são nossos clientes VIP? Quem está em risco de churn?" |
| `vw_sales_over_time` | "Nossa receita está crescendo mês a mês?" |
| `vw_payment_analysis` | "PIX ou cartão: qual gera maior ticket médio?" |
| `vw_geographic_analysis` | "Em qual estado devo abrir o próximo centro de distribuição?" |
| `vw_review_analytics` | "Qual livro tem as melhores avaliações para recomendar na homepage?" |
| `agg_daily_metrics` | "Qual foi nossa receita líquida ontem?" (para dashboards) |
| `agg_author_performance` | "Qual autor merece destaque na campanha de Natal?" |

---

## Insights de Negócio Extraídos

### Qualidade dos Dados

- **70% dos registros** na Bronze apresentam alguma inconsistência
- **Score médio de qualidade** estimado: 0.72 para clientes, 0.85 para livros
- **1 duplicata confirmada** (C001 - Maria Silva Santos) que, em escala, representa campanhas duplicadas

### Padrões Detectados

1. **Datas:** 3 formatos coexistem — `YYYY-MM-DD` (predominante), `YYYY/MM/DD` e `DD/MM/YYYY`
2. **Emails:** 2 em 10 são inválidos (sem domínio completo ou string vazia)
3. **Status de pedido:** 5 variações para 4 estados canônicos
4. **Categorias de livro:** 8 categorias distintas com múltiplas grafias cada

### Oportunidades Identificadas

- **Reativação de clientes:** Clientes com status "Em Risco" (60-180 dias sem compra) são candidatos a campanhas de reengajamento
- **Catálogo premium:** Livros com `avg_rating >= 4.5` e alto volume de reviews são candidatos para posições de destaque
- **Concentração geográfica:** Pipeline geográfico revela estados subexplorados com alto potencial

---

## Métricas de Sucesso do Projeto

| KPI | Meta | Como Medir (Gold Layer) |
|-----|------|------------------------|
| Taxa de deduplicação | 100% | `COUNT(DISTINCT customer_id)` em dim_customers vs raw_customers |
| Cobertura de data_quality_score | 100% dos registros | `COUNT(*) WHERE data_quality_score IS NULL = 0` |
| Pedidos válidos identificados | ≥ 80% | `SUM(is_valid_order = TRUE) / COUNT(*)` em fact_orders |
| Views Gold funcionais | 7/7 views | Execução sem erro e retorno de dados |
| Consistência de categoria | 100% | Ausência de duplicatas em `DISTINCT category` de dim_books |
