#!/usr/bin/env python3
"""Monta o painel publico (docs/index.html) a partir do warehouse.

Roda no GitHub Actions logo depois da carga diaria (.github/workflows/publicar_site.yml)
e tambem na mao:

    export DATABRICKS_HOST=adb-xxxx.azuredatabricks.net
    export DATABRICKS_WAREHOUSE_ID=abc123
    export DATABRICKS_TOKEN=dapi...
    export CONTADOR_URL=https://contador.seu-dominio.workers.dev
    python site/gerar.py --saida docs/index.html

Sem credito no Databricks da para gerar a pagina a partir de um despejo local
dos mesmos blocos (util para testar layout sem gastar warehouse):

    python site/gerar.py --dados caminho/para/dados --saida /tmp/index.html

O modelo (site/modelo.html) e o mesmo arquivo publicado no artifact do Claude;
a unica diferenca e que aqui os marcadores __XXX__ sao preenchidos por este
script em vez de pela tarefa agendada.
"""

import argparse
import json
import os
import pathlib
import re
import sys
from datetime import datetime, timezone

RAIZ = pathlib.Path(__file__).resolve().parent
MODELO = RAIZ / "modelo.html"

# Uma consulta so devolve as nove pecas do bloco DADOS. As cinco ultimas voltam
# como uma celula de texto com varias linhas (separador ";", decimal ".").
#
# O CTE "inst" existe porque a Wikipedia escreve o mesmo instituto de varias
# formas ("Datafolha"/"DataFolha", "Futura/Apex"/"Apex/Futura") e as vezes cola
# uma citacao <ref> dentro do nome. Ele limpa o markup e faz a grafia mais usada
# vencer. Nao remova mesmo que o dado pareca limpo: e o que impede o filtro de
# instituto de fatiar a media em varias grafias do mesmo instituto.
CONSULTA = r"""
with inst as (
  select nm_instituto, first_value(limpo) over (partition by chave order by qt desc, limpo) as nm_canon
  from (
    select nm_instituto, limpo, qt,
           array_join(array_sort(filter(split(lower(regexp_replace(limpo, '[^A-Za-z0-9À-ÿ]', ' ')), ' +'), x -> x <> '')), '|') as chave
    from (
      select nm_instituto,
             trim(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(
               nm_instituto, '(?i)<?ref[ \t]+name[ \t]*=.*$', ''), '(?i)<ref[^>]*>.*$', ''),
               '<[^>]*>', ''), '\[[^\]]*\]', ''), ' +', ' ')) as limpo,
             count(*) as qt
      from workspace.marts.fct_intencao_voto group by 1, 2
    )
  )
),
f as (
  select v.*, i.nm_canon as inst_ok
  from workspace.marts.fct_intencao_voto v join inst i using (nm_instituto)
),
c as (select id_cenario, count(case when tp_resposta='Candidato' then 1 end) as n from f group by 1),
duelo as (
  select date_format(f.dt_fim_campo,'yyyy-MM-dd') as d, f.inst_ok, max(f.pc_margem_erro) as margem,
         max(struct(cast(f.pc_intencao_voto as double) as v, f.nm_candidato as nm)) as hi,
         min(struct(cast(f.pc_intencao_voto as double) as v, f.nm_candidato as nm)) as lo
  from f join c using (id_cenario)
  where c.n = 2 and f.tp_resposta='Candidato' and f.dt_fim_campo is not null
  group by f.id_cenario, date_format(f.dt_fim_campo,'yyyy-MM-dd'), f.inst_ok
),
cad as (
  select datediff(dt_inicio_campo, lag(dt_inicio_campo) over (order by dt_inicio_campo)) as dias
  from (select distinct dt_inicio_campo from workspace.marts.fct_intencao_voto
        where dt_inicio_campo >= date_sub(current_date(), 120))
),
topi as (select nm_instituto from workspace.marts.fct_pesquisas_registradas group by 1 order by count(*) desc limit 12)
select
  date_format((select max(_ingerido_em) from workspace.marts.fct_intencao_voto), "yyyy-MM-dd'T'HH:mm:ss'Z'") as carga_utc,
  date_format((select max(dt_fim_campo) from workspace.marts.fct_intencao_voto), 'yyyy-MM-dd') as campo_recente,
  date_format((select max(dt_inicio_campo) from workspace.marts.fct_intencao_voto), 'yyyy-MM-dd') as campo_inicio,
  cast(greatest(1, coalesce((select percentile_approx(dias, 0.5) from cad where dias > 0), 7)) as string) as cadencia,
  (select array_join(collect_list(l), '\n') from (
     select concat_ws(';', date_format(f.dt_fim_campo,'yyyy-MM-dd'), f.inst_ok,
              cast(max(f.qt_amostra) as string), cast(max(f.pc_margem_erro) as string)) as l
     from f join c using (id_cenario)
     where c.n >= 7 and f.dt_fim_campo is not null
     group by date_format(f.dt_fim_campo,'yyyy-MM-dd'), f.inst_ok order by 1)) as b_p1t,
  (select array_join(collect_list(l), '\n') from (
     select concat_ws(';', date_format(f.dt_fim_campo,'yyyy-MM-dd'), f.inst_ok,
              concat(f.nm_candidato, '|', coalesce(f.sg_partido,'?')),
              cast(round(avg(cast(f.pc_intencao_voto as double)),2) as string)) as l
     from f join c using (id_cenario)
     where c.n >= 7 and f.tp_resposta='Candidato' and f.dt_fim_campo is not null
     group by date_format(f.dt_fim_campo,'yyyy-MM-dd'), f.inst_ok, f.nm_candidato, coalesce(f.sg_partido,'?')
     order by 1)) as b_v1t,
  (select array_join(collect_list(l), '\n') from (
     select concat_ws(';', d, inst_ok, hi.nm, cast(hi.v as string), lo.nm, cast(lo.v as string), cast(margem as string)) as l
     from duelo order by d, inst_ok, hi.nm)) as b_d2t,
  (select array_join(collect_list(l), '\n') from (
     select concat_ws(';', nm_instituto, cast(count(*) as string), cast(round(sum(vr_pesquisa),2) as string),
              cast(sum(qt_entrevistados) as string),
              cast(count(case when ds_cargo = 'Presidente' then 1 end) as string),
              cast(count(case when tp_contratacao = 'Própria' then 1 end) as string),
              cast(count(case when fl_dq_possui_alerta then 1 end) as string),
              date_format(min(dt_registro),'yyyy-MM-dd'),
              date_format(max(dt_registro),'yyyy-MM-dd')) as l
     from workspace.marts.fct_pesquisas_registradas
     group by nm_instituto order by count(*) desc)) as b_inst,
  (select array_join(collect_list(l), '\n') from (
     select concat_ws(';', date_format(p.dt_registro,'yyyy-MM'),
              case when t.nm_instituto is null then 'Outros' else p.nm_instituto end,
              cast(count(*) as string), cast(round(sum(p.vr_pesquisa),2) as string))  as l
     from workspace.marts.fct_pesquisas_registradas p
     left join topi t using (nm_instituto)
     group by date_format(p.dt_registro,'yyyy-MM'),
              case when t.nm_instituto is null then 'Outros' else p.nm_instituto end
     order by 1)) as b_instmes
"""

