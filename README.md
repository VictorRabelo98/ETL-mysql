# // PROJETO 01 · ENGENHARIA DE DADOS

## Pipeline ETL com Arquitetura Medallion

> Pipeline ETL completo em três camadas (Bronze / Silver / Gold) para limpeza e qualidade de dados de uma livraria online. Tratamento de duplicatas, normalização de datas em formatos mistos, validação de faixas e cálculo de score de qualidade por registro. Camada Gold com dados agregados prontos para análise de negócio.

---

**Stack:** `MYSQL` · `ETL` · `MEDALLION ARCHITECTURE` · `DATA QUALITY` · `SQL`

---

## Visão Geral

Uma livraria online em crescimento acelerado passa a receber dados de múltiplas fontes: cadastros manuais, importações legadas, integrações com marketplaces e APIs externas. O resultado é um repositório de dados **caótico, inconsistente e não confiável**. Decisões de negócio baseadas nesses dados custam dinheiro, tempo e credibilidade.

Este projeto resolve exatamente esse problema através de um pipeline ETL estruturado com **Arquitetura Medallion** em MySQL puro — sem dependências externas, sem frameworks, apenas SQL.

---

## Arquitetura: Medallion em 3 Camadas

```
┌─────────────────────────────────────────────────────────┐
│                   BRONZE LAYER                          │
│            Dados brutos, exatamente como vieram         │
│   raw_customers · raw_books · raw_orders                │
│   raw_order_items · raw_reviews                         │
└─────────────────────┬───────────────────────────────────┘
                      │  ETL + Validação + Limpeza
                      ▼
┌─────────────────────────────────────────────────────────┐
│                   SILVER LAYER                          │
│         Dados limpos, tipados e normalizados            │
│   dim_customers · dim_books · fact_orders               │
│   fact_order_items · fact_reviews                       │
└─────────────────────┬───────────────────────────────────┘
                      │  Agregação + Análise
                      ▼
┌─────────────────────────────────────────────────────────┐
│                    GOLD LAYER                           │
│       Dados prontos para análise de negócio             │
│   7 Views analíticas · 2 Tabelas agregadas              │
│   Segmentação RFM · KPIs · Métricas temporais           │
└─────────────────────────────────────────────────────────┘
```

---

## Problemas de Negócio Resolvidos

| Problema | Impacto | Solução no Pipeline |
|----------|---------|---------------------|
| Registros duplicados de clientes | Campanhas enviadas em duplicata, métricas infladas | Deduplicação por `customer_id` com seleção do registro mais antigo |
| Datas em 3 formatos diferentes | Falha em relatórios temporais | Detecção por REGEXP + STR_TO_DATE multi-formato |
| Preços negativos no catálogo | Pedidos com valor inválido processados | Validação `price >= 0`, registros inválidos recebem NULL |
| Ratings fora da escala (−2 a 12) | Média de avaliações distorcida | Filtro `BETWEEN 1 AND 5` |
| Status de pedido inconsistente | Dashboard com status fragmentado | Mapeamento canônico (entregue → Entregue, PIX → PIX) |
| Pedidos com data futura | Revenue projetado contabilizado como realizado | Validação `order_date <= CURDATE()` |
| Score de qualidade ausente | Impossível priorizar limpeza incremental | Campo `data_quality_score` por registro (0.00 → 1.00) |

---

## Estrutura de Arquivos

```
ETL-mysql/
├── README.md                         ← Este arquivo
├── docs/
│   ├── STORYTELLING.md               ← Narrativa do projeto
│   ├── BUSINESS_CONTEXT.md           ← Problema e contexto de negócio
│   ├── ARCHITECTURE.md               ← Arquitetura técnica detalhada
│   ├── DATA_QUALITY.md               ← Relatório de qualidade de dados
│   ├── STACK.md                      ← Stack tecnológica
│   └── CODE_CHANGES.md               ← O que foi corrigido e por quê
├── sql-project/
│   ├── 1.sql                         ← Bronze Layer (dados brutos originais)
│   ├── 2.sql                         ← Silver Layer (transformações originais)
│   ├── 3.sql                         ← Gold Layer (analytics originais)
│   └── corrected/
│       ├── 1_bronze_corrected.sql    ← Bronze com melhorias
│       ├── 2_silver_corrected.sql    ← Silver com bugs corrigidos
│       └── 3_gold_corrected.sql      ← Gold consolidado e corrigido
└── Fluxo Completo do Projeto ETL.pdf
```

---

## Como Executar

```sql
-- Execute na ordem:
SOURCE sql-project/1.sql;   -- Cria schemas e carrega dados brutos
SOURCE sql-project/2.sql;   -- Limpa e transforma (Silver layer)
SOURCE sql-project/3.sql;   -- Gera visões e agregações (Gold layer)

-- Ou use as versões corrigidas:
SOURCE sql-project/corrected/1_bronze_corrected.sql;
SOURCE sql-project/corrected/2_silver_corrected.sql;
SOURCE sql-project/corrected/3_gold_corrected.sql;
```

---

## Resultado: Dados Prontos para Análise

Após o pipeline, a Gold layer entrega:

- **`vw_sales_by_category`** — Receita e volume por categoria de livro
- **`vw_top_selling_books`** — Ranking de livros por cópias vendidas
- **`vw_customer_analytics`** — Segmentação RFM (Ativo / Em Risco / Inativo) + tier (VIP / Regular / Novo)
- **`vw_sales_over_time`** — Série temporal de vendas por mês
- **`vw_payment_analysis`** — Distribuição de métodos de pagamento com % de receita
- **`vw_geographic_analysis`** — Receita e pedidos por estado e cidade
- **`vw_review_analytics`** — Distribuição de ratings e sentimento por livro
- **`agg_daily_metrics`** — Métricas diárias pré-calculadas para dashboards
- **`agg_author_performance`** — Performance de cada autor (vendas + reviews)

---

## Autor

Desenvolvido por **Victor Rabelo** | Engenharia de Dados

[![GitHub](https://img.shields.io/badge/GitHub-victorrabelo98-black)](https://github.com/VictorRabelo98/ETL-mysql)
