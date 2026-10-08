# Curso: refazendo o eleicoes2026 do zero

Dossiê do projeto para estudo. Junta o que está no código com o que só existiu nas conversas de
desenvolvimento: configurações feitas em consoles, onde fica cada chave, decisões e problemas
reais com suas causas. Estado de 08/10/2026.

> Nenhum valor de token, senha ou chave aparece aqui. Só o **nome** de cada um e **onde** ele é
> configurado. Quem cria e cola os valores é sempre você, no console de cada serviço.

---

## 0. Visão geral em uma frase

Python no GitHub Actions baixa as fontes (TSE e Wikipédia) e grava cru no Databricks (bronze);
o dbt transforma em views e tabelas limpas e testadas (prata e ouro); o `site/gerar.py` lê os
modelos `painel_*` e publica um HTML estático no GitHub Pages; uma tarefa agendada do Claude
copia os mesmos dados para um artifact no claude.ai.

```
TSE / Wikipédia ──► carga_raw.py (Actions) ──► Volume landing + raw_eleicoes (Databricks, bronze)
                                                   │ dbt (SQL executado no SQL warehouse)
                                                   ▼
                         staging / intermediate (prata) ──► marts + painel_* (ouro)
                                                   │
                         gerar.py (Actions) ──► docs/index.html ──► GitHub Pages
                         tarefa do Claude ──► artifact claude.ai (copia do site)
```

Endereços: repositório `github.com/pedro-parreiracruz/eleicoes2026`; site
`pedro-parreiracruz.github.io/eleicoes2026`; página explicativa da arquitetura publicada como
artifact ("Arquitetura do eleicoes2026").

---

## 1. Contas, chaves e configurações (tudo que não está no código)

### 1.1 GitHub

- Repositório público `eleicoes2026`.
- **Settings → Environments → `producao`**: o environment que guarda as credenciais usadas pelos
  jobs que falam com o Databricks.
  - Secret `DATABRICKS_TOKEN` — token pessoal do Databricks (começa com `dapi`).
  - Variable `DATABRICKS_HOST` — `dbc-xxxxxxxx-xxxx.cloud.databricks.com` (sem `https://`).
  - Variable `DATABRICKS_WAREHOUSE_ID` — id do SQL warehouse (`76f19a62eddd3ef2`).
  - Opcionais: `DATABRICKS_CATALOG` (padrão `workspace`), `DATABRICKS_SCHEMA` (padrão
    `raw_eleicoes`), `CONTADOR_URL` (contador de acessos), `PAINEL_FONTE` (`consulta` = rollback).
- **Settings → Pages**: fonte "Deploy from a branch", branch `main`, pasta `/docs`.
- **Settings → Actions → General**: permissões de workflow com leitura e escrita (os workflows
  fazem commit de `docs/index.html` e `site/propostas_tse.json`). Cada workflow declara as
  próprias `permissions:` (`contents: write`, e no de propostas também `issues` e `actions`).
- Ids dos workflows usados para disparar pela CLI: carga `360598444`, publicar `363318307`.

**Conceito:** secret é cifrado e nunca aparece no log; variable é texto visível. Token vai em
secret, endereço vai em variable. O environment permite exigir aprovação e separar credenciais
de produção.

### 1.2 Databricks Free Edition

- Conta gratuita; workspace com catálogo `workspace` (Unity Catalog).
- **SQL Warehouses → "Serverless Starter Warehouse"**, tamanho 2X-Small, auto stop 10 min
  (na Free Edition não dá para editar o auto stop).
  - O id do warehouse aparece na página dele e no "HTTP path" (`/sql/1.0/warehouses/<id>`), em
    Connection details.
- **Token:** User Settings → Developer → Access tokens → Generate new token. Copie uma vez e
  cole direto no secret do GitHub e no dbt Platform. Nunca em chat, código ou arquivo.
- Schemas criados pelo projeto: `raw_eleicoes` (com o volume `landing`), `staging`,
  `intermediate`, `marts`, `seeds`, `snapshots`, `dq_falhas`. O `raw_eleicoes` e o volume são
  criados pelo próprio `carga_raw.py` (`CREATE SCHEMA/VOLUME IF NOT EXISTS`); os outros, pelo dbt.