# marcador no modelo -> chave devolvida pela consulta
CAMPOS = {
    "__CARGA__": "carga_utc",
    "__CAMPO__": "campo_recente",
    "__CAMPO_INI__": "campo_inicio",
    "__CADENCIA__": "cadencia",
    "__P1T__": "b_p1t",
    "__V1T__": "b_v1t",
    "__D2T__": "b_d2t",
    "__INST__": "b_inst",
    "__INSTMES__": "b_instmes",
}
# os cinco blocos grandes entram no HTML como template literal (crase)
BLOCOS = ["b_p1t", "b_v1t", "b_d2t", "b_inst", "b_instmes"]
# despejo local: nome do arquivo por bloco, para o modo --dados
ARQUIVOS = {
    "b_p1t": "PESQUISAS1T.txt",
    "b_v1t": "VALORES1T.txt",
    "b_d2t": "DUELOS2T.txt",
    "b_inst": "INSTITUTOS.txt",
    "b_instmes": "INSTITUTOSMES.txt",
}

CABECA = """<!doctype html>
<html lang="pt-BR">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="description" content="Intenção de voto para a Presidência em 2026: 1º turno, duelos de 2º turno, mercado de pesquisas e propostas de governo.">
<meta name="color-scheme" content="light dark">
<meta property="og:title" content="Corrida Presidencial 2026">
<meta property="og:description" content="Pesquisas de intenção de voto e planos de governo, direto das fontes oficiais.">
<meta property="og:type" content="website">
"""


