"""Liga o SQL warehouse do Databricks e espera ficar RUNNING antes de qualquer consulta.

De 01 a 05/10/2026 o warehouse parado deixou de ligar sozinho quando chegava uma consulta
("Cannot create the resource, please try again later"), e toda carga falhou. No console,
o botao Start ligava na hora. Este script faz o mesmo que o botao (API /start) e espera o
estado RUNNING, com novas tentativas. Usa as mesmas variaveis da carga:
DATABRICKS_HOST, DATABRICKS_TOKEN e DATABRICKS_WAREHOUSE_ID.
"""
import os
import sys
import time

import requests

TENTATIVAS = 5          # pedidos de start
ESPERA_POR_TENTATIVA = 240  # segundos aguardando RUNNING depois de cada pedido


def main():
    host = os.environ["DATABRICKS_HOST"].replace("https://", "").rstrip("/")
    wid = os.environ["DATABRICKS_WAREHOUSE_ID"]
    s = requests.Session()
    s.headers["Authorization"] = "Bearer " + os.environ["DATABRICKS_TOKEN"]
    url = f"https://{host}/api/2.0/sql/warehouses/{wid}"

    def estado():
        r = s.get(url, timeout=60)
        r.raise_for_status()
        return r.json().get("state", "?")

    for tentativa in range(1, TENTATIVAS + 1):
        try:
            st = estado()
            if st == "RUNNING":
                print(f"warehouse RUNNING (tentativa {tentativa})")
                return 0
            if st in ("STOPPED", "STOPPING", "?"):
                if st == "STOPPING":
                    time.sleep(20)
                r = s.post(url + "/start", timeout=60)
                print(f"tentativa {tentativa}: estado {st}, pedido de start -> HTTP {r.status_code} {r.text[:200]}")
            else:
                print(f"tentativa {tentativa}: estado {st}, aguardando")
            fim = time.time() + ESPERA_POR_TENTATIVA
            while time.time() < fim:
                time.sleep(10)
                st = estado()
                if st == "RUNNING":
                    print(f"warehouse RUNNING (tentativa {tentativa})")
                    return 0
        except requests.RequestException as erro:
            print(f"tentativa {tentativa}: erro de rede {erro}")
        time.sleep(30 * tentativa)
    print("::error title=Warehouse nao ligou::o SQL warehouse do Databricks nao ficou RUNNING "
          f"depois de {TENTATIVAS} pedidos de start (Cannot create the resource?)")
    return 1


if __name__ == "__main__":
    sys.exit(main())