- **Limites da Free Edition que moldaram o projeto:**
  - sem acesso à internet de saída a partir do Databricks (testado em 17/09/2026) → a extração
    roda fora, no GitHub Actions;
  - cota diária de computação → checagens mais espaçadas, testes só na carga diária;
  - warehouse parado que às vezes não liga sozinho ("Cannot create the resource") → script
    `ligar_warehouse.py`.

### 1.3 dbt

- **dbt Core** (produção): instalado no próprio job do Actions
  (`dbt-core>=1.12,<1.13` e `dbt-databricks>=1.12,<1.13`). Usa `ci/profiles.yml`, que lê host,
  http_path e token de variáveis de ambiente — nenhum segredo no arquivo.
- Para rodar local: copiar `profiles.yml.exemplo` para `~/.dbt/profiles.yml` e preencher.
- **dbt Platform** (nuvem): projeto id `70506183167046`, conectado ao mesmo warehouse com o token
  do Databricks. Serve para explorar o projeto e para o Claude consultar o Databricks (MCP). Não
  roda a carga. O ambiente de produção está como "Latest"; um job criado lá falhou na compilação
  em versão Fusion e foi abandonado.
- Macro `generate_schema_name`: em produção usa o schema configurado (`staging`, `marts`...);
  em desenvolvimento prefixa com o schema do usuário.

### 1.4 GitHub CLI no computador

- Login feito com device flow (`gh auth login`, código mostrado na tela e confirmado em
  github.com/login/device), escopos `repo`, `workflow`, `read:org`, `gist`.
- Git configurado com `user.name "Pedro Parreira"` e o e-mail noreply do GitHub.

### 1.5 Claude

- **Tarefa agendada "refresh corrida presidencial 2026"** — todo dia 17:08 UTC (14:08 de
  Brasília). Desde 05/10 copia os dados do `docs/index.html` do repositório (não consulta mais o
  Databricks), atualiza o contador de acessos e o aviso dos planos de governo, valida a página
  num navegador headless e publica o artifact.
- **Artifact "Corrida Presidencial 2026"** — a mesma página do site, hospedada no claude.ai.
  Tem três blocos marcados que a tarefa substitui: `DADOS`, `CONTADOR` e a linha `PROP_TSE`.

---

## 2. Roteiro de módulos

Cada módulo: conceito → micro-ações → arquivos do repositório → exercício.

### Módulo 1 — Fontes e contrato dos dados
- TSE PesqEle 2026: `cdn.tse.jus.br/.../pesquisa_eleitoral_2026.zip`, CSVs `;`, latin-1, um por
  UF. Colunas como `NR_PROTOCOLO_REGISTRO`, `DT_INICIO_PESQUISA`, `QT_ENTREVISTADO`,
  `DS_PLANO_AMOSTRAL`. Sentinela `#NULO#`.
- TSE totalização 2022 (1º e 2º turno): zip com CSV.
- Wikipédia: página de pesquisas da eleição presidencial 2026; tabelas HTML com notas de rodapé
  coladas nos nomes (`Quaest[17]`), "<1" e decimais com vírgula.
- DivulgaCandContas (TSE): API JSON `/divulga/rest/v1/candidatura/listar/2026/BR/20322002026/1/candidatos`
  e `/buscar/.../candidato/<id>`; arquivos do tipo `codTipo = 5` são o plano de governo (PDF em
  `/divulga/rest/arquivo/doc/<id>`).
- O CDN do TSE tem anti-bot que recusa o `requests` → `curl_cffi` com assinatura de Chrome.

### Módulo 2 — Extração e bronze (`ingestion/carga_raw.py`)
- Baixa, lê tudo como texto (`dtype=str`) para não perder nada, grava parquet (pyarrow, snappy).
- Sobe o parquet para `/Volumes/workspace/raw_eleicoes/landing/` pela Files API
  (`PUT /api/2.0/fs/files`).
- Cria a tabela Delta com `CREATE OR REPLACE TABLE ... AS SELECT *, current_timestamp() AS
  _ingerido_em FROM parquet.\`<caminho>\`` pela Statement Execution API.
- `DRY_RUN=1` gera só os parquets em `saida/`.
- **Conceito:** bronze não corrige nada; se a limpeza errar, refaz-se a partir dela sem baixar de novo.