def do_warehouse():
    """Roda a consulta no Databricks e devolve as nove pecas."""
    try:
        from databricks import sql
    except ImportError:
        sys.exit("falta a dependencia: pip install databricks-sql-connector")

    host = os.environ.get("DATABRICKS_HOST", "").replace("https://", "").strip("/")
    warehouse = os.environ.get("DATABRICKS_WAREHOUSE_ID", "").strip()
    token = os.environ.get("DATABRICKS_TOKEN", "").strip()
    faltando = [n for n, v in (("DATABRICKS_HOST", host),
                               ("DATABRICKS_WAREHOUSE_ID", warehouse),
                               ("DATABRICKS_TOKEN", token)) if not v]
    if faltando:
        sys.exit("variaveis de ambiente faltando: " + ", ".join(faltando))

    with sql.connect(server_hostname=host,
                     http_path=f"/sql/1.0/warehouses/{warehouse}",
                     access_token=token) as con:
        with con.cursor() as cur:
            cur.execute(CONSULTA)
            colunas = [d[0] for d in cur.description]
            linha = cur.fetchone()
    if linha is None:
        sys.exit("a consulta nao devolveu linha nenhuma")
    return dict(zip(colunas, linha))


def do_despejo(pasta):
    """Le os mesmos blocos de arquivos .txt ja salvos (modo offline)."""
    pasta = pathlib.Path(pasta)
    dados = {}
    for chave, arq in ARQUIVOS.items():
        caminho = pasta / arq
        if not caminho.exists():
            sys.exit(f"nao achei {caminho}")
        dados[chave] = caminho.read_text(encoding="utf-8").strip()

    # opcional: META.json com carga_utc / campo_recente / campo_inicio / cadencia
    info = pasta / "META.json"
    meta = json.loads(info.read_text(encoding="utf-8")) if info.exists() else {}
    if not isinstance(meta, dict):
        meta = {}
    # datas: o que estiver no INFO.json manda; senao deduz dos proprios blocos
    datas = sorted({l.split(";")[0] for l in dados["b_p1t"].splitlines() if l})
    dados["carga_utc"] = meta.get("carga_utc") or datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    dados["campo_recente"] = meta.get("campo_recente") or (datas[-1] if datas else "")
    dados["campo_inicio"] = meta.get("campo_inicio") or dados["campo_recente"]
    dados["cadencia"] = str(meta.get("cadencia") or 7)
    return dados


