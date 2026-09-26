# eleicoes2026

Pipeline que acompanha a eleição presidencial de 2026: coleta as pesquisas registradas no
TSE e os resultados publicados na Wikipédia, trata e testa tudo com dbt no Databricks e
publica um painel público.

**Painel:** https://pedro-parreiracruz.github.io/eleicoes2026/

## Como funciona

```
GitHub Actions (servidores do GitHub; horários de Brasília)
  05:17  carga completa
         ingestion/carga_raw.py: TSE (zips) + Wikipédia -> parquet -> workspace.raw_eleicoes.*
         dbt build: seeds + snapshots + staging -> intermediate -> marts -> marts.painel_* + testes
         site/gerar.py: lê marts.painel_* -> docs/index.html -> GitHub Pages
  06:07 a 18:07, a cada 3 horas  checagem
         ingestion/verificar_wikipedia.py: a tabela de pesquisas mudou desde a última carga?
         não -> para aí, sem ligar o Databricks
         sim -> carrega a Wikipédia, roda o dbt e republica o painel
```

Nada depende de máquina ligada: tudo roda nos servidores do GitHub. A carga fica **fora** do
Databricks porque a Free Edition bloqueia acesso de saída à internet ("serverless network
policy", testado em 17/09/2026 para cdn.tse.jus.br, dadosabertos.tse.jus.br e pt.wikipedia.org).

## Estrutura

```
.github/workflows/
  carga_eleicoes.yml      carga diária, checagem a cada 3 horas e dbt build
  publicar_site.yml       gera docs/index.html a partir dos modelos painel_* e publica
ingestion/
  carga_raw.py            baixa TSE e Wikipédia e grava as tabelas cruas (tudo string)
  verificar_wikipedia.py  impressão digital da tabela da Wikipédia (checagem horária)
ci/profiles.yml           profile do dbt usado pelo Actions
seeds/                    de-para de institutos e candidatos; candidatos registrados no TSE
macros/                   limpeza (tse_texto, br_decimal, sem_notas...) e nome de schema
models/staging/           tipagem, sentinelas do TSE e remoção de artefatos da Wikipédia
models/intermediate/      regras de negócio, flags de qualidade, padronização e chaves
models/marts/             fatos e dimensões (fct_intencao_voto, fct_pesquisas_registradas,
                          fct_resultado_oficial_2022, dim_instituto, dim_calendario)
models/marts/painel/      um modelo por bloco do painel (painel_*)
snapshots/                histórico de alterações dos registros de pesquisa no TSE
tests/                    testes singulares (soma de cenários, alertas, resultado 2022)
site/                     modelo.html (o painel), gerar.py, LEIA-ME.md e o contador opcional
docs/index.html           o painel publicado (gerado; não editar à mão)
```

## Fontes

| Fonte | O que traz | Como chega |
| --- | --- | --- |
| TSE — PesqEle 2026 | pesquisas registradas: instituto, contratante, amostra, valor, datas | zip de dados abertos |
| TSE — totalização 2022 | resultado oficial do 1º e do 2º turno de 2022, para comparação | zip de dados abertos |
| Wikipédia | intenção de voto divulgada por cada instituto, por cenário | tabelas da página de pesquisas |

O CDN do TSE tem proteção anti-bot, por isso a carga usa `curl_cffi` (assinatura de Chrome).

## Camadas do dbt

- **staging** — tipagem e limpeza: datas, decimais brasileiros, sentinelas (`#NULO#`), notas de
  rodapé coladas no texto (`Quaest[17]`) e artefatos de tabela da Wikipédia.
- **intermediate** — regras de negócio: método de coleta, flags de qualidade, padronização de
  nomes por seed e chaves de pesquisa e de cenário por hash do conteúdo.
- **marts** — fatos e dimensões usados pelo painel e por qualquer outro consumidor.
- **marts/painel** — um modelo por bloco do painel, com as colunas legíveis e mais `linha`
  (o texto exato que vai para o HTML) e `nr_ordem` (a ordem em que entra).

Testes rodam junto com o build (`dbt build`). Falhas em modo `warn` não quebram a carga: as
linhas reprovadas ficam materializadas em `workspace.dq_falhas.*`, uma tabela por teste.

## Configuração (uma vez)

GitHub → Settings → Secrets and variables → Actions, no environment `producao`:

| Tipo | Nome | Valor |
| --- | --- | --- |
| Secret | `DATABRICKS_TOKEN` | token `dapi...` |
| Variable | `DATABRICKS_HOST` | `dbc-XXXXXXXX-XXXX.cloud.databricks.com` (SQL Warehouses → Connection details) |
| Variable | `DATABRICKS_WAREHOUSE_ID` | o trecho final do HTTP path, em `/sql/1.0/warehouses/<id>` |
| Variable (opcional) | `DATABRICKS_CATALOG` / `DATABRICKS_SCHEMA` | padrão `workspace` / `raw_eleicoes` |
| Variable (opcional) | `CONTADOR_URL` | contador de acessos do painel; vazio, o contador some |
| Variable (opcional) | `PAINEL_FONTE` | `consulta` faz o painel voltar à consulta antiga (rollback) |

O `DATABRICKS_HTTP_PATH` do dbt é montado a partir do warehouse id.

## Rodar na mão

- **Carga e painel:** GitHub → Actions → "Carga eleicoes2026" → *Run workflow* (dá para escolher
  as fontes; o disparo manual sempre carrega, sem checar se a Wikipédia mudou).
- **Só republicar o painel:** Actions → "Publicar painel" → *Run workflow*.
- **Carga local, sem gravar no Databricks:** `DRY_RUN=1 python ingestion/carga_raw.py`
  (gera `saida/*.parquet`).
- **dbt local:** copie `profiles.yml.exemplo` para `~/.dbt/profiles.yml` (o `ci/profiles.yml` é
  só do CI) e rode `dbt build`.

## O painel

`site/LEIA-ME.md` explica os modelos `painel_*`, o rollback para a consulta antiga, o contador
de acessos e como o painel é republicado. `site/modelo.html` é o painel em si, com marcadores
(`__P1T__`, `__D2T__`…) que o `gerar.py` preenche; ele é a mesma página publicada no artifact
do claude.ai.

## Limitações conhecidas

- A Wikipédia não informa o ano do campo: a regra usa o ano da carga e volta um ano se a data
  cair no futuro.
- Linhas com `revisar = true` nos seeds esperam confirmação humana.
- O 1º turno só usa cenários com a lista oficial de candidatos; cenários hipotéticos ficam nos
  duelos de 2º turno, marcados na tela.
- Consumo do warehouse depende da cota da Free Edition do Databricks; se ela estourar, a carga
  falha e o painel fica com o último dado bom.