### Módulo 3 — dbt: projeto, sources, staging (prata)
- `dbt_project.yml`: staging e intermediate como `view`, marts como `table`; schemas por pasta.
- Sources em `models/staging/tse/_tse__sources.yml` e `models/staging/wikipedia/_wikipedia__sources.yml`.
- Staging: tipagem, datas, decimais brasileiros (`br_decimal`), sentinelas (`tse_texto`), remoção
  de notas (`sem_notas`).
- **Armadilha real (21/09):** o Databricks processa escapes em literais; regex precisa de barra
  dobrada (`'\\['`). Com barra simples, "Quaest[17]" virou "]" e o painel perdeu os nomes.

### Módulo 4 — Intermediate, seeds e snapshot (prata)
- `int_pesquisas__classificadas`, `int_intencao_voto__padronizada`: regras, flags de qualidade,
  chaves por hash.
- Seeds: `de_para_instituto`, `de_para_candidato`, `candidatos_registrados`,
  `instituto_registro_tse`. Linhas com `revisar = true` esperam confirmação humana.
- Snapshot `snp_tse__pesquisas_eleitorais`: histórico de mudanças nos registros do TSE.

### Módulo 5 — Marts e modelos do painel (ouro)
- `fct_pesquisas_registradas`, `fct_intencao_voto`, `fct_resultado_oficial_2022`,
  `dim_instituto`, `dim_calendario`.
- `painel_registro_tse`: casa cada pesquisa da Wikipédia com o registro no TSE por instituto
  (seed com palavra-chave), datas de campo (±3 dias) e amostra; exclui registros nacionais que
  espelham pesquisa estadual; extrai nível de confiança do plano amostral por regex.
- `painel_votos_todos` → `painel_votos` (inner join com o registro: sem registro, fora do painel).
- `painel_1t_pesquisas`, `painel_1t_valores`, `painel_2t_duelos`, `painel_institutos`,
  `painel_institutos_mes`, `painel_metadados`: cada um gera uma coluna `linha` (texto exato que vai
  para o HTML, campos separados por `;`) e `nr_ordem`.
- **Formatos das linhas:**
  - P1T: data;instituto;amostra;margem;registro(s);confiança;contratação P/C;empresa;início
  - V1T: data;instituto;nome|partido;valor;C|N
  - D2T: data;instituto;frente;%;atrás;%;margem;%indecisos;registro;confiança;P/C;empresa;amostra;início
- Campos vazios usam `coalesce(..., '')`: `concat_ws` pula nulos e deslocaria os campos.
- `painel_metadados` tira as datas do cabeçalho dos próprios blocos (correção de 29/09, quando um
  cenário fora do painel virou "pesquisa mais recente").

### Módulo 6 — Testes e qualidade
- Testes genéricos nos `.yml` e singulares em `tests/` (soma de cenário perto de 100%, instituto
  preenchido, alertas do TSE, resultado 2022 somando 100).
- Severidade `warn` + `store_failures`: o build não para, e as linhas reprovadas ficam em `dq_falhas`.

### Módulo 7 — Orquestração com GitHub Actions
- `carga_eleicoes.yml`:
  - cron `17 8 * * *` (05:17 de Brasília) = carga completa: TSE + Wikipédia + `dbt build` + publicar;
  - cron `7 9-21/3 * * *` = checagem: `verificar_wikipedia.py` calcula uma impressão digital da
    tabela; o cache do Actions (`wiki-<hash>`) diz se já foi carregada; só se mudou carrega e roda
    `dbt run --select stg_wikipedia__intencao_voto_2026+` (sem testes);
  - `workflow_dispatch` com entradas `rodar_tse`, `rodar_wikipedia`, `rodar_dbt`;
  - marca de cota esgotada no cache (`cota-esgotada-<dia UTC>`) para as checagens não insistirem;
  - `defaults.run.shell: bash` para ter `pipefail` (senão `comando | tee` esconde falhas);
  - todo job que usa o Databricks começa por `ingestion/ligar_warehouse.py`.
- `publicar_site.yml`: roda `site/gerar.py`, faz commit de `docs/index.html`; entrada `fonte`
  (`dbt` ou `consulta` para rollback).
- `verificar_propostas.yml`: cron `37 9-21/3 * * *`, sem Databricks; ver módulo 9.
- **Realidade:** o GitHub atrasa crons em horários cheios; a carga das 05:17 chegou a rodar perto
  das 11h.

