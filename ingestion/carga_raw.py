"""
Carga bruta do projeto eleicoes2026 — executada pelo GitHub Actions.

Por que fora do Databricks: o workspace (Free Edition) bloqueia acesso de saída à
internet ("serverless network policy"), mas aceita conexões de entrada. Então este
script roda num runner com internet, baixa as fontes e grava no Databricks:

    fonte (TSE / Wikipedia)
      -> DataFrame com todas as colunas como string (sem transformação)
      -> parquet
      -> Volume  /Volumes/<catalog>/<schema>/landing/<tabela>.parquet   (Files API)
      -> tabela  <catalog>.<schema>.<tabela>                              (SQL Statement API)

Toda limpeza e regra de qualidade fica no dbt.

Variáveis de ambiente:
    DATABRICKS_HOST          ex.: dbc-xxxx.cloud.databricks.com   (obrigatória)
    DATABRICKS_TOKEN         token pessoal ou de service principal (obrigatória)
    DATABRICKS_WAREHOUSE_ID  id do SQL Warehouse (final do HTTP path) (obrigatória)
    DATABRICKS_CATALOG       padrão: workspace
    DATABRICKS_SCHEMA        padrão: raw_eleicoes
    DATABRICKS_VOLUME        padrão: landing
    FONTES                   lista separada por vírgula (padrão: todas)
                             pesquisa_eleitoral_2026,totalizacao_presidente_2022,intencao_voto_2026
    DRY_RUN                  "1" = só baixa e gera parquet em ./saida, sem gravar no Databricks
"""

from __future__ import annotations

import io
import os
import re
import sys
import time
import zipfile
from datetime import datetime, timezone
from pathlib import Path

import pandas as pd
import requests

# O CDN do TSE tem proteção anti-bot que recusa (403) o cliente `requests` pela assinatura TLS,
# mesmo com User-Agent de navegador. `curl_cffi` reproduz a conexão do Chrome e é aceito.
HEADERS = {"Accept": "*/*", "Accept-Language": "pt-BR,pt;q=0.9"}

try:
    from curl_cffi import requests as http_cliente
    _KWARGS_CLIENTE = {"impersonate": "chrome"}
except ImportError:  # fallback (Wikipedia funciona com requests puro)
    http_cliente = requests
    _KWARGS_CLIENTE = {}

URL_PESQELE = "https://cdn.tse.jus.br/estatistica/sead/odsele/pesquisa_eleitoral/pesquisa_eleitoral_2026.zip"
URL_TOTALIZACAO = "https://cdn.tse.jus.br/estatistica/sead/eleicoes/eleicoes2022/Historico_Totalizacao_Presidente_BR_{turno}_2022.zip"
URL_WIKI = "https://pt.wikipedia.org/wiki/Pesquisas_de_opini%C3%A3o_para_a_elei%C3%A7%C3%A3o_presidencial_no_Brasil_em_2026"


def log(msg: str) -> None:
    print(f"[{datetime.now(timezone.utc):%H:%M:%S}] {msg}", flush=True)


# --------------------------------------------------------------------------------------
# Extração
# --------------------------------------------------------------------------------------

def _get(url: str, timeout: int = 300, tentativas: int = 3):
    for i in range(1, tentativas + 1):
        try:
            resp = http_cliente.get(url, headers=HEADERS, timeout=timeout, **_KWARGS_CLIENTE)
            resp.raise_for_status()
            return resp
        except Exception as exc:
            if i == tentativas:
                raise
            log(f"  falha ao baixar ({exc}); nova tentativa em {10 * i}s")
            time.sleep(10 * i)
    raise RuntimeError("inalcançável")


def ler_csvs_do_zip(conteudo: bytes) -> list[tuple[str, pd.DataFrame]]:
    """Lê todos os CSVs de um zip do TSE (; e latin-1) como string, sem tratar valores."""
    saida = []
    with zipfile.ZipFile(io.BytesIO(conteudo)) as zf:
        for nome in zf.namelist():
            if not nome.lower().endswith(".csv"):
                continue
            with zf.open(nome) as f:
                df = pd.read_csv(
                    f, sep=";", encoding="latin-1", dtype=str,
                    keep_default_na=False, na_filter=False,
                )
            df.columns = [str(c).strip() for c in df.columns]
            saida.append((nome, df))
    if not saida:
        raise RuntimeError("zip sem arquivos CSV")
    return saida


def extrair_pesquisa_eleitoral_2026() -> pd.DataFrame:
    log("TSE PesqEle 2026: baixando")
    partes = []
    for nome, df in ler_csvs_do_zip(_get(URL_PESQELE).content):
        df["_arquivo_origem"] = nome
        partes.append(df)
    return pd.concat(partes, ignore_index=True)


