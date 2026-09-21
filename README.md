# eleicoes2026 — pesquisas eleitorais 2026 (Databricks + dbt + painel público)

Pipeline que coleta as pesquisas da eleição presidencial de 2026 (registro no TSE e resultados
publicados na Wikipédia), trata e testa tudo com dbt no Databricks e publica um painel público:
**https://pedro-parreiracruz.github.io/eleicoes2026/**

Começou tirando do Power BI **"pesquisas eleitorais"** as regras de limpeza e de qualidade que
estavam em Power Query e DAX (histórico mais abaixo); hoje as mesmas tabelas alimentam o painel.

```
.github/workflows/
  carga_eleicoes.yml     carga diária completa + checagem de hora em hora da Wikipédia + dbt
  publicar_site.yml      gera docs/index.html a partir dos modelos painel_* e publica no Pages
ingestion/
  carga_raw.py           baixa TSE e Wikipédia e grava as tabelas raw (tudo string)
  verificar_wikipedia.py impressão digital da tabela da Wikipédia (a checagem horária)
ci/profiles.yml          profile do dbt usado pelo Actions
seeds/                   DE-PARA de institutos e candidatos, candidatos registrados no TSE
macros/                  limpeza (tse_texto, br_decimal, sem_notas...) e nome de schema
models/staging/          tipagem + sentinelas TSE + remoção de artefatos
models/intermediate/     regras de negócio, flags de qualidade, padronização e chaves
models/marts/            fatos e dimensões (fct_intencao_voto, fct_pesquisas_registradas...)
models/marts/painel/     um modelo por bloco do painel público (painel_*)
snapshots/               histórico de alterações dos registros no PesqEle
tests/                   testes singulares
site/                    modelo.html (o painel), gerar.py, LEIA-ME.md e o contador opcional
docs/index.html          o painel publicado (gerado; não editar à mão)
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
| 8b | 2026_Pesquisas | `Método de Coleta` (DAX) usa `CONTAINSSTRING("ura")`, que casa com "estrut**ura**do". Nos dados de 17/09/2026, 2.171 de 2.465 metodologias citam "questionário estruturado": **94% das pesquisas viram URA** (real: 11%) | regex com palavra inteira + termos presenciais; distribuição: Presencial 1.469 · Telefone 317 · URA 261 · Web 134 · Não classificada 284 |
| 9 | 2026_Pesquisas | Instituto identificado por texto, não por CNPJ | `dim_instituto` por CNPJ |
| 10 | 2026_Pesquisas | Filtro `NM_UE = "BRASIL"` na carga esconde as demais UEs | todas as UEs + `fl_abrangencia_nacional` |
| 11 | f2026_IntencaoVoto | Colunas-artefato como dado: `Header` classificado como Candidato, `Vantagem` como Não-resposta | `tp_resposta = 'Artefato'` removido |
| 12 | f2026_IntencaoVoto | Candidato com grafias diferentes: `Flávio  PL`/`Flávio PL`, `Tereza PP`/`Tereza C. PP`, `Ciro PDT`/`Gomes PDT` | limpeza de espaços + seed; nome e partido separados |
| 13 | f2026_IntencaoVoto | Instituto com variações/typo: `Atlasinstel`, `Nexus/BTG` x `Nexus/BTG Pactual`, `Quaest` x `Genial/Quaest` | seed `de_para_instituto` |
| 14 | f2026_IntencaoVoto | `Cenario` = posição da tabela na página; muda a cada edição da Wikipedia | `id_pesquisa` e `id_cenario` por hash do conteúdo |
| 15 | f2026_IntencaoVoto | Período sem data ("27 Mar - 29 Mar"), margem como texto | `dt_inicio_campo`, `dt_fim_campo`, `pc_margem_erro` |
| 16 | f2026_IntencaoVoto | Sem checagem de consistência | teste: soma por cenário entre 90% e 110% |
| 17 | f2026_IntencaoVoto | Nome da Wikipedia vinha com a nota de rodapé colada: `Quaest[17]` x `Quaest[34][35]` x `Genial/Quaest [190]` — **244 "institutos" distintos**. Os dígitos da nota também entravam nos números (amostra de 138.139.140) | macro `sem_notas()` aplicada a instituto, período, amostra e margem no staging; 244 → 28 institutos |
| 18 | f2026_IntencaoVoto | A carga usava `pd.read_html` com os padrões do pandas: `thousands=","` virava `45,2` em **452** e `decimal="."` virava `2.000` em **2.0**. Percentual com decimal caía no filtro 0–100 e a margem máxima dava 300 p.p. | `carga_raw.py` lê cada wikitable isolada com `thousands=None` e `converters=str` (texto preservado); margem máxima 3,5 p.p., 1.182 linhas com decimal recuperadas |

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
GitHub Actions (servidores do GitHub; horário de Brasília)
  05:17  carga completa
         ingestion/carga_raw.py: TSE (zips) + Wikipédia -> parquet -> workspace.raw_eleicoes.*
         dbt build: seeds + snapshots + staging -> intermediate -> marts -> marts.painel_* + testes
         site/gerar.py: lê marts.painel_* -> docs/index.html -> GitHub Pages
  06:07-18:07, de hora em hora  checagem
         ingestion/verificar_wikipedia.py: a tabela mudou desde a última carga?
         não -> para (sem Databricks) · sim -> carga da Wikipédia + dbt build + site
Power BI  ->  conector Databricks (SQL Warehouse)  ->  workspace.marts.*
```

