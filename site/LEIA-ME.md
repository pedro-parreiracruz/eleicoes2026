# Painel público + contador de acessos

Por que sair do artifact: a página publicada no claude.ai é **isolada da rede externa**.
Testei os quatro tipos de endpoint e todos foram bloqueados — inclusive o CDN que a
própria plataforma libera para carregar script. Sem chamada externa, o contador só
funcionaria com o armazenamento da plataforma, e esse torna a página interna da
organização, matando o link público. Hospedando fora, você tem os dois.

## O que tem nesta pasta

| arquivo | para que serve |
| --- | --- |
| `modelo.html` | o painel inteiro, com marcadores `__CARGA__`, `__P1T__`… no lugar dos dados. É o mesmo arquivo publicado no artifact. |
| `gerar.py` | lê os modelos `painel_*` do dbt no Databricks, preenche os marcadores e escreve o `docs/index.html`. |
| `contador/worker.js` | Cloudflare Worker, alternativa ao serviço de contagem aberto. |
| `contador/wrangler.toml` | configuração do deploy do Worker. |

E em `.github/workflows/publicar_site.yml`, o passo que roda o `gerar.py` depois da
carga diária e faz push do `docs/index.html`.

## 1. Publicar o site

    python site/gerar.py --saida docs/index.html
    git add docs/index.html && git commit -m "painel público" && git push

Depois, em **Settings → Pages**: Source `Deploy from a branch`, Branch `main`, pasta
`/docs`. Em um ou dois minutos o painel está em
`https://pedro-parreiracruz.github.io/eleicoes2026/`.

O `gerar.py` precisa de três variáveis de ambiente (as mesmas do workflow de carga):
`DATABRICKS_HOST`, `DATABRICKS_WAREHOUSE_ID` e `DATABRICKS_TOKEN`. Ele roda **uma**
consulta só e se recusa a escrever o arquivo se algum bloco vier vazio, se alguma
data vier estranha ou se sobrar markup da Wikipédia em nome de instituto — melhor
não publicar do que publicar quebrado.

Para mexer no visual sem gastar warehouse, dá para gerar a partir de um despejo local
dos mesmos blocos:

    python site/gerar.py --dados caminho/para/dados --saida /tmp/index.html

A pasta precisa ter `PESQUISAS1T.txt`, `VALORES1T.txt`, `DUELOS2T.txt`,
`INSTITUTOS.txt`, `INSTITUTOSMES.txt` e, opcionalmente, um `META.json` com
`carga_utc`, `campo_recente`, `campo_inicio` e `cadencia`.

## 2. O contador

O contador já existe e já está ligado — não precisa instalar nada. Ele usa o
**Abacus**, um serviço gratuito de contagem que não pede conta nem chave:

    namespace: pedro-parreiracruz.github.io
    chave:     corrida-2026
    somar:     https://abacus.jasoncameron.dev/hit/pedro-parreiracruz.github.io/corrida-2026
    ler:       https://abacus.jasoncameron.dev/get/pedro-parreiracruz.github.io/corrida-2026

O contador conta **acessos**: cada vez que a página é aberta ou recarregada soma 1, de
qualquer aparelho. A página chama a URL que soma a cada carregamento; a de leitura fica para
a tarefa diária que grava o número no artifact. Nada é guardado no aparelho de quem visita.
O `gerar.py` recebe as duas de uma vez, no formato `base|namespace/chave`:

    python site/gerar.py --saida docs/index.html \
      --contador "https://abacus.jasoncameron.dev|pedro-parreiracruz.github.io/corrida-2026"

No workflow isso vem da variável `CONTADOR_URL` do repositório (**Settings → Secrets
and variables → Actions → Variables**, environment `producao`). Vazia, o contador
simplesmente não aparece e a página funciona igual.

O que você aceita ao usar um serviço aberto assim: o número é público e **inflável**
— quem descobrir a URL pode chamá-la num laço; se o serviço sair do ar o chip some
(a página não quebra); e o contador expira após 6 meses sem nenhum acesso.

Se um dia quiser infraestrutura própria, `contador/worker.js` é um Cloudflare Worker
que faz o mesmo com validação de id e sem ninguém no meio:

    cd site/contador
    npx wrangler login
    npx wrangler kv namespace create ACESSOS     # copie o id devolvido
    # cole o id em wrangler.toml, e ajuste ORIGEM para o domínio do seu site
    npx wrangler deploy

Ele responde `{"total": N}` em `POST /` e `GET /total`, e a página aceita tanto
`value` quanto `total` — então é só trocar a `CONTADOR_URL` e republicar.

### E no artifact do claude.ai?

A página publicada lá é isolada da rede: nenhuma chamada externa sai de dentro dela,
então ela não consegue perguntar o número a ninguém nem somar acesso. A saída é gravar o
número dentro do HTML na hora de publicar: a tarefa agendada que republica o artifact
todo dia lê `CONTADOR_GET` (sem cache) e escreve o resultado em `CONTADOR_TOTAL` /
`CONTADOR_DATA`. Ela só troca o número se o novo for maior — contador não diminui.