def extrair_totalizacao_presidente_2022() -> pd.DataFrame:
    partes = []
    for turno in ("1T", "2T"):
        log(f"TSE totalização Presidente 2022 {turno}: baixando")
        for nome, df in ler_csvs_do_zip(_get(URL_TOTALIZACAO.format(turno=turno)).content):
            df["TURNO"] = turno
            df["_arquivo_origem"] = nome
            partes.append(df)
    # colunas de candidato ausentes em um turno ficam vazias
    return pd.concat(partes, ignore_index=True).fillna("")


def _achar_coluna(cols: list[str], termos: list[str]) -> str | None:
    for c in cols:
        if any(t in c.lower() for t in termos):
            return c
    return None


def normalizar_wikitables(tabelas: list[pd.DataFrame]) -> pd.DataFrame:
    """Mesma heurística do Power Query original: identifica instituto/período/amostra/margem
    pelo nome e despivota as demais colunas (1 linha por célula). Nenhuma limpeza de valor."""
    linhas = []
    for idx, t in enumerate(tabelas):
        t = t.copy()
        if isinstance(t.columns, pd.MultiIndex):
            t.columns = [
                " ".join(dict.fromkeys(str(x) for x in col if "Unnamed" not in str(x))).strip()
                for col in t.columns
            ]
        t.columns = [str(c).strip() for c in t.columns]
        t = t.loc[:, ~pd.Index(t.columns).duplicated()]

        cols = list(t.columns)
        c_inst = _achar_coluna(cols, ["instituto", "contratante", "pesquisa"])
        c_data = _achar_coluna(cols, ["data", "período", "periodo"])
        if c_inst is None or c_data is None:
            continue
        c_amos = _achar_coluna(cols, ["amostra"])
        c_marg = _achar_coluna(cols, ["margem"])
        fixas = [c for c in dict.fromkeys((c_inst, c_data, c_amos, c_marg)) if c]
        if len(fixas) == len(cols):
            continue

        longo = t.melt(id_vars=fixas, var_name="coluna_candidato", value_name="valor_texto")
        saida = pd.DataFrame({
            "tabela_idx": str(idx),
            "instituto_texto": longo[c_inst],
            "periodo_texto": longo[c_data],
            "amostra_texto": longo[c_amos] if c_amos else None,
            "margem_texto": longo[c_marg] if c_marg else None,
            "coluna_candidato": longo["coluna_candidato"],
            "valor_texto": longo["valor_texto"],
        })
        linhas.append(saida)

    if not linhas:
        raise RuntimeError("nenhuma wikitable com colunas de instituto e período encontrada")
    return pd.concat(linhas, ignore_index=True)


def extrair_intencao_voto_2026() -> pd.DataFrame:
    log("Wikipedia intenção de voto 2026: baixando")
    html = _get(URL_WIKI, timeout=120).text
    tabelas = pd.read_html(io.StringIO(html), attrs={"class": "wikitable"}, flavor="lxml")
    log(f"  {len(tabelas)} wikitables encontradas")
    return normalizar_wikitables(tabelas)


FONTES = {
    "pesquisa_eleitoral_2026": extrair_pesquisa_eleitoral_2026,
    "totalizacao_presidente_2022": extrair_totalizacao_presidente_2022,
    "intencao_voto_2026": extrair_intencao_voto_2026,
}


# --------------------------------------------------------------------------------------
# Preparação
# --------------------------------------------------------------------------------------

_INVALIDOS = re.compile(r"[ ,;{}()\n\t=]+")


def preparar(df: pd.DataFrame) -> pd.DataFrame:
    """Tudo string, nulos como vazio, nomes de coluna aceitos pelo Delta (sem espaço, vírgula etc.)."""
    df = df.copy()
    novos, vistos = [], set()
    for c in df.columns:
        nome = _INVALIDOS.sub("_", str(c).strip()).rstrip("_") or "coluna"  # preserva "_" inicial (_arquivo_origem)
        base, n = nome, 2
        while nome.upper() in vistos:
            nome = f"{base}_{n}"
            n += 1
        vistos.add(nome.upper())
        novos.append(nome)
    df.columns = novos
    return df.fillna("").astype(str)


def para_parquet(df: pd.DataFrame) -> bytes:
    """Parquet com todas as colunas como `string` (utf8) — não `large_string`, que o pandas
    recente usa por padrão e que leitores Spark mais antigos não aceitam."""
    import pyarrow as pa
    import pyarrow.parquet as pq

    schema = pa.schema([pa.field(c, pa.string()) for c in df.columns])
    tabela = pa.Table.from_pandas(df, schema=schema, preserve_index=False)
    buf = io.BytesIO()
    pq.write_table(tabela, buf, compression="snappy")
    return buf.getvalue()


# --------------------------------------------------------------------------------------
# Databricks
# --------------------------------------------------------------------------------------