A carga roda **fora** do Databricks porque a Free Edition bloqueia acesso de saída à internet
("serverless network policy" — testado em 17/09/2026 para cdn.tse.jus.br, dadosabertos.tse.jus.br
e pt.wikipedia.org). Conexões de entrada funcionam normalmente.

Detalhes do painel, do rollback para a consulta antiga e do contador: `site/LEIA-ME.md`.

## Configuração (uma vez)

### GitHub → Settings → Secrets and variables → Actions

| Tipo | Nome | Valor |
|---|---|---|
| Secret | `DATABRICKS_TOKEN` | token `dapi...` |
| Variable | `DATABRICKS_HOST` | `dbc-XXXXXXXX-XXXX.cloud.databricks.com` — Databricks → SQL Warehouses → o warehouse → Connection details → Server hostname |
| Variable | `DATABRICKS_WAREHOUSE_ID` | id do warehouse: o trecho final do HTTP path, em `/sql/1.0/warehouses/<id>` |
| Variable (opcional) | `DATABRICKS_CATALOG` / `DATABRICKS_SCHEMA` | padrão `workspace` / `raw_eleicoes` |

Os três primeiros ficam no **Environment `producao`** (Settings → Environments), que é o que os
jobs do workflow declaram. O `DATABRICKS_HTTP_PATH` do dbt é montado a partir do warehouse id.

### Transformação

O job `dbt build (Databricks)` do workflow instala dbt Core + dbt-databricks e roda
`dbt deps` · `dbt debug` · `dbt build` (build = seeds + snapshots + models + testes) com
`DBT_PROFILES_DIR=ci` e `--target prod`. Não depende de job configurado no dbt Platform — a UI do
dbt continua servindo para explorar a linhagem, editar modelos e rodar consultas.
Os artefatos (`manifest.json`, `run_results.json`) ficam anexados a cada execução do Actions.

Falhas de teste em modo `warn` não quebram o build: elas ficam materializadas em
`workspace.dq_falhas.*`, uma tabela por teste.

### Rodar manualmente

GitHub → Actions → "Carga eleicoes2026" → **Run workflow** (dá para escolher só algumas fontes; o disparo manual sempre carrega, sem checar se mudou).
Local, sem gravar no Databricks: `DRY_RUN=1 python ingestion/carga_raw.py` (gera `saida/*.parquet`).

### Power BI

Obter dados → Azure Databricks → Server hostname + HTTP path do warehouse → catálogo `workspace`,
schema `marts`. Substituir `2026_Pesquisas`, `f2026_IntencaoVoto`, `f2022_ResultadoOficial` e
`dCalendario` pelas tabelas do dbt e remover as colunas calculadas de limpeza.

dbt Core local: copie `profiles.yml.exemplo` para `~/.dbt/profiles.yml` (o `ci/profiles.yml` é só do CI).

## A revisar

- Linhas com `revisar = true` nos seeds (ex. `Gomes PSDB`, `Barbosa DC`, `Cury Avante`, `Lima Sem partido`, `Vox`).
- `*_PE_VOTOS_TOT_ACUMULADO` vem como fração ("   0,484307") e é convertido para % no staging; validado: resultado final soma 100,000% dos válidos (1T Lula 48,43%, 2T Lula 50,90%).
- A Wikipedia não informa o ano do campo. A regra usa o ano da carga e volta 1 ano se a data cair no futuro.
