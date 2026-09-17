# eleicoes2026 — dbt (Databricks)

Projeto dbt que tira do Power BI **"pesquisas eleitorais"** as regras de limpeza e de qualidade
que hoje estão espalhadas em Power Query e em colunas calculadas DAX. O Power BI passa a ler
tabelas já tratadas e testadas e fica só com as medidas.

```
.github/workflows/     carga agendada (GitHub Actions) + disparo do job dbt
ingestion/            carga_raw.py (usado pelo Actions) e notebook alternativo; tudo string
seeds/                DE-PARA de institutos e candidatos
macros/limpeza.sql    tse_texto, br_decimal, tse_timestamp, texto_para_decimal, mes_para_numero
models/staging/       tipagem + sentinelas TSE + remoção de artefatos
models/intermediate/  regras de negócio, flags de qualidade, padronização e chaves
models/marts/         fct_pesquisas_registradas, dim_instituto, fct_intencao_voto,
                      fct_resultado_oficial_2022, dim_calendario (+ exposure do Power BI)
snapshots/            histórico de alterações dos registros no PesqEle
tests/                testes singulares (soma de cenários, alertas de qualidade, resultado 2022)
```

## Problemas de qualidade encontrados no modelo atual (perfil em 15/09/2026)

| # | Tabela Power BI | Problema | Tratamento no dbt |
|---|---|---|---|
| 1 | f2022_ResultadoOficial | `Data Totalizacao` tem hora; relação com `dCalendario[Date]` **não casa em nenhuma das 103.379 linhas** | `dt_totalizacao` (date) separado de `ts_totalizacao`; teste `relationships` |
| 2 | f2022_ResultadoOficial | Nomes vindos do cabeçalho perdem acento/apóstrofo (Felipe Davila, Leo Pericles, "Vera") | seed `de_para_candidato` |
| 3 | f2022_ResultadoOficial | Sem marcação do resultado final (13.723 instantes de totalização) | `fl_resultado_final` |
| 4 | 2026_Pesquisas | Todas as 26 colunas como texto; datas e números convertidos em DAX | tipagem no staging (macros) |
| 5 | 2026_Pesquisas | `#NULO#` em 127 de 603 nomes fantasia | `tse_texto()` + fallback razão social |
| 6 | 2026_Pesquisas | 23 pesquisas com divulgação antes do fim do campo | `fl_dq_divulgacao_antes_fim_campo` (warn) |
| 7 | 2026_Pesquisas | 2 registros com menos de 5 dias até a divulgação (prazo legal) | `fl_dq_registro_fora_prazo_legal` (warn) |
| 8 | 2026_Pesquisas | 1 amostra inválida; 1 metodologia não classificada | flags + teste `accepted_values` |
| 8b | 2026_Pesquisas | `Método de Coleta` (DAX) usa `CONTAINSSTRING("ura")`, que casa com "estrut**ura**do": "Questionário estruturado web" vira URA | regex com palavra inteira (`\\bura\\b`) |
| 9 | 2026_Pesquisas | Instituto identificado por texto, não por CNPJ | `dim_instituto` por CNPJ |
| 10 | 2026_Pesquisas | Filtro `NM_UE = "BRASIL"` na carga esconde as demais UEs | todas as UEs + `fl_abrangencia_nacional` |
| 11 | f2026_IntencaoVoto | Colunas-artefato como dado: `Header` classificado como Candidato, `Vantagem` como Não-resposta | `tp_resposta = 'Artefato'` removido |
| 12 | f2026_IntencaoVoto | Candidato com grafias diferentes: `Flávio  PL`/`Flávio PL`, `Tereza PP`/`Tereza C. PP`, `Ciro PDT`/`Gomes PDT` | limpeza de espaços + seed; nome e partido separados |
| 13 | f2026_IntencaoVoto | Instituto com variações/typo: `Atlasinstel`, `Nexus/BTG` x `Nexus/BTG Pactual`, `Quaest` x `Genial/Quaest` | seed `de_para_instituto` |
| 14 | f2026_IntencaoVoto | `Cenario` = posição da tabela na página; muda a cada edição da Wikipedia | `id_pesquisa` e `id_cenario` por hash do conteúdo |
| 15 | f2026_IntencaoVoto | Período sem data ("27 Mar - 29 Mar"), margem como texto | `dt_inicio_campo`, `dt_fim_campo`, `pc_margem_erro` |
| 16 | f2026_IntencaoVoto | Sem checagem de consistência | teste: soma por cenário entre 90% e 110% |

## De → para (Power BI → dbt)