Por isso o rótulo muda conforme a origem do número:

- no site, "acessos" — número do momento, somado a cada abertura;
- no artifact, "acessos até 21/09" — número do dia da última publicação.

Os dois mostram a mesma conta: acessos **ao site**. Quem abre só o link do artifact
não entra na conta, porque de lá não sai chamada nenhuma.

### O que ele conta

Cada abertura da página soma 1: recarregar conta, abrir em outra aba conta, a mesma
pessoa voltando amanhã conta de novo. Nada é guardado no aparelho de quem visita e
**nenhum IP ou dado pessoal** sai da página — ela só chama a URL de soma.

Até 21/09/2026 o contador contava aparelhos distintos; a partir daí passou a contar
acessos e seguiu do mesmo número (12), sem zerar.

Sobre IP, já que você perguntou: JavaScript no navegador **nunca** enxerga o IP de
quem acessa — só o servidor que entrega a requisição vê. E no Brasil IP é dado
pessoal sob a LGPD, o que traria obrigação de base legal e de aviso de privacidade
para uma métrica que, além de tudo, é pior: todo mundo no mesmo Wi-Fi compartilha um
IP e celular troca de IP o tempo todo.

## 3. Atualização automática

Tudo roda nos servidores do GitHub (nenhum computador precisa estar ligado), em
`.github/workflows/carga_eleicoes.yml`, com dois agendamentos (horário de Brasília):

- **05:17, carga completa:** TSE + Wikipédia → dbt build → site.
- **06:07, 09:07, 12:07, 15:07 e 18:07, checagem:** baixa só a tabela da Wikipédia e tira uma
  impressão digital dela (`ingestion/verificar_wikipedia.py`, mesmo leitor da carga). Se for
  igual à da última carga que foi para o site, para ali — sem ligar o Databricks. Se mudou,
  carrega a Wikipédia, roda o dbt e republica. A impressão da última carga fica no cache do
  Actions (`wiki-<hash>`), gravada pelo job "Lembrar tabela carregada" só quando carga, dbt
  e site deram certo.

O GitHub pode atrasar ou pular agendamentos em horário de pico; o próximo compensa.

A tarefa agendada que republica o artifact continua existindo em paralelo — as duas
leem os mesmos modelos `painel_*` (com a consulta antiga como reserva). Quando o site do GitHub Pages estiver no ar e
estável, o artifact vira cópia de conveniência e a tarefa agendada pode ser
desligada.

## Fonte dos dados e rollback

Toda a regra do painel mora no dbt, em `models/marts/painel/`:

| modelo | bloco do painel |
| --- | --- |
| `painel_votos` | base: instituto limpo + perfil do cenário (quantos candidatos, quantos fora da urna) |
| `painel_1t_pesquisas` / `painel_1t_valores` | 1º turno (só cenários com a lista oficial) |
| `painel_2t_duelos` | simulações de 2º turno |
| `painel_institutos` / `painel_institutos_mes` | mercado de pesquisas registradas no TSE |
| `painel_metadados` | hora da carga, janela de campo, cadência |

A lista de candidatos registrados virou o seed `candidatos_registrados.csv`. Cada modelo
tem as colunas legíveis e mais `linha` (o texto exato que vai para o HTML) e `nr_ordem`.
O `gerar.py` só junta as linhas. No Databricks, **Catalog → workspace → marts →
painel_… → Lineage** mostra o caminho inteiro desde `raw_eleicoes`.

A consulta antiga continua dentro do `gerar.py` como `CONSULTA_LEGADA`. Há três níveis
de volta:

1. **Automático.** Se os modelos não existirem ou um bloco reprovar na checagem (vazio,
   instituto sem nome, data estranha), o `gerar.py` usa a consulta antiga sozinho e deixa
   um aviso amarelo "Painel caiu na consulta antiga" no run do Actions.
2. **Uma vez, na mão.** Actions → *Publicar painel* → *Run workflow* → fonte `consulta`.
3. **Para todas as cargas.** Settings → Environments → `producao` → variável
   `PAINEL_FONTE` = `consulta`. Apagar a variável (ou pôr `dbt`) volta aos modelos.
   Localmente: `python site/gerar.py --fonte consulta`.

E se quiser o código exatamente como era, a tag git `painel-consulta-legada` marca o
último commit antes da mudança:

    git checkout painel-consulta-legada -- site/gerar.py .github/workflows/publicar_site.yml

Os modelos novos podem ficar no projeto sem atrapalhar; a consulta antiga não depende
deles.

## Quando o modelo mudar

`modelo.html` é uma cópia do painel. Se você editar o visual direto no artifact,
traga a versão nova para cá antes de publicar o site, senão o GitHub Pages fica para
trás. O `gerar.py` aborta se um marcador sumir do modelo, então uma cópia incompleta
falha alto em vez de gerar página quebrada.
