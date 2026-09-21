# Painel público + contador de aparelhos

Por que sair do artifact: a página publicada no claude.ai é **isolada da rede externa**.
Testei os quatro tipos de endpoint e todos foram bloqueados — inclusive o CDN que a
própria plataforma libera para carregar script. Sem chamada externa, o contador só
funcionaria com o armazenamento da plataforma, e esse torna a página interna da
organização, matando o link público. Hospedando fora, você tem os dois.

## O que tem nesta pasta

| arquivo | para que serve |
| --- | --- |
| `modelo.html` | o painel inteiro, com marcadores `__CARGA__`, `__P1T__`… no lugar dos dados. É o mesmo arquivo publicado no artifact. |
| `gerar.py` | consulta o Databricks, preenche os marcadores e escreve o `docs/index.html`. |
| `contador/worker.js` | Cloudflare Worker que conta aparelhos distintos. |
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

A contagem por aparelho distinto é feita no navegador: na primeira visita a página
chama a URL que soma e deixa uma marca no `localStorage`; nas visitas seguintes chama
só a que lê. O `gerar.py` recebe as duas de uma vez, no formato `base|namespace/chave`:

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
então ela não consegue perguntar o número a ninguém. A saída é gravar o número dentro
do HTML na hora de publicar. Quem faz isso é a tarefa agendada que republica o
artifact todo dia: ela lê `CONTADOR_URL` no arquivo, faz um `GET <url>/total` no
Worker e escreve o resultado em `CONTADOR_TOTAL` / `CONTADOR_DATA`.

Por isso o rótulo muda conforme a origem do número:

- no site, "aparelhos" — número do momento, a cada visita;
- no artifact, "aparelhos até 19/09" — número do dia da última publicação.

Os dois contam a mesma coisa: aparelhos que abriram **o site**. Quem abre só o link
do artifact não entra na conta, porque de lá não sai chamada nenhuma. Enquanto o
Worker não estiver no ar, `CONTADOR_TOTAL` fica em `0` e o chip nem aparece.

### O que ele conta, e o que não conta

Cada navegador gera um id aleatório na primeira visita e guarda no `localStorage`.
Só esse id chega ao Worker — **nenhum IP, nenhum dado pessoal**.

Conta aparelho, não pessoa:

- quem limpa os dados do navegador conta de novo;
- aba anônima conta de novo;
- a mesma pessoa no celular e no computador conta duas vezes;
- quem bloqueia `localStorage` recebe um id efêmero e conta a cada visita.

É medida de alcance, não de audiência. Se você precisar de audiência de verdade —
páginas vistas, origem do acesso, retorno — a ferramenta certa é GoatCounter ou
Plausible, que não usam cookie e continuam sem guardar dado pessoal.

Sobre IP, já que você perguntou: JavaScript no navegador **nunca** enxerga o IP de
quem acessa — só o servidor que entrega a requisição vê. E no Brasil IP é dado
pessoal sob a LGPD, o que traria obrigação de base legal e de aviso de privacidade
para uma métrica que, além de tudo, é pior: todo mundo no mesmo Wi-Fi compartilha um
IP e celular troca de IP o tempo todo.

## 3. Atualização diária

Com o `gerar.py` no repositório o painel se atualiza sozinho: o
`publicar_site.yml` dispara quando a carga termina com sucesso, regenera o
`docs/index.html` e só faz commit se o conteúdo mudou.

A tarefa agendada que republica o artifact continua existindo em paralelo — as duas
leem exatamente a mesma consulta. Quando o site do GitHub Pages estiver no ar e
estável, o artifact vira cópia de conveniência e a tarefa agendada pode ser
desligada.

## Quando o modelo mudar

`modelo.html` é uma cópia do painel. Se você editar o visual direto no artifact,
traga a versão nova para cá antes de publicar o site, senão o GitHub Pages fica para
trás. O `gerar.py` aborta se um marcador sumir do modelo, então uma cópia incompleta
falha alto em vez de gerar página quebrada.