| Power BI | dbt |
|---|---|
| `2026_Pesquisas[Data Início/Fim Campo, Data Divulgação, Data Registro]` (DAX) | `fct_pesquisas_registradas.dt_*` |
| `[Qtd Entrevistados]`, `[Valor Pesquisa]`, `[Custo por Entrevista]` | `qt_entrevistados`, `vr_pesquisa`, `vr_custo_por_entrevista` |
| `[Tipo Contratação]`, `[Método de Coleta]`, `[Instituto]` | `tp_contratacao`, `tp_metodo_coleta`, `nm_instituto` |
| medida `Margem de Erro Teórica` (sobre a média) | `pc_margem_erro_teorica` por pesquisa (a medida pode continuar) |
| `f2026_IntencaoVoto` (Power Query) | `fct_intencao_voto` |
| `f2022_ResultadoOficial` (Power Query) | `fct_resultado_oficial_2022` |
| `dCalendario` (tabela calculada) | `dim_calendario` (inclui dias até o 2º turno) |
| função `fnUnzip` | desnecessária (a carga roda no GitHub Actions) |

As **medidas DAX continuam no Power BI**; troque apenas as referências de coluna.

## Arquitetura

```
GitHub Actions (todo dia 06h BRT ou manual)
  ingestion/carga_raw.py
    TSE (zips) + Wikipedia  ->  parquet  ->  Volume workspace.raw_eleicoes.landing
                                         ->  tabelas workspace.raw_eleicoes.*   (tudo string)
  dispara o job do dbt Platform
    staging -> intermediate -> marts + testes
Power BI  ->  conector Databricks (SQL Warehouse)  ->  workspace.marts.*
```

A carga roda **fora** do Databricks porque a Free Edition bloqueia acesso de saída à internet
("serverless network policy" — testado em 17/09/2026 para cdn.tse.jus.br, dadosabertos.tse.jus.br
e pt.wikipedia.org). Conexões de entrada funcionam normalmente. Em um workspace pago, o notebook
`ingestion/01_carga_raw_databricks.py` faz a mesma carga de dentro do Databricks.

## Configuração (uma vez)

### GitHub → Settings → Secrets and variables → Actions

| Tipo | Nome | Valor |
|---|---|---|
| Secret | `DATABRICKS_TOKEN` | token `dapi...` |
| Variable | `DATABRICKS_HOST` | `dbc-f1556444-f00a.cloud.databricks.com` |
| Variable | `DATABRICKS_WAREHOUSE_ID` | `73dc97c464e41132` |
| Variable (opcional) | `DATABRICKS_CATALOG` / `DATABRICKS_SCHEMA` | padrão `workspace` / `raw_eleicoes` |
| Secret (opcional) | `DBT_CLOUD_API_TOKEN` | token de serviço do dbt com permissão de disparar jobs |
| Variable (opcional) | `DBT_CLOUD_HOST` | host de acesso do dbt (ex.: `us1.dbt.com` ou o subdomínio da conta) |
| Variable (opcional) | `DBT_CLOUD_ACCOUNT_ID` / `DBT_CLOUD_JOB_ID` | ids numéricos (aparecem na URL do job) |

Sem as variáveis do dbt, o workflow só faz a carga; o job do dbt pode ser agendado no próprio dbt.

### dbt Platform → Deploy → Jobs → Create job (ambiente Production)

Comandos: `dbt deps` · `dbt seed` · `dbt snapshot` · `dbt build`. Sem agendamento próprio se for
disparado pelo GitHub Actions; caso contrário, agende para depois das 06h.

### Rodar manualmente

GitHub → Actions → "Carga eleicoes2026" → **Run workflow** (dá para escolher só algumas fontes).
Local, sem gravar no Databricks: `DRY_RUN=1 python ingestion/carga_raw.py` (gera `saida/*.parquet`).

### Power BI

Obter dados → Azure Databricks → Server hostname + HTTP path do warehouse → catálogo `workspace`,
schema `marts`. Substituir `2026_Pesquisas`, `f2026_IntencaoVoto`, `f2022_ResultadoOficial` e
`dCalendario` pelas tabelas do dbt e remover as colunas calculadas de limpeza.

dbt Core local: copie `profiles.yml.exemplo` para `~/.dbt/profiles.yml`.

## A revisar

- Linhas com `revisar = true` nos seeds (ex. `Gomes PSDB`, `Barbosa DC`, `Cury Avante`, `Lima Sem partido`, `Vox`).
- Se `*_PE_VOTOS_TOT_ACUMULADO` é % dos votos válidos ou do total (teste `assert_resultado_final_2022_soma_100`).
- A Wikipedia não informa o ano do campo. A regra usa o ano da carga e volta 1 ano se a data cair no futuro.