def conferir(dados):
    """Barra qualquer coisa que quebraria o HTML ou a pagina."""
    for chave in BLOCOS:
        texto = dados.get(chave) or ""
        if not texto.strip():
            sys.exit(f"o bloco {chave} veio vazio — a carga provavelmente nao rodou")
        if "`" in texto or "${" in texto:
            sys.exit(f"o bloco {chave} tem crase ou ${{ e quebraria o template literal")
    for chave in ("carga_utc", "campo_recente", "campo_inicio"):
        if not re.match(r"^\d{4}-\d{2}-\d{2}", str(dados.get(chave) or "")):
            sys.exit(f"{chave} nao parece data: {dados.get(chave)!r}")
    if not re.match(r"^\d+$", str(dados.get("cadencia") or "")):
        sys.exit(f"cadencia precisa ser numero puro, veio {dados.get('cadencia')!r}")
    # o filtro de instituto nao pode mostrar sobra de markup da Wikipedia
    sujos = [l.split(";")[1] for l in (dados["b_p1t"] + "\n" + dados["b_v1t"]).splitlines()
             if l and re.search(r"<|\[|ref name=", l.split(";")[1] if ";" in l else "")]
    if sujos:
        sys.exit("instituto com markup sobrando: " + ", ".join(sorted(set(sujos))[:5]))


def montar(dados, contador_url):
    modelo = MODELO.read_text(encoding="utf-8")
    troca = {m: str(dados[c]) for m, c in CAMPOS.items()}
    # contador_url é a BASE do serviço + namespace/chave, ex.:
    #   https://abacus.jasoncameron.dev|pedro-parreiracruz.github.io/corrida-2026
    # Aqui viram as duas URLs que a página usa: somar uma vez por aparelho, e só ler.
    if contador_url:
        base, _, alvo = contador_url.partition("|")
        base = base.rstrip("/")
        alvo = alvo.strip("/") or "corrida-2026"
        troca["__CONTADOR_HIT__"] = f"{base}/hit/{alvo}"
        troca["__CONTADOR_GET__"] = f"{base}/get/{alvo}"
    else:
        troca["__CONTADOR_HIT__"] = ""
        troca["__CONTADOR_GET__"] = ""
    # no site o número vem vivo a cada visita; o total gravado é só o caminho que o
    # artifact usa, e lá quem preenche é a tarefa diária
    troca["__CONTADOR_TOTAL__"] = "0"
    troca["__CONTADOR_DATA__"] = ""
    for marcador, valor in troca.items():
        if marcador not in modelo:
            sys.exit(f"o modelo nao tem o marcador {marcador} — modelo desatualizado?")
        modelo = modelo.replace(marcador, valor)
    # o modelo e um fragmento (o artifact injeta o esqueleto); aqui fechamos a pagina
    cabeca, resto = modelo.split("</title>", 1)
    return CABECA + cabeca + "</title>\n</head>\n<body>\n" + resto + "\n</body>\n</html>\n"


def main():
    p = argparse.ArgumentParser(description="Gera o painel publico da corrida presidencial 2026.")
    p.add_argument("--saida", default="docs/index.html", help="arquivo a escrever")
    p.add_argument("--dados", help="pasta com despejo local dos blocos (pula o Databricks)")
    p.add_argument("--contador", default=os.environ.get("CONTADOR_URL", ""),
                   help="URL do contador de aparelhos; vazio desliga o contador")
    args = p.parse_args()

    dados = do_despejo(args.dados) if args.dados else do_warehouse()
    conferir(dados)
    pagina = montar(dados, args.contador.strip())

    saida = pathlib.Path(args.saida)
    saida.parent.mkdir(parents=True, exist_ok=True)
    saida.write_text(pagina, encoding="utf-8")

    linhas = {c: len((dados[c] or "").splitlines()) for c in BLOCOS}
    print(f"gerado {saida} ({len(pagina) // 1024} KB)")
    print(f"  carga {dados['carga_utc']} | campo {dados['campo_inicio']} a {dados['campo_recente']}"
          f" | cadencia {dados['cadencia']}d")
    print("  linhas: " + ", ".join(f"{k.replace('b_', '')}={v}" for k, v in linhas.items()))
    print("  contador: " + (args.contador.strip() or "desligado"))


if __name__ == "__main__":
    main()
