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
         sim -> carrega a Wikipédia, dbt run do que depende dela (sem testes) e republica
```

Nada depende de máquina ligada: tudo roda nos servidores do GitHub. A carga fica **fora** do
Databricks porque a Free Edition bloqueia acesso de saída à internet ("serverless network
policy", testado em 17/09/2026 para cdn.tse.jus.br, dadosabertos.tse.jus.br e pt.wikipedia.org).

## Estrutura

```
.github/workflows/
  carga_eleicoes.yml      carga diária, checagem a cada 3 horas e dbt build
  publicar_site.yml       gera docs/index.html a partir dos modelos painel_* e publica
  verificar_propostas.yml confere a cada 3 horas se algum plano de governo mudou no TSE
ingestion/
  carga_raw.py            baixa TSE e Wikipédia e grava as tabelas cruas (tudo string)
  verificar_wikipedia.py  impressão digital da tabela da Wikipédia (checagem a cada 3 horas)
  verificar_propostas.py  compara o PDF de plano de governo lido no painel com o do TSE
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

## Metodologia das médias

A mesma explicação aparece no painel, em "Como as médias são calculadas".

- Só entram pesquisas com registro localizado no TSE (`painel_registro_tse`).
- 1º turno: só cenários em que todos os nomes têm candidatura registrada; vários cenários da
  mesma pesquisa viram a média deles.
- Cada pesquisa é reescalada proporcionalmente para somar 100% (os institutos arredondam cada
  número e a soma publicada varia de ~97% a ~107%). Indecisos, brancos, nulos e "outros" são uma
  fatia só. Os blocos do HTML guardam o número como publicado; a reescala é feita na página.
- Linha do tempo: média simples das pesquisas com fim de campo no mesmo dia, sem peso por
  amostra, método ou instituto; candidato ausente de uma pesquisa conta zero nela, para o dia
  fechar 100%. Série com mais de 14 dias: linha cheia = média móvel centrada de 5 pontos.
- Barras: média das pesquisas do período em que o candidato aparece, com faixa mínimo–máximo.
- 2º turno: simulações de dois nomes, reescaladas para 100% com indecisos/brancos/nulos (sem
  esse dado, a diferença para 100% conta como indecisos); média simples por dia.
- "Pesquisa mais recente" (chip do topo) e o início de campo dela saem só das pesquisas que o
  painel mostra (`painel_1t_pesquisas` e `painel_2t_duelos`, conferidas de novo no
  `site/gerar.py`); cenário que não entra em nenhum gráfico não mexe nessa data.

## Planos de governo

O resumo da aba Propostas (constante `PROP` em `site/modelo.html`) é feito por gente, a partir
do PDF que cada candidatura protocolou no TSE (DivulgaCandContas, arquivo do tipo 5). O workflow
`verificar_propostas.yml` (06:37 a 18:37, a cada 3 horas, sem Databricks) compara o PDF lido com
o que o TSE mostra. Se mudou, grava `site/propostas_tse.json`, abre uma issue e republica: o painel
passa a mostrar o aviso "nova versão no TSE, resumo em revisão" e o link para o PDF novo até o
resumo ser refeito.

## Limitações conhecidas

- Desde 01/10/2026 o warehouse parado às vezes não liga sozinho quando chega uma consulta
  ("Cannot create the resource"), embora ligue pelo botão Start. Por isso cada job que usa o
  Databricks começa por `ingestion/ligar_warehouse.py`, que faz o mesmo que o botão e espera o
  estado RUNNING.

- **Só entram pesquisas registradas no TSE** (Lei 9.504/97, art. 33). A Wikipédia não traz o
  número de registro, então `painel_registro_tse` casa cada pesquisa com o PesqEle por instituto
  (seed `instituto_registro_tse`), período de campo (±3 dias) e amostra; o painel lista o
  registro, a empresa, a contratação e o nível de confiança de cada uma. Pesquisa sem registro
  localizado fica de fora (inclusive as de 2025, anteriores ao registro obrigatório).

- A Wikipédia não informa o ano do campo: a regra usa o ano da carga e volta um ano se a data
  cair no futuro.
- Linhas com `revisar = true` nos seeds esperam confirmação humana.
- O 1º turno só usa cenários com a lista oficial de candidatos; cenários hipotéticos ficam nos
  duelos de 2º turno, marcados na tela.
- Consumo do warehouse depende da cota diária da Free Edition do Databricks. Para poupar: as
  checagens rodam só `dbt run` do que depende da Wikipédia (testes só na carga completa) e, se a
  cota estourar, o dia fica marcado no cache do Actions e as checagens seguintes nem ligam o
  Databricks até o dia virar (UTC). O painel fica com o último dado bom. O auto stop do
  warehouse inicial (10 min) não é editável na Free Edition.
