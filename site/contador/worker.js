/**
 * Contador de aparelhos do painel Corrida Presidencial 2026.
 *
 * Conta APARELHOS, não pessoas: a página gera um id aleatório por navegador e o guarda
 * no localStorage. Aqui só chega esse id — nada de IP, nada de identificação pessoal.
 *
 * Por que não IP: IP é dado pessoal sob a LGPD, e como métrica é pior — todo mundo no
 * mesmo Wi-Fi compartilha um, e celular troca de IP o tempo todo.
 *
 * Deploy: Cloudflare Workers, plano gratuito. Precisa de um KV namespace ligado como
 * ACESSOS e da variável ORIGEM com o domínio do site.
 */

const CORS = origem => ({
  'access-control-allow-origin': origem,
  'access-control-allow-methods': 'POST, OPTIONS',
  'access-control-allow-headers': 'content-type',
  'access-control-max-age': '86400',
  'vary': 'origin'
});

export default {
  async fetch(req, env) {
    const permitidas = (env.ORIGEM || '').split(',').map(s => s.trim()).filter(Boolean);
    const origem = req.headers.get('origin') || '';
    const liberada = permitidas.includes(origem) ? origem : permitidas[0] || '';

    if (req.method === 'OPTIONS') return new Response(null, {status: 204, headers: CORS(liberada)});

    // GET /total: só devolve o número, não conta nada. É por aqui que a publicação diária
    // do artifact lê o total para gravar dentro do HTML — o artifact do claude.ai é
    // isolado da rede e não consegue perguntar sozinho. Leitura é pública de propósito:
    // o número já aparece no painel, não há o que proteger.
    if (req.method === 'GET' && new URL(req.url).pathname === '/total') {
      const total = parseInt((await env.ACESSOS.get('total')) || '0', 10);
      return Response.json({total}, {headers: {'access-control-allow-origin': '*',
                                               'cache-control': 'public, max-age=300'}});
    }

    if (req.method !== 'POST')    return new Response('método não permitido', {status: 405, headers: CORS(liberada)});
    if (permitidas.length && !permitidas.includes(origem))
      return new Response('origem não permitida', {status: 403, headers: CORS(liberada)});

    let id;
    try { id = (await req.json()).id; } catch (e) { id = null; }
    // aceita só o formato que a página gera: evita alguém inflar o número com lixo
    if (typeof id !== 'string' || !/^[a-z0-9-]{8,64}$/i.test(id))
      return new Response('id inválido', {status: 400, headers: CORS(liberada)});

    const chave = 'ap:' + id;
    const novo = (await env.ACESSOS.get(chave)) === null;

    if (novo) {
      // 400 dias: aparelho que some da base volta a contar, o que é honesto
      await env.ACESSOS.put(chave, '1', {expirationTtl: 60 * 60 * 24 * 400});
      const atual = parseInt((await env.ACESSOS.get('total')) || '0', 10);
      await env.ACESSOS.put('total', String(atual + 1));
      return Response.json({total: atual + 1, novo: true}, {headers: CORS(liberada)});
    }

    const total = parseInt((await env.ACESSOS.get('total')) || '0', 10);
    return Response.json({total, novo: false}, {headers: CORS(liberada)});
  }
};
