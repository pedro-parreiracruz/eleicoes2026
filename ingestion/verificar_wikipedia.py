"""Diz se a tabela de pesquisas da Wikipedia mudou desde a ultima carga, sem tocar no Databricks.

Usado pela checagem de hora em hora (carga_eleicoes.yml, job "verificar"). Baixa a pagina e
le as tabelas com exatamente as mesmas funcoes da carga (carga_raw.py) e tira um sha256 do
resultado. Assim a impressao digital so muda quando muda algo que a carga gravaria: edicao em
texto corrido, referencias ou formatacao da pagina nao disparam carga.

Saida: escreve `hash=<sha256>` e `linhas=<n>` em $GITHUB_OUTPUT (ou imprime, fora do Actions).
A comparacao com a ultima carga fica no workflow (cache do Actions com a chave wiki-<hash>).
"""
import hashlib
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from carga_raw import extrair_intencao_voto_2026, preparar  # noqa: E402

df = preparar(extrair_intencao_voto_2026())
impressao = hashlib.sha256(df.to_csv(index=False).encode("utf-8")).hexdigest()
saida = f"hash={impressao}\nlinhas={len(df)}\n"
print(saida, end="")
if os.getenv("GITHUB_OUTPUT"):
    with open(os.environ["GITHUB_OUTPUT"], "a", encoding="utf-8") as f:
        f.write(saida)
