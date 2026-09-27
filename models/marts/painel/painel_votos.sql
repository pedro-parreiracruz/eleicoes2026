-- Base do painel: painel_votos_todos so com as pesquisas que tem registro localizado no TSE
-- (painel_registro_tse), com o numero do registro, a empresa registrada, o tipo de
-- contratacao e o nivel de confianca. Pesquisa sem registro nao aparece em bloco nenhum.
select v.*,
       r.nr_protocolo_registro,
       r.nm_empresa_registro,
       r.tp_contratacao,
       r.pc_nivel_confianca
from {{ ref('painel_votos_todos') }} v
join {{ ref('painel_registro_tse') }} r using (id_pesquisa)