class Databricks:
    def __init__(self, host: str, token: str, warehouse_id: str):
        self.base = "https://" + host.replace("https://", "").rstrip("/")
        self.warehouse_id = warehouse_id
        self.s = requests.Session()
        self.s.headers.update({"Authorization": f"Bearer {token}"})

    def upload(self, caminho_volume: str, conteudo: bytes) -> None:
        url = f"{self.base}/api/2.0/fs/files{caminho_volume}"
        r = self.s.put(url, params={"overwrite": "true"}, data=conteudo,
                       headers={"Content-Type": "application/octet-stream"}, timeout=600)
        if r.status_code >= 300:
            raise RuntimeError(f"upload falhou ({r.status_code}): {r.text[:500]}")

    def sql(self, statement: str, timeout_s: int = 900) -> dict:
        r = self.s.post(f"{self.base}/api/2.0/sql/statements", json={
            "warehouse_id": self.warehouse_id,
            "statement": statement,
            "wait_timeout": "50s",
            "on_wait_timeout": "CONTINUE",
        }, timeout=120)
        if r.status_code >= 300:
            raise RuntimeError(f"SQL falhou ({r.status_code}): {r.text[:500]}")
        resp = r.json()
        inicio = time.time()
        while resp["status"]["state"] in ("PENDING", "RUNNING"):
            if time.time() - inicio > timeout_s:
                raise TimeoutError(f"SQL excedeu {timeout_s}s: {statement[:120]}")
            time.sleep(5)
            resp = self.s.get(f"{self.base}/api/2.0/sql/statements/{resp['statement_id']}", timeout=60).json()
        if resp["status"]["state"] != "SUCCEEDED":
            erro = resp["status"].get("error", {}).get("message", resp["status"])
            raise RuntimeError(f"SQL {resp['status']['state']}: {erro}\n{statement[:300]}")
        return resp


def gravar_tabela(db: Databricks, catalog: str, schema: str, volume: str, tabela: str, parquet: bytes) -> int:
    caminho = f"/Volumes/{catalog}/{schema}/{volume}/{tabela}.parquet"
    log(f"  enviando {len(parquet) / 1e6:.1f} MB para {caminho}")
    db.upload(caminho, parquet)
    log(f"  criando {catalog}.{schema}.{tabela}")
    db.sql(f"""
        CREATE OR REPLACE TABLE `{catalog}`.`{schema}`.`{tabela}`
        COMMENT 'Carga bruta via GitHub Actions (ingestion/carga_raw.py). Não editar manualmente.'
        AS SELECT * EXCEPT (_rescued_data), current_timestamp() AS _ingerido_em
        FROM read_files('{caminho}', format => 'parquet')
    """)
    resp = db.sql(f"SELECT count(*) FROM `{catalog}`.`{schema}`.`{tabela}`")
    return int(resp["result"]["data_array"][0][0])


# --------------------------------------------------------------------------------------

def main() -> int:
    catalog = os.getenv("DATABRICKS_CATALOG", "workspace")
    schema = os.getenv("DATABRICKS_SCHEMA", "raw_eleicoes")
    volume = os.getenv("DATABRICKS_VOLUME", "landing")
    dry_run = os.getenv("DRY_RUN") == "1"
    selecionadas = [f.strip() for f in os.getenv("FONTES", ",".join(FONTES)).split(",") if f.strip()]

    desconhecidas = set(selecionadas) - set(FONTES)
    if desconhecidas:
        log(f"fontes desconhecidas: {sorted(desconhecidas)}")
        return 2

    db = None
    if not dry_run:
        faltando = [v for v in ("DATABRICKS_HOST", "DATABRICKS_TOKEN", "DATABRICKS_WAREHOUSE_ID") if not os.getenv(v)]
        if faltando:
            log(f"variáveis obrigatórias ausentes: {faltando}")
            return 2
        db = Databricks(os.environ["DATABRICKS_HOST"], os.environ["DATABRICKS_TOKEN"], os.environ["DATABRICKS_WAREHOUSE_ID"])
        db.sql(f"CREATE SCHEMA IF NOT EXISTS `{catalog}`.`{schema}`")
        db.sql(f"CREATE VOLUME IF NOT EXISTS `{catalog}`.`{schema}`.`{volume}`")

    falhas = []
    for tabela in selecionadas:
        try:
            df = preparar(FONTES[tabela]())
            log(f"  {tabela}: {len(df):,} linhas x {len(df.columns)} colunas")
            if df.empty:
                raise RuntimeError("extração retornou 0 linhas")
            parquet = para_parquet(df)
            if dry_run:
                Path("saida").mkdir(exist_ok=True)
                Path(f"saida/{tabela}.parquet").write_bytes(parquet)
                log(f"  DRY_RUN: saida/{tabela}.parquet")
            else:
                n = gravar_tabela(db, catalog, schema, volume, tabela, parquet)
                log(f"  OK: {n:,} linhas em {catalog}.{schema}.{tabela}")
        except Exception as exc:  # uma fonte com problema não impede as outras
            log(f"  ERRO em {tabela}: {exc}")
            falhas.append(tabela)

    if falhas:
        log(f"concluído com falhas: {falhas}")
        return 1
    log("concluído sem falhas")
    return 0


if __name__ == "__main__":
    sys.exit(main())