### Módulo 8 — O painel (`site/modelo.html` + `site/gerar.py`)
- `modelo.html` é HTML, CSS e JavaScript puros, gráficos em SVG desenhados à mão, sem biblioteca.
  Marcadores (`__P1T__`, `__V1T__`, `__CARGA__`...) que o `gerar.py` substitui.
- `gerar.py`: consulta `painel_*` (`CONSULTA_DBT`) ou a consulta antiga (`CONSULTA_LEGADA`, rollback
  automático se os modelos falharem); confere blocos (instituto vazio, markup, crases); confere as
  datas do cabeçalho contra os blocos; injeta `propostas_tse.json`.
- Regras de cálculo na página: cada pesquisa reescalada para somar 100%; média do dia com
  candidato ausente contando zero; média móvel de 5 pontos com mais de 14 dias; tooltip
  arredondado pelo maior resto para fechar 100,0%.
- Capa com foto, links e animação; abas 1º turno, 2º turno, Institutos, Propostas.
- Lista "Registro no TSE de cada pesquisa usada", aviso legal e fonte colada em cada gráfico.

### Módulo 9 — Planos de governo
- Resumos (constante `PROP` em `modelo.html`) escritos por gente a partir do PDF; nunca inventados.
- `ingestion/verificar_propostas.py` compara o id do PDF lido com o tipo 5 atual no TSE, grava
  `site/propostas_tse.json`, abre issue e republica; a página mostra "nova versão no TSE, resumo
  em revisão" com link.
- Caso real: em 01/10 a Samara (UP) trocou o programa de 1 para 67 páginas.

### Módulo 10 — Questões legais (pesquisa eleitoral)
- Lei 9.504/97 art. 33: só divulgar pesquisa registrada; multa também para quem republica.
- Informações exibidas por pesquisa: registro (formato BR-00000/2026), empresa, contratação,
  período de campo, amostra, margem, nível de confiança. Contratante não está nos dados abertos.
- Proposta pendente (não implementada): tabela de pesquisas suspensas pela Justiça Eleitoral,
  excluídas do cálculo e listadas sem números.
- Recomendação: validar com advogado eleitoral.

---

## 3. Linha do tempo de problemas e soluções

| Data | Problema | Causa | Solução |
|---|---|---|---|
| 17/09 | Download falhava dentro do Databricks | Free Edition sem internet de saída | Extração no GitHub Actions |
| 21/09 | Institutos sem nome no painel | Regex com barra simples no Databricks | Barras dobradas + teste `assert_painel_instituto_preenchido` |
| 25/09 | Cargas falhando à tarde | Cota diária da Free Edition | Checagens a cada 3 h, dbt só da Wikipédia, testes só na carga diária |
| 27/09 | Risco legal de pesquisa sem registro | Wikipédia não traz registro | `painel_registro_tse` + inner join |
| 27/09 | Soma ≠ 100% nas linhas | Institutos arredondam; ausentes na média | Reescala por pesquisa, ausente = 0, arredondamento pelo maior resto |
| 29/09 | "Pesquisa mais recente" sem pesquisa na tela | Datas vinham de `painel_votos` | Datas tiradas dos blocos (modelo + `gerar.py`) |
| 01–05/10 | Painel 4 dias desatualizado | Warehouse parado não ligava sozinho | `ligar_warehouse.py` antes de cada job; tarefa do Claude copia do site |
| 05/10 | Chip "1º turno em 04/10" depois da eleição | Data fixa | Contagem para o 2º turno |

---

## 4. Para refazer do zero (ordem sugerida)

1. Criar contas: GitHub, Databricks Free Edition, dbt Platform (opcional).
2. Repositório vazio; Python 3.12; `ingestion/requirements.txt`.
3. Escrever e testar `carga_raw.py` com `DRY_RUN=1`.
4. Gerar o token no Databricks e configurar o environment `producao` no GitHub.
5. Rodar a carga real manualmente; conferir as tabelas em `raw_eleicoes`.
6. `dbt init`, profile, sources, staging; `dbt build` local.
7. Intermediate, seeds, snapshot, marts, testes.
8. Modelos `painel_*` e `gerar.py`; gerar `docs/index.html` local.
9. Ativar GitHub Pages.
10. Workflows: carga, publicar, checagem, planos.
11. Automação no Claude (opcional).

Exercício final: mudar a regra de casamento com o TSE (por exemplo, tolerância de 2 dias),
medir quantas pesquisas saem e explicar o impacto no painel.
