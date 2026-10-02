"""Confere no DivulgaCandContas (TSE) se o plano de governo de algum candidato mudou.

O resumo da aba Propostas (constante PROP em site/modelo.html) foi lido de um PDF
especifico de cada candidatura. A campanha pode protocolar uma versao nova; o TSE entao
troca o arquivo do tipo 5 ("proposta de governo") no registro. Este script compara, para
cada candidato a presidente, o id do PDF que o painel leu com o(s) id(s) do tipo 5 que o
TSE mostra hoje, e grava site/propostas_tse.json:

  alteracoes            candidato do painel cujo PDF lido nao esta mais no registro
  sem_plano_no_painel   candidato registrado que o painel ainda nao resume
  fora_da_lista         candidato do painel que saiu da lista do TSE

O arquivo so e regravado quando o resultado muda (o campo "atualizado" marca quando).
Nao le nem resume PDF: resumo de proposta e feito por gente, a partir do documento.
Saidas para o GitHub Actions: mudou=true|false e alertas=<n>.
"""
import datetime
import json
import os
import pathlib
import re
import sys

from curl_cffi import requests

BASE = "https://divulgacandcontas.tse.jus.br/divulga/rest/v1/candidatura"
ELEICAO = "2026/BR/20322002026"
CARGO_PRESIDENTE = "1"
TIPO_PROPOSTA = "5"
MODELO = pathlib.Path("site/modelo.html")
SAIDA = pathlib.Path("site/propostas_tse.json")


def get(url):
    r = requests.get(url, impersonate="chrome", timeout=60)
    r.raise_for_status()
    return r.json()


def saida_actions(**kv):
    caminho = os.environ.get("GITHUB_OUTPUT")
    if caminho:
        with open(caminho, "a", encoding="utf-8") as f:
            for k, v in kv.items():
                f.write(f"{k}={v}\n")


def main():
    prop = json.loads(re.search(r"const PROP = (\{.*?\});\n", MODELO.read_text(encoding="utf-8")).group(1))
    painel = {str(c["cid"]): c for c in prop["cands"] if c.get("cid")}
    anterior = json.loads(SAIDA.read_text(encoding="utf-8")) if SAIDA.exists() else {}
    desde_antes = {a["cid"]: a.get("desde") for a in anterior.get("alteracoes", [])}
    hoje = datetime.date.today().isoformat()

    lista = get(f"{BASE}/listar/{ELEICAO}/{CARGO_PRESIDENTE}/candidatos")["candidatos"]
    alteracoes, sem_plano, vistos = [], [], set()
    for c in lista:
        cid = str(c["id"])
        vistos.add(cid)
        det = get(f"{BASE}/buscar/{ELEICAO}/candidato/{cid}")
        planos = [{"id": str(a["idArquivo"]), "nome": a.get("nome", "")}
                  for a in (det.get("arquivos") or []) if str(a.get("codTipo")) == TIPO_PROPOSTA]
        p = painel.get(cid)
        if p is None:
            sem_plano.append({"cid": cid, "nome_urna": c.get("nomeUrna"),
                              "partido": (c.get("partido") or {}).get("sigla"), "planos": planos})
            continue
        usado = p["u"].rstrip("/").rsplit("/", 1)[-1]
        if usado not in {x["id"] for x in planos}:
            alteracoes.append({"cid": cid, "n": p["n"], "usado": usado, "novo": planos,
                               "desde": desde_antes.get(cid) or hoje})
    fora = [{"cid": cid, "n": p["n"]} for cid, p in painel.items() if cid not in vistos]

    novo = {"candidatos": len(lista), "alteracoes": alteracoes,
            "sem_plano_no_painel": sem_plano, "fora_da_lista": fora}
    velho = {k: v for k, v in anterior.items() if k != "atualizado"}
    mudou = novo != velho
    if mudou:
        novo["atualizado"] = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
        SAIDA.write_text(json.dumps(novo, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    alertas = len(alteracoes) + len(sem_plano) + len(fora)

    linhas = [f"- **{a['n']}**: o painel leu o PDF {a['usado']}; o TSE hoje mostra "
              + ", ".join(f"{x['id']} ({x['nome']})" for x in a["novo"]) for a in alteracoes]
    linhas += [f"- **{s['nome_urna']}** ({s['partido']}): registrado no TSE e sem resumo no painel" for s in sem_plano]
    linhas += [f"- **{f['n']}**: está no painel mas saiu da lista do TSE" for f in fora]
    pathlib.Path("alerta_propostas.md").write_text(
        "A conferência automática dos planos de governo no TSE encontrou:\n\n" + "\n".join(linhas)
        + "\n\nO painel já mostra o aviso e o link para a versão nova. O resumo das propostas "
          "precisa ser refeito a partir do PDF novo (site/modelo.html, constante PROP).\n",
        encoding="utf-8")
    print(f"{len(lista)} candidatos; {alertas} alerta(s); arquivo {'atualizado' if mudou else 'sem mudança'}")
    for l in linhas:
        print(l)
    saida_actions(mudou=str(mudou).lower(), alertas=alertas)
    return 0


if __name__ == "__main__":
    sys.exit(main())
