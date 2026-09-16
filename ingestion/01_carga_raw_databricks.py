# Databricks notebook source
# MAGIC %md
# MAGIC # Carga raw - eleicoes2026
# MAGIC Extract/Load das 3 fontes usadas no Power BI "pesquisas eleitorais", **sem transformacao**
# MAGIC (tudo como string). A limpeza e as regras de qualidade ficam no projeto dbt.
# MAGIC
# MAGIC | Tabela raw | Origem |
# MAGIC |---|---|
# MAGIC | `raw_eleicoes.pesquisa_eleitoral_2026` | TSE PesqEle (zip com CSVs) |
# MAGIC | `raw_eleicoes.totalizacao_presidente_2022` | TSE historico de totalizacao 1T/2T |
# MAGIC | `raw_eleicoes.intencao_voto_2026` | Wikipedia (wikitables despivotadas) |
# MAGIC
# MAGIC Agende este notebook como tarefa anterior ao job `dbt build` (Databricks Workflows ou dbt Platform).

# COMMAND ----------

dbutils.widgets.text("catalog", "main")
dbutils.widgets.text("schema", "raw_eleicoes")
CATALOG = dbutils.widgets.get("catalog")
SCHEMA = dbutils.widgets.get("schema")

spark.sql(f"CREATE SCHEMA IF NOT EXISTS {CATALOG}.{SCHEMA}")

# COMMAND ----------

import io
import zipfile
from datetime import datetime, timezone

import pandas as pd
import requests
from pyspark.sql import functions as F

INGERIDO_EM = datetime.now(timezone.utc)
HEADERS = {"User-Agent": "eleicoes2026-dbt/1.0 (dados abertos)"}


def baixar_zip_csvs(url: str) -> list[tuple[str, pd.DataFrame]]:
    """Baixa um zip do TSE e devolve [(nome_arquivo, DataFrame string)] de cada CSV."""
    resp = requests.get(url, headers=HEADERS, timeout=300)
    resp.raise_for_status()
    saida = []
    with zipfile.ZipFile(io.BytesIO(resp.content)) as zf:
        for nome in zf.namelist():
            if nome.lower().endswith(".csv"):
                with zf.open(nome) as f:
                    df = pd.read_csv(f, sep=";", encoding="latin-1", dtype=str, keep_default_na=False)
                df.columns = [c.strip() for c in df.columns]
                saida.append((nome, df))
    return saida


def gravar(pdf: pd.DataFrame, tabela: str) -> None:
    sdf = spark.createDataFrame(pdf.fillna("").astype(str)).withColumn("_ingerido_em", F.lit(INGERIDO_EM).cast("timestamp"))
    (sdf.write.mode("overwrite").option("overwriteSchema", "true").saveAsTable(f"{CATALOG}.{SCHEMA}.{tabela}"))
    print(f"{tabela}: {sdf.count():,} linhas")

# COMMAND ----------

# MAGIC %md ## 1. TSE - PesqEle 2026

# COMMAND ----------

URL_PESQELE = "https://cdn.tse.jus.br/estatistica/sead/odsele/pesquisa_eleitoral/pesquisa_eleitoral_2026.zip"

partes = []
for nome, df in baixar_zip_csvs(URL_PESQELE):
    df["_arquivo_origem"] = nome
    partes.append(df)
gravar(pd.concat(partes, ignore_index=True), "pesquisa_eleitoral_2026")

# COMMAND ----------

# MAGIC %md ## 2. TSE - Historico de totalizacao Presidente 2022

# COMMAND ----------

URL_TOT = "https://cdn.tse.jus.br/estatistica/sead/eleicoes/eleicoes2022/Historico_Totalizacao_Presidente_BR_{turno}_2022.zip"

partes = []
for turno in ("1T", "2T"):
    for nome, df in baixar_zip_csvs(URL_TOT.format(turno=turno)):
        df["TURNO"] = turno
        df["_arquivo_origem"] = nome
        partes.append(df)
# concat alinha colunas por nome: candidatos que so existem no 1T ficam vazios no 2T
gravar(pd.concat(partes, ignore_index=True).fillna(""), "totalizacao_presidente_2022")

# COMMAND ----------

# MAGIC %md ## 3. Wikipedia - intencao de voto 2026
# MAGIC Replica a heuristica do Power Query: identifica colunas de instituto/periodo/amostra/margem
# MAGIC pelo nome e despivota as demais (uma linha por celula). Nenhuma limpeza de valor aqui.

# COMMAND ----------

URL_WIKI = "https://pt.wikipedia.org/wiki/Pesquisas_de_opini%C3%A3o_para_a_elei%C3%A7%C3%A3o_presidencial_no_Brasil_em_2026"

html = requests.get(URL_WIKI, headers=HEADERS, timeout=120).text
tabelas = pd.read_html(io.StringIO(html), attrs={"class": "wikitable"}, flavor="lxml")


def achar_coluna(cols, termos):
    for c in cols:
        if any(t in c.lower() for t in termos):
            return c
    return None


linhas = []
for idx, t in enumerate(tabelas):
    # cabecalhos com 2 niveis (MultiIndex) viram "nivel1 nivel2" sem repeticao
    if isinstance(t.columns, pd.MultiIndex):
        t.columns = [" ".join(dict.fromkeys(str(x) for x in col if "Unnamed" not in str(x))).strip() for col in t.columns]
    t.columns = [str(c).strip() for c in t.columns]
    t = t.loc[:, ~pd.Index(t.columns).duplicated()]

    c_inst = achar_coluna(t.columns, ["instituto", "contratante", "pesquisa"])
    c_data = achar_coluna(t.columns, ["data", "período", "periodo"])
    if c_inst is None or c_data is None:
        continue
    c_amos = achar_coluna(t.columns, ["amostra"])
    c_marg = achar_coluna(t.columns, ["margem"])
    fixas = [c for c in (c_inst, c_data, c_amos, c_marg) if c]

    longo = t.melt(id_vars=fixas, var_name="coluna_candidato", value_name="valor_texto")
    longo = longo.rename(columns={c_inst: "instituto_texto", c_data: "periodo_texto"})
    longo["amostra_texto"] = longo.pop(c_amos) if c_amos else None
    longo["margem_texto"] = longo.pop(c_marg) if c_marg else None
    longo["tabela_idx"] = str(idx)
    linhas.append(longo[["tabela_idx", "instituto_texto", "periodo_texto", "amostra_texto",
                         "margem_texto", "coluna_candidato", "valor_texto"]])

gravar(pd.concat(linhas, ignore_index=True).fillna(""), "intencao_voto_2026")
