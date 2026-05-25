# A História por Trás do Pipeline

## Capítulo 1: O Crescimento que Criou o Caos

Era o início de 2023. A **LibreBooks**, uma livraria online brasileira em expansão, estava crescendo rápido demais para o seu próprio bem.

Em seis meses, a empresa havia integrado três sistemas diferentes: o cadastro original feito em planilha Excel, uma migração de um sistema legado de ponto de venda físico, e os novos cadastros diretos pela plataforma web. Cada sistema tinha seu próprio padrão. Nenhum conversava com o outro.

O resultado: um banco de dados MySQL com **11 mil registros de clientes, onde 23% estavam duplicados**. Datas de nascimento em `15/04/1990`, `1990-04-15` e `15-04-1990` — o mesmo dia, três formatos impossíveis de comparar. Preços negativos que faziam o relatório de receita mostrar números que desafiavam a matemática.

O time de marketing enviou uma campanha de aniversário para 2.400 clientes. Trezentos receberam dois e-mails. Oito receberam três. A taxa de cancelamento de newsletter foi a mais alta da história da empresa.

O CEO perguntou: *"Quantos clientes ativos temos de verdade?"*

Ninguém sabia responder com certeza.

---

## Capítulo 2: O Diagnóstico

O engenheiro de dados chamado para resolver o problema começou pela análise dos dados brutos. O que encontrou foi um retrato fiel de como **dados sem governança evoluem na prática**:

**Nos clientes:**
- `C001 - Maria Silva Santos` aparecia duas vezes, registro idêntico
- `C004 - Carlos Eduardo` tinha espaços extras no nome: `"  Carlos Eduardo  "`
- O estado de um cliente estava como `"rj"` (minúsculo), outro como `"Brasil"` no campo de estado
- Emails como `"joao@invalid"` sem domínio passavam pela validação básica
- Datas em três formatos diferentes, coexistindo na mesma coluna VARCHAR

**Nos livros:**
- `B005 - A Menina que Roubava Livros` com preço `-15.50` — negativo
- `B011 - A Revolução dos Bichos` publicado no ano `3000`
- Categorias como `"fantasia"`, `"Fantasia"` e `"FICÇÃO"` para o mesmo gênero
- Códigos de idioma como `"pt"`, `"PT"`, `"pt-br"`, `"PT-BR"` para o mesmo idioma

**Nos pedidos:**
- `ORD007` com data `2025-12-30` — um pedido do futuro sendo contabilizado na receita atual
- `ORD005` com `total_amount = ""` — campo obrigatório vazio
- Status como `"entregue"`, `"Entregue"`, `"PROCESSANDO"` para os mesmos estados

**Nas avaliações:**
- `R006` com rating `12` — seis estrelas em uma escala de cinco
- `R011` com rating `-2` — avaliação abaixo do mínimo possível
- `R012` com `review_date = "invalid-date"` — string literal, não uma data

Ao todo: **47 registros com problemas críticos** entre 67 registros totais. Taxa de problema: **70%**.

---

## Capítulo 3: A Solução — Arquitetura Medallion

A decisão foi construir um pipeline ETL estruturado com **Arquitetura Medallion**. A filosofia é simples: nunca destrua o dado original. Em vez disso, crie camadas progressivas de qualidade.

### Bronze: Preserve a Realidade

A camada Bronze é um espelho fiel da fonte. Todos os campos são `VARCHAR`. Nenhum dado é rejeitado. Nenhum formato é exigido. O objetivo é capturar a realidade bruta exatamente como ela é — erros incluídos.

Isso garante **rastreabilidade**. Se uma transformação Silver gerar dúvidas, o engenheiro pode sempre voltar ao Bronze para entender de onde veio o dado.

### Silver: Construa a Verdade

A camada Silver é onde acontece o trabalho real. Cada transformação é uma decisão de negócio:

- *"O que fazemos com um email sem @?"* → Marcar como inválido, manter o registro
- *"O que fazemos com um preço negativo?"* → Converter para NULL, não deletar
- *"Como unificamos três formatos de data?"* → REGEXP para detectar, STR_TO_DATE para converter

Cada registro recebe um `data_quality_score` entre 0.00 e 1.00. Um cliente sem email válido, sem telefone e com data de nascimento inválida recebe score baixo. Um cliente completo e consistente recebe 1.00. Esse score é **combustível para priorização de limpeza incremental**.

### Gold: Entregue Valor

A camada Gold transforma dados limpos em inteligência de negócio. Sete views analíticas e duas tabelas pré-agregadas:

- O CEO agora pode ver exatamente quantos clientes estão ativos (compra nos últimos 60 dias)
- O time de marketing pode segmentar por tier: VIP (gasto ≥ R$300), Regular (≥ R$150), Novo
- O time de produto pode identificar quais categorias de livros geram mais receita
- O time financeiro pode ver métricas diárias de receita bruta, descontos e receita líquida

---

## Capítulo 4: O Resultado

Após o pipeline:

| Métrica | Antes (Bronze) | Depois (Silver) | Melhoria |
|---------|----------------|-----------------|----------|
| Clientes únicos | 11 (com 1 duplicata) | 10 únicos | Deduplicação 100% |
| Emails válidos | ~60% | 70% (marcados e rastreados) | Visibilidade total |
| Pedidos com data válida | 83% | 83% (com flag is_valid_order) | Rastreável |
| Score médio de qualidade de clientes | N/A | 0.72 | Baseline estabelecido |
| Categorias de livros distintas | 8 variações | 8 canônicas | Consistência |

O CEO finalmente tinha sua resposta: **9 clientes únicos com cadastro completo**, dos quais 7 haviam feito pedido válido nos últimos 12 meses. Dos 7, 2 eram VIP, 3 eram Regular e 2 eram Novo.

Números pequenos porque este é um dataset de demonstração — mas o padrão escalaria para 1 milhão de registros.

---

## Epílogo: Dados como Ativo

Este projeto demonstra um princípio fundamental da engenharia de dados moderna:

> *Dados ruins não são apenas um problema técnico. São um problema de negócio que custa dinheiro real.*

A Arquitetura Medallion não é apenas uma estrutura técnica. É um contrato com o negócio: **você pode confiar nos dados da Gold layer**. Cada query que um analista executa ali parte de uma base confiável, validada, documentada.

E quando surgir uma nova fonte de dados com seus próprios formatos e inconsistências — basta adicionar uma nova ingestão na Bronze e deixar o pipeline fazer o trabalho.

---

*Pipeline ETL com Arquitetura Medallion · Projeto 01 · Engenharia de Dados*
*VRC. · victorrabelo98*
